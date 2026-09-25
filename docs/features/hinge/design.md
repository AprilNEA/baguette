---
description: Why iPhone Duo's hinge and hardware keys are driven by a guest-side HingeControl that reproduces dtuhidd's virtual HID events — the measured payloads, usages, reading path and packaging. Read before touching the hinge or foldable keys.
---

# Hinge — design

## Path

- **Drive:** `baguette hinge` / `POST /simulators/<udid>/hinge` / 3D socket `set_pose` → `Hinge.fold(to:over:)` (`HingeMotor`) → `GuestHingeMotor` → `xcrun simctl spawn <udid> <HingeControl> serve` (one per device, kept) → `HIDVirtualEventService` vendor event on an `avpCustom`-shaped service.
- **Keys:** `baguette press` / `POST …/input` / stream sockets → a foldable's `Input` is `FoldableInput` → `DeviceKeys` (also played by `GuestHingeMotor`) → `HingeControl button <page> <usage> <ms>` on a `mainScreenButtons`-shaped service.
- **Read:** `DevicectlHinge` → `xcrun devicectl device motion hinge-angle`.

## How the hinge is driven

Nothing on the host sets the hinge: `devicectl device motion
hinge-angle` only reads it, `simctl` has no verb, and Device Hub's
window is opaque to accessibility. Device Hub itself speaks CoreDevice's
`UniversalHIDService` — a Swift-only private API with no module
interface — to a daemon in the guest, `dtuhidd`
(`/usr/libexec/dtuhidd`, from CoreSimulator's iphoneos platform
support). That daemon owns a set of virtual HID services registered
with backboardd through the private `HID.framework`
(`HIDVirtualEventService`), one of which it names `avpCustom`: usage
page `0xFF61`, usage `0x5B`, transport `CoreDevice`. Every pose command
Device Hub sends is dispatched on it as a **vendor-defined
`IOHIDEvent`** (page `0xFF61`, usage `0x5B`, version 0) whose payload
is a small keyed record. Watched with a HID event monitor inside the
guest while Device Hub's picker ran:

```
{provider: "com.apple.Virtualization.VirtualMachines",
 source:   "hinge-slider-control",  type: "range", value: <degrees as double>}
{provider: "com.apple.Virtualization.VirtualMachines",
 source:   "orientation-picker-control", type: "enum", value: "portrait"}
```

The record's wire form: `d3 00 00 00`, then items of `[u24 aux][u8
type]` with the top bit of `type` marking a container's last entry —
`0x01` dictionary (aux = entry count), `0x08` key (NUL-terminated, aux
= length incl NUL), `0x09` string (aux = length), `0x04` double (aux =
`0x3f`, 8 bytes little-endian) — every item padded to 4 bytes. The
`provider` names the VM-based device stack these controls were built
for; the simulator's consumer accepts them from any service of that
shape.

So baguette ships **`HingeControl`** (`Injected/HingeControl/`), an
iOS-Simulator *executable* — the first non-dylib under `Injected/`,
built and staged by the same loop — which `GuestHingeMotor` starts once
per device with `xcrun simctl spawn <udid> <HingeControl> serve` and
keeps: it registers a service of the same shape and plays each line it
is written on stdin (`sweep <from> <to> <ms>` at 60 Hz with Device
Hub's ease-out, `angle <deg>`, `orientation <native-value>`). The public
rotation command uses the same helper in one-shot mode instead. The encoder
reproduces Device Hub's payload byte for byte. Sweeps queue behind one
another; a pose costs no spawn after the first (~0.9 s round trip for
Device Hub's 0.8 s sweep). `SharedHinge.fold(to:over:)` starts each
sweep from the angle last heard — or shut, as the device boots, when
nothing has been heard — and `DevicectlHinge` reads the sweep back like
any other, so the page, `litPanel` and the chrome all follow.

A background `simctl spawn` of the tool (`&` in a subshell) once
delivered nothing — run it in the foreground / keep `serve` alive.
Spawned guest tools need `codesign -s -` and the iphonesimulator SDK
target. To inspect such events again, a guest HID monitor is
`HIDEventSystemClient initWithType:1` (monitor) +
`IOHIDEventGetDataValue` with field base `1<<16`.

`orientation-picker-control` is Device Hub's rotate button by the same
route (`HingeMotor.turn(to:)`). Its native values are `portrait`, `pud`,
`landscape-left`, and `landscape-right`; camel-case names such as
`landscapeLeft` are silently ignored. The public CLI and HTTP route detect
multiple integrated panels and use this guest route; single-panel devices
retain the Purple event. Rotation uses a bounded one-shot helper invocation
so a short-lived CLI cannot exit before its queued input is processed.

The one-shot helper validates its native orientation values and exits with
status 2 for invalid arguments or 1 for a rejected HID dispatch. The host
waits up to eight seconds, then kills a stalled child and reports a timeout.
Diagnostic output alone is not failure. Failure to read the device's panel
configuration is also an error; it must not select the legacy path by default.

Physical orientation can differ from an app's interface orientation. The
browser's model roll is a separate presentation transform. Rotation can run
while a hinge sweep is in progress; callers that need a specific sequence
must wait for each operation before starting the next.

## Reading the hinge back

Device Hub streams the angle into the guest as HID reports
(`UniversalHID` → `dtuhidd` → `kIOHIDEventTypeHingeAngle` → CoreMotion
→ SpringBoard's pose provider), and SpringBoard decides which panel to
light. baguette reads it with `devicectl device motion hinge-angle`
(`DevicectlHinge`): the first sample is the current angle and lands in
~0.3 s, and only a device with several integrated panels
(`IntegratedPanels.several`) ever asks. Device Hub's closed pose reads
≈3°, its open pose ≈130°; SpringBoard goes landscape on its own when
open. `devicectl`'s hinge stream can go silent after a SpringBoard
restart (`baguette heal`) — it then reports nothing until Device Hub
moves the pose — so the shared hinge remembers such silence for three
seconds rather than making every caller wait it out. By hand:

```bash
xcrun devicectl device motion hinge-angle --device <UDID> --timeout 5
```

What the lit panel binds (framebuffer, digitizer, chrome, tap
space, AX point size, rotation) is in
[iPhone Duo](../iphone-duo/README.md).

## The hardware keys go the same way

On iPhone Duo the legacy button press does not work. `baguette press
--button volume-up` builds its `IndigoHIDMessageForHIDArbitrary` for
the lit panel's digitizer target, and the guest *does* get it — a HID
monitor sees consumer page `0x0C` usage `0xE9` down and up — but on a
**touchscreen** service (usage page `0x0D` usage `0x04`), and
SpringBoard's volume, sleep/wake and camera-control handling ignores a
key from there. Device Hub's buttons arrive on another of `dtuhidd`'s
services, `mainScreenButtons` (usage page `0x0B` usage `0x01`, built-in,
transport `CoreDevice`), as plain keyboard `IOHIDEvent`s held a quarter
second. Measured with the same monitor, one click each in Device Hub:

| Device Hub button | page | usage |
|---|---|---|
| volume up | `0x0C` | `0xE9` |
| volume down | `0x0C` | `0xEA` |
| power (sleep/wake) | `0x0C` | `0x30` |
| camera control | `0xFF00` | `0x66` |

`HingeControl` registers a second service of that shape and presses
them: `button <page> <usage> <ms>`. On the host, `DeviceKeys` is the
domain role (`GuestHingeMotor` plays it as well, one serving child per
device), and a foldable's `Input` is `FoldableInput`: touches go to the
lit panel's digitizer as before, and a `DeviceButton` with a Device Hub
key (`power`, `lock`, `volume-up`, `volume-down`, `action`) goes to the
guest, held `duration` seconds or Device Hub's 0.25 s. The CLI, the
`POST …/input` route and the stream sockets all press through it
without change; `home` and the edge gestures still take the legacy
path. Single-panel devices are untouched — `SimulatorKitDisplay` wraps
the input only when the device has several panels.

## Packaging

`HingeControl` follows the injected dylibs exactly: built fat by
`Injected/build.sh` (host-arch-only under `BAGUETTE_INJECTED_ARCHS`),
staged under `Sources/Baguette/Resources/HingeControl/`, `.copy`'d by
`Package.swift`, and installed by `InjectedDylibInstaller` (kind
`.executable`, env override `BAGUETTE_HINGECONTROL_TOOL`) into the
content-hashed build directory with `0755`. The one difference is the
link: an executable, so no `-dynamiclib` / `-install_name`.

The homebrew-core formula rebuilds every injected product from source
for the host arch (`brew audit` rejects the committed universal
binaries), mirroring each `build.sh`; it needs one more entry for this
one:

```ruby
# Executable spawned in the guest, not a dylib: same sources layout, plain link.
tool = "Sources/Baguette/Resources/HingeControl/HingeControl"
rm tool
system "xcrun", "clang", "-arch", arch, "-isysroot", sdk,
       "-target", "#{arch}-apple-ios17.0-simulator", "-fobjc-arc",
       "-framework", "Foundation", "-Wl,-adhoc_codesign",
       "-o", tool, *Dir["Injected/HingeControl/Sources/*.m"]
```

## Dead ends

- CoreDevice's `UniversalHIDService` is Swift-only with no swiftmodule
  anywhere — not callable from baguette.
- A SpringBoard shim (swizzling `CMAngleManager` to feed fabricated
  `CMAngle`s) worked too, but needed an injected dylib and a SpringBoard
  restart; it is not shipped.
- The legacy Indigo button press reaches the Duo's guest on a
  touchscreen service and is ignored (above).
