---
description: Tap, swipe and stream single-finger touches on a simulator, including the home-indicator and top-edge system gestures (home, app switcher, lock screen, Notification Center). Use when a flow needs coordinate input or an edge swipe.
---

# Touches & edge gestures

Coordinate input on iOS 26 / Xcode 26 — taps, swipes, streaming single-finger
touches, and the system gestures that start at a screen edge. Every flag:
[commands.md#baguette-tap](../../commands.md#baguette-tap),
[#baguette-swipe](../../commands.md#baguette-swipe),
[#baguette-press](../../commands.md#baguette-press). Coordinates are in device
points, with the screen's `width` / `height` alongside.

## Quick start

```bash
baguette tap   --udid <UDID> --x 220 --y 480 --width 440 --height 956
baguette swipe --udid <UDID> --start-x 220 --start-y 800 --end-x 220 --end-y 200 \
               --width 440 --height 956
baguette press --udid <UDID> --button swipe-to-home
```

In `baguette serve`, click / drag on the focus-mode canvas. A drag from the
bottom 7 % streams with `edge: bottom` (iOS animates the home / app-switcher
preview live); a drag from the top 7 % streams with `edge: top` (iOS pulls the
lock-screen cover sheet from a top-left origin or Notification Center from a
top-right origin). Both follow your actual drag speed — no canned playback on
release.

## System gestures

iOS tells these apart purely by velocity, dwell and start-x — baguette doesn't
run a client-side discriminator; the same UX as Simulator.app. The four canned
shapes are buttons:

| Button | Shape | iOS does |
|--------|-------|----------|
| `swipe-to-home` | Quick flick up from `y ≈ 1.0` to `y ≈ 0.3` over ~12 × 16 ms steps, `edge=bottom` | Home — back to the home screen |
| `swipe-to-app-switcher` | Slow drag up from `y ≈ 1.0` to `y ≈ 0.58` over ~30 × 35 ms steps + ~900 ms dwell at midpoint, `edge=bottom` | App Switcher — multitasking cards |
| `pull-down-to-lock-screen` | Slow drag down from `(0.25, 0.0)` to `(0.25, 0.55)` over ~24 × 25 ms steps, `edge=top` | Pulls the **Lock Screen** cover sheet down |
| `pull-down-to-notification-center` | Slow drag down from `(0.75, 0.0)` to `(0.75, 0.55)` over ~24 × 25 ms steps, `edge=top` | Opens **Notification Center** |

```bash
baguette press --udid <UDID> --button swipe-to-app-switcher
baguette press --udid <UDID> --button pull-down-to-notification-center
```

Use the buttons when you don't need live-preview feedback (CLI scripts,
`baguette input` stdin) — each is a single dispatch instead of a chain. The
canonical `app-switcher` button is a double home press, not a gesture — see
[buttons](../buttons/README.md).

## Wire

`tap`, `swipe` and the streaming `touch1-down` / `touch1-move` / `touch1-up`
envelopes go over `baguette serve`'s WebSocket and `baguette input`'s stdin;
they're specified in [wire.md](../../wire.md). The one field specific to this
feature is `edge` — `bottom` (home / app switcher), `top` (lock screen /
Notification Center), `left` or `right`; omit it for an interior touch. It
rides `tap` as well as `touch1-*`:

```json
{ "type": "touch1-down", "x": 220, "y": 950, "width": 440, "height": 956, "edge": "bottom" }
{ "type": "touch1-move", "x": 220, "y": 500, "width": 440, "height": 956, "edge": "bottom" }
{ "type": "touch1-up",   "x": 220, "y": 500, "width": 440, "height": 956, "edge": "bottom" }
{ "type": "tap", "x": 742, "y": 44, "width": 800, "height": 480, "edge": "top" }
```

A `tap` with `edge` and a `touch1-down`/`touch1-up` pair at the same point
produce identical messages. Reach for it when a control sits inside an edge
band and a browser touch works where an unflagged wire tap does not; the
CarPlay map template's nav bar is the case that surfaced the gap
([companion-screens](../companion-screens/README.md)). An unrecognised `edge`
is rejected (`invalid edge: expected left | top | right | bottom`) rather than
quietly demoted to an interior touch. The finger identifier is handled for you:
fresh on `touch1-down`, reused through `touch1-up`.

## Gotchas

- **Input success confirms transmission, not app handling.** A transport timeout
  reports failure with an unknown delivery outcome; check the app before retrying.
  See [dispatch semantics](design.md#5-dispatch) for the per-message wait and cleanup.
- **Edges are physical, not visual, when rotated.** A CLI / wire caller passing
  `edge: bottom` while the device is rotated will *not* fire the home gesture.
  Send the orientation-appropriate edge for a visual-bottom drag: `portrait` →
  `bottom`, `landscape-left` → `right`, `portrait-upside-down` → `right`,
  `landscape-right` → `top`. Or use the `swipe-to-app-switcher` /
  `swipe-to-home` buttons, which always run from the device's portrait bottom
  and let iOS handle the rotation. The page rotates `edge` for you, and
  `app-switcher` is rotation-agnostic.
- **Pinch needs two fingers.** Single-finger streaming (`touch1-*`) routes
  correctly but `UIPinchGestureRecognizer` treats it as an interactive pan;
  prefer `touch2-*` for pinch / multi-finger.
- **The phone by default.** To touch a CarPlay / external display, pass
  `baguette input --display carplay` — see [companion-screens](../companion-screens/README.md).
- **Xcode 27:** once Device Hub attaches, taps can report ok and never land
  until healed — see [device-hub](../device-hub/README.md).

## See also

- [design.md](design.md) — the digitizer recipe, the byte patches and how they were found
- [buttons](../buttons/README.md) · [companion-screens](../companion-screens/README.md) · [device-hub](../device-hub/README.md)
