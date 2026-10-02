---
description: Why real-iPhone CarPlay reaches the page by capturing Apple's CarPlay Simulator window and clicking into it — what was spiked, why postToPid and in-process access fail, and why no third-party CarPlay receiver is used. Read before touching head-unit.
---

# Head unit: design

**Status: designed and spiked, not implemented.** Spiked 2026-10-01 on
macOS 27, Xcode 27.0, CarPlay Simulator (Additional Tools, bundle
`com.apple.CarPlaySimulator`) with a physical iPhone attached.

A *head unit* is the screen in a car's dashboard. Apple's CarPlay Simulator
plays one on the Mac: a real iPhone connects to it and draws CarPlay into its
window. baguette shows that window in the page's external pane and forwards
taps and drags back into it. It is the dependable CarPlay path while
simulator CarPlay is blocked on Xcode 27 —
see [companion-screens](../companion-screens/design.md#xcode-27-no-simulatorapp-and-carplay-doesnt-come-up).

## Shape

```
?display=headunit ─▶ StreamDisplayPlan.bind ─▶ (HeadUnitScreen, HeadUnitInput)
frames ◀─ MJPEG/H.264 ◀─ HeadUnitScreen ◀─ ScreenCaptureKit window capture
taps   ─▶ GestureDispatcher ─▶ HeadUnitInput ─▶ [MouseEvent] ─▶ Mouse (HostMouse)
rail   ─▶ companion-screens.json + "headUnit": {available,title,width,height}
```

- `DisplayKind.headUnit`, wire token `headunit` — a third plane beside
  `phone` and `carplay`, so the stream route, encoders and pane are reused.
- Pure Domain: `HeadUnitWindow.pick(from:)` (the CarPlay Simulator window
  among the host's windows) and the gesture → `[MouseEvent]` mapping in
  window points. Wire coordinates are window points, as with any plane.
- `@Mockable protocol Mouse` — the host pointer:
  `perform(_ events: [MouseEvent], in window: HeadUnitWindow) -> Bool`.
- Integration-only: `HeadUnitScreen` (ScreenCaptureKit), `HostMouse`
  (CGEvent), the host window list.
- Supported: tap, swipe, `touch1-*`. Buttons, keys and pinches answer
  `{"ok":false}` rather than being dropped. The window's own control strip
  (car, back, home, Siri, knob, media keys) is part of the captured frame,
  so those are clickable from the page.

## Finding the window

`SCShareableContent` lists it under bundle `com.apple.CarPlaySimulator`,
titled `CarPlay Simulator - <iPhone name>` — the title says which phone
is attached. The standalone app's windows are unambiguous; DeviceHub's
built-in CarPlay Simulator window belongs to DeviceHub (`com.apple.dt.Devices`)
alongside its phone windows and is left for later.

## Capturing it

An `SCStream` on `SCContentFilter(desktopIndependentWindow:)` delivered ~30
fps of live CarPlay, **every frame an IOSurface-backed `CVPixelBuffer`** —
exactly what `Screen.start(onFrame:)` hands the encoders. Two details:

- A command-line process must open its WindowServer connection first
  (`CGMainDisplayID()`), or ScreenCaptureKit asserts `CGS_REQUIRE_INIT`.
- Size = window frame × `filter.pointPixelScale`, with
  `captureResolution = .best`. Asking for 2× without them captured the
  window at 1× into a corner of a 2× buffer.

Needs **Screen Recording** for the process running baguette (for a
terminal inside an IDE, the IDE).

## Clicking into it

| Tried | Result |
| --- | --- |
| `CGEvent.postToPid` with the window id set on the event | Ignored — 0 pixels changed, with permission granted |
| Global events (`.cghidEventTap`) at the window's position | Tap opened Music; a 12-step drag scrolled a list; the window's Home button worked |
| Global events while another app is frontmost | Swallowed: the first click only activates the window (toolbar greys, nothing fires) |

So `HostMouse` does: activate CarPlay Simulator → wait 50 ms → post
down / drag… / up → wait 50 ms for the queue to drain → warp the cursor
back → re-activate the app that was frontmost. Measured: focus returns to
the previous app and the cursor to within a pixel. Without the drain
wait, the warp ran before the drag finished and the cursor ended ~650 px
away. Polling `NSWorkspace.frontmostApplication` for the activation doesn't
work without a run loop — it never updates — so the wait is fixed.

Consequences the user sees: CarPlay Simulator flicks to the front for each
gesture; it must be on screen (another window covering it is fine,
activation raises it; minimised or on another Space is not). Needs
**Accessibility** (`CGPreflightPostEventAccess`); without it events are
dropped silently, so the rail must report the missing permission.

## Dead ends

- **Getting frames from inside CarPlay Simulator.** `DYLD_INSERT_LIBRARIES`
  is ignored (Apple-signed with `com.apple.private.*` entitlements), and
  re-signing strips the entitlements it needs to reach the phone.
- **Loading its `CarPlaySDK.framework` in baguette.** The iPhone
  authenticates a head unit through
  `com.apple.security.attestation.access`, which only Apple-signed code holds.
- **DiPlay / xcertplay** (Android CarPlay receivers). They authenticate with
  an MFi chip, a remote signer, or an accessory key recovered from Carlinkit
  firmware (DiPlay's release APK), and are GPL-3.0 / AGPL-3.0. Apple's
  CarPlay Simulator already plays the car with Apple's own authentication.
  They can't drive the simulator either — see companion-screens.
