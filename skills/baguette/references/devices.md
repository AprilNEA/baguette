# Devices — get a simulator ready and know its shape

Read when: no device is booted, taps ack but nothing happens, you need the
screen size, or the device rotates or folds (iPhone Duo). Flags for every
command are in `commands.md`.

## Find, boot, shut down

```bash
baguette list                       # human-readable
baguette list --json                # {running, available}: pick a booted UDID
baguette boot --udid <UDID>         # waits for the boot to finish
baguette shutdown --udid <UDID>
baguette lifetime --detach          # keep devices booted when Simulator.app closes
```

Every command takes `--device-set <path>` for a device in a custom set.

## When input acks but lands nowhere: `heal`

Under Xcode 27, Device Hub can take over a device's input surface: every
gesture answers `{"ok":true}` and nothing happens on screen. `baguette boot`
repairs it on the way up; for a device booted some other way run
`baguette heal --udid <UDID>`. It restarts SpringBoard (running apps are
killed, the device is back in about four seconds). It comes back after Device
Hub is relaunched. See
[device hub](https://github.com/tddworks/baguette/blob/main/docs/features/device-hub/README.md).

## The screen's size — needed by every gesture

```bash
baguette chrome layout --udid <UDID> | jq '.screen | {width, height}'
# → {"width": 438, "height": 954}
```

Those are device points, the units every gesture's `width` / `height` take.
Read them per device and again after a rotation or a fold; never hardcode.

## Rotate

```bash
baguette orientation --udid <UDID> landscape-left
# portrait | landscape-left | landscape-right | portrait-upside-down
```

## iPhone Duo (Xcode 27.1, iOS 27.1)

One device, two panels: a cover lit while folded and a larger unfolded panel.
The hinge decides which is lit, and `tap`, `type`, `screenshot`, `stream`,
`describe-ui` and `chrome layout` all follow the **lit** panel.

```bash
baguette hinge --udid <UDID>                 # read: {"angleDegrees": 130.0}
baguette hinge --udid <UDID> --pose open     # closed (0°) | open (130°) | flat (180°)
baguette hinge --udid <UDID> --angle 72      # any angle 0–180
baguette chrome layout --udid <UDID>         # now the unfolded panel's size
```

It boots folded. After a fold, read `chrome layout` again before tapping.
Exit code `3` means the guest helper timed out: the move may have landed, so
read the hinge before retrying. Never power a panel off with
`simctl io … screenConfig`; it crash-loops SpringBoard. See
[iPhone Duo](https://github.com/tddworks/baguette/blob/main/docs/features/iphone-duo/README.md).

## CarPlay

`--display carplay` on `input`, `screenshot` and `stream` targets an attached
CarPlay display; add `--require-existing-display` to fail rather than enable
one. See
[companion screens](https://github.com/tddworks/baguette/blob/main/docs/features/companion-screens/README.md).

## Not wired

Physical devices (`/devices.json`, `WS /devices/:udid/stream`): the host side
exists but no companion app ships, so gestures are rejected with
`device control is not wired yet`. Simulators only.
