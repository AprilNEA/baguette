---
description: How baguette's taps, swipes and edge gestures become a real digitizer touch on iOS 26 — the IOHIDEvent recipe, the trackpad wrapper, the byte slots it patches, and how each was found.
---

# Touches — design

`IndigoHIDMessageForMouseNSEvent` — the path most public bridges
target — has a regression on Xcode 26: bare mouse-event taps either
get misinterpreted as the home gesture or silently drop. Our fix
doesn't try to coax that wrapper. We feed the simulator a real
`IOHIDEvent` shaped exactly like a hardware touch, run it through
`IndigoHIDMessageForTrackpadEventFromHIDEventRef`, and patch two
byte slots the SimulatorKit wrapper leaves uninitialised.

## Path

- `baguette tap` / `swipe`, the `tap` / `swipe` / `touch1-*` envelopes on
  `baguette input` and the stream WebSocket, and the page canvas →
  `Input.touch1(phase:at:size:edge:)` (streaming) or the `IndigoHIDInput`
  button cases for the canned `swipe-to-app-switcher` / `swipe-to-home` /
  `pull-down-to-lock-screen` / `pull-down-to-notification-center` shortcuts.
- From there `IOHIDDigitizerDispatch.send(...)` builds + patches + dispatches a
  single touch event through `SimDeviceLegacyHIDClient`.
- Not on this path: hardware buttons, and the `app-switcher` button, which
  rides the home-button event source — two `IndigoHIDMessageForButton` presses
  ~150 ms apart (see [buttons/design.md](../buttons/design.md)).

## The recipe

Five steps. Each one is empirically verified — skip any of them and
iOS either ignores the touch or `backboardd` crashes.

### 1. Build a digitizer-finger event

```swift
IOHIDEventCreateDigitizerFingerEvent(
    nil, mach_absolute_time(),
    /*index*/ 0, /*identifier*/ id,
    /*eventMask*/ phase.eventMask,    // 0x07 down/move, 0x06 up
    x, y, 0.0,                         // normalised coords
    /*tipPressure*/ 0.0, /*twist*/ 0.0,
    /*range*/ phase.range, /*touch*/ phase.touch,
    /*options*/ 0
)
```

`eventMask` is a bitmask from `IOHIDFamily/IOHIDEvent.h`:

```
Range = 0x01   Touch = 0x02   Position = 0x04   Stop = 0x08
Peak  = 0x10   Identity = 0x20  Attribute = 0x40  Cancel = 0x80
```

Down + move use `0x07` (Range | Touch | Position) so iOS sees a
sustained touch with each event; up uses `0x06` (Touch | Position)
to signal lift. `tipPressure` stays at `0.0` — non-zero crashed the
simulator's HID processor in early probes.

### 2. Wrap in a digitizer-parent event

`IOHIDEventCreateDigitizerEvent` (transducer = Finger) → append the
finger as a child via `IOHIDEventAppendEvent`. Real iOS touches
arrive as parent + child IOHIDEvent pairs; a bare finger event
makes the SimulatorKit wrapper produce a 192-byte stub iOS ignores.
Parent + child produces a 384-byte two-record message that matches
the layout `IndigoHIDMessageForMouseNSEvent` writes for working
taps.

### 3. Run through the trackpad wrapper

```swift
IndigoHIDMessageForTrackpadEventFromHIDEventRef(parent)
```

`SimulatorKit.framework` exports three `*FromHIDEventRef` wrappers:

| Wrapper | Accepts digitizer events? |
|---------|---------------------------|
| `IndigoHIDMessageForPointerEventFromHIDEventRef`  | ❌ rejects |
| `IndigoHIDMessageForScrollEventFromHIDEventRef`   | untested |
| `IndigoHIDMessageForTrackpadEventFromHIDEventRef` | ✅ — what we use |

The trackpad path was the missing piece: it's the only wrapper that
accepts an `IOHIDEvent` of digitizer type and emits a structured
two-record Indigo message instead of returning `nil`.

### 4. Patch four byte slots

The wrapper leaves two fields uninitialised. iOS reads both; without
the patch the message arrives in an unconsumed channel and gets
dropped silently (visible as `dispatched: true` followed by no
visible reaction).

| Offset | Patch | Meaning |
|--------|-------|---------|
| `0x6c` (record 1) | `0x32` (UInt32) | `IndigoHIDTouchTarget` — routing tag iOS reads to send the touch to the digitizer subsystem |
| `0x10c` (record 2) | `0x32` | same target, mirrored on the child record |
| `0x3a` (record 1) | `0x04` (UInt8) when any edge bit is set, else `0x00` | "edges-present" flag |
| `0x3b` (record 1) | edge bitmask (UInt8) | left=`0x02`, right=`0x04`, top=`0x08`, **bottom=`0x01`**, none=`0x00` |
| `0xda` / `0xdb` (record 2) | mirror of 0x3a / 0x3b | same edge encoding on the child record |

The bitmask values were derived empirically by sweeping `edge=0..4`
through `IndigoHIDMessageForMouseNSEvent`'s 7-arg shape and diffing
the produced bytes — see the `--compare-with-mouse` flag on the
`diag-digitizer-trackpad` probe.

### 5. Dispatch

`SimDeviceLegacyHIDClient.send(message:freeWhenDone:completionQueue:completion:)`
queues the actual Mach send asynchronously. Returning from that method does not
mean the message has been sent. A one-shot CLI that exits immediately can stop
before its final touch-up leaves the process.

The shared message boundary waits for the `void (^)(NSError *nullable)`
completion on a dedicated queue. Supplying no callback queue would select the
main queue and deadlock synchronous input on the main thread. The callback
confirms Mach transmission or reports its error; it does not acknowledge guest
processing. Successful input therefore still needs an application-side check
when verifying an interaction.

The host wait is limited to five seconds per message, not per gesture. Cleanup
messages have their own waits. A timeout reports failure with an
unknown delivery outcome; it does not cancel queued framework work or retry the
message. Framework ownership continues after timeout, so a late callback remains
safe. Multi-event gestures attempt their matching releases after send failures.

This contract was checked against Xcode 26.6 SimulatorKit's Objective-C metadata,
Swift symbols and disassembly. Neither its simpler `send(message:)` overload nor
another exported method provides synchronous sending. The framework retains its
client until queued work ends; ordinary ARC lifetime is not the completion
problem.

## Phases

`IOHIDDigitizerDispatch.Phase` covers a touch sequence:

| Phase | `eventMask` | `range` | `touch` | When |
|-------|-------------|---------|---------|------|
| `down` | `0x07` (Range \| Touch \| Position) | `true`  | `true`  | initial press |
| `move` | `0x07` (sustained)                  | `true`  | `true`  | every position update during the drag — keeping Touch on prevents iOS from interpreting the move as a fresh tap |
| `up`   | `0x06` (Touch \| Position)           | `false` | `false` | finger lift |

A tap is `down → hold → up` at the same point. A swipe is
`down → N interpolated moves → up`. Identifiers are sticky on `down`
and reused until `up`, so iOS sees one continuous touch across the
chain.

## Edge gestures

`IOHIDDigitizerDispatch.Edge` flips the matching edge bit on every
event in a sequence: bottom = `0x01`, left = `0x02`, right = `0x04`,
top = `0x08` (with the "edges-present" flag `0x04` at offset `0x3a`).
This is the flag the simulator's system-gesture recognizers check to
decide whether a touch is an interior pan or a system-gesture
candidate.

iOS itself discriminates between gestures purely by velocity, dwell,
and start-x — *we don't* run a client-side discriminator. Same UX as
Simulator.app:

| Gesture | Dispatch shape |
|---------|----------------|
| **Quick flick up** from `y ≈ 1.0` to `y ≈ 0.3` over ~12 × 16 ms steps with `edge=bottom` | iOS fires Home — back to the home screen |
| **Slow drag up** from `y ≈ 1.0` to `y ≈ 0.58` over ~30 × 35 ms steps + ~900 ms dwell at midpoint with `edge=bottom` | iOS fires App Switcher — multitasking cards |
| **Slow drag down** from `(0.25, 0.0)` to `(0.25, 0.55)` over ~24 × 25 ms steps with `edge=top` | iOS pulls the **Lock Screen** cover sheet down |
| **Slow drag down** from `(0.75, 0.0)` to `(0.75, 0.55)` over ~24 × 25 ms steps with `edge=top` | iOS opens **Notification Center** |

The browser canvas auto-detects edge drags on mousedown — bottom
band (`y / r.height ≥ 0.93`) streams with `edge: "bottom"`; top
band (`y / r.height ≤ 0.07`) streams with `edge: "top"`. Both
switch to live `touch1-*` streaming at the user's actual drag
speed. iOS animates the corresponding system preview (home-card
for bottom, lock-screen cover sheet or notification center for
top) live as the cursor moves — no client-side buffering, no
canned playback on release.

## Where the bytes are decoded

If iOS ever changes any of the layout offsets, the `diag-digitizer-trackpad`
probe is the falsification surface:

```
baguette diag-digitizer-trackpad --udid <UDID> \
    --event-mask 0x07 --range --touch --with-parent \
    --x 0.5 --y 0.5 --dump --compare-with-mouse
```

- `--dump` prints the wrapper output as 16-byte hex rows.
- `--compare-with-mouse` builds the same coords through
  `IndigoHIDMessageForMouseNSEvent` (the working tap path) at
  `edge=0` and `edge=3` so you can diff layouts side-by-side.
- `--patch-target` and `--patch-edge bottom|...` toggle the patches
  individually so you can isolate which slot iOS depends on.
- `--cycle` does paired down→up; `--swipe-end-y` does down→N moves
  →up; `--swipe-dwell-ms` adds a midpoint hold.

The probe stays in the build as integration-only research scaffolding. It doesn't sit in any
production path — taps / swipes / touches go through
`IOHIDDigitizerDispatch` directly, not the probe.

## Known limits

- **`touch2-*` (two-finger streaming)** still rides the legacy
  `IndigoHIDMessageForMouseNSEvent` 9-arg signature. Pinch / pan
  with two coincident fingers continues to work via that path; we
  haven't ported it onto the digitizer recipe because the existing
  shape is verified and there's no live-preview feature gated on
  the swap.
- **Edge gesture remapping in landscape** — when the device is
  rotated, the user's *visual* bottom corresponds to a different
  *physical* edge in the portrait coord frame the message uses.
  The browser's orientation transport rotates the `edge` name
  alongside the coords so iOS's gesture recognizer sees a touch +
  edge flag pair on the matching physical edge. Verified mapping
  for a visual-bottom drag: `portrait` → `bottom`,
  `landscape-left` (raw=4) → `right`, `portrait-upside-down`
  (raw=2) → `right`, `landscape-right` (raw=3) → `top`.
  CLI / wire callers passing `edge: bottom` directly while the
  device is rotated will *not* fire the home gesture — they need
  to send the orientation-appropriate edge name from the table
  above, or use the `swipe-to-app-switcher` / `swipe-to-home`
  button shortcuts (which always run their canned shapes from the
  device's portrait bottom regardless of current orientation,
  then iOS handles the rotation internally). The canonical
  `app-switcher` button is rotation-agnostic by design — it's a
  pair of home-button events, no coordinates involved.
- **No carplay / external display targets** — `target = 0x32`
  (touch digitizer) is hard-coded. The dispatch helper would need
  a target parameter to support those, plus a way to route
  through the right `Indigo*Service` warm-up.
- **Single-finger pinch.** Single-finger streaming (`touch1-*`) routes
  correctly but `UIPinchGestureRecognizer` treats it as an interactive
  pan; prefer `touch2-*` for pinch / multi-finger.
