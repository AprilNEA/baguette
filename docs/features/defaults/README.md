---
description: Read, write and delete an installed app's persisted UserDefaults on a booted simulator, with every value typed, including App Group suites. Use to set up onboarding, feature-flag or preference scenarios before driving the UI.
---

# Defaults

Prepare an app's persisted preferences (its standard `UserDefaults`, an App
Group suite, or a suite of its own), then drive the UI with baguette. Values keep their type, a key
that was never stored reads differently from a stored `false` / `0` / `""`, and
nothing outside the key you name changes. Every flag:
[commands.md#baguette-defaults](../../commands.md#baguette-defaults).

## Quick start

```bash
# what's stored, typed
baguette defaults read   --udid <UDID> --bundle-id com.example.app --json

# reset onboarding, so the app starts from the new value
baguette defaults write  --udid <UDID> --bundle-id com.example.app \
  --key onboardingComplete --type bool --value false --relaunch

# remove one key (a no-op when it isn't stored)
baguette defaults delete --udid <UDID> --bundle-id com.example.app --key onboardingComplete

# an App Group suite: UserDefaults(suiteName: "group.com.example.shared")
baguette defaults read   --udid <UDID> --bundle-id com.example.app \
  --suite group.com.example.shared --key token --json
```

In `baguette serve`'s focus page, the toolbar's Defaults button (in the
Inspect group) opens a card that does the same: pick an app and a suite, edit
each value in place, add or delete keys, export or import a set, with
"Relaunch app after each change" on by default.

## Workflows

**Set up a scenario, then verify the UI.** Write each key with `--relaunch` on
the last one (or all of them). The app quits before the write and launches
after, so it starts from what you stored. Then `describe-ui` / `screenshot` as
usual.

**Save a setup once, restore it every run.** `export` prints the suite as
typed JSON (all keys, or the `--key`s you name); `import` writes those values
back, into whichever app and suite you name, and leaves other keys alone. With
`--relaunch` the app is quit once before the import and launched once after.

```bash
baguette defaults export --udid <UDID> --bundle-id com.example.app \
  --key onboardingComplete --key featureFlags > onboarding.json
baguette defaults import --udid <UDID> --bundle-id com.example.app \
  --file onboarding.json --relaunch            # --file - reads stdin
```

**Check a key, not just a value.** `read --key k --json` answers
`{"key":"k","present":false}` for a key that was never stored and
`{"key":"k","present":true,"type":"bool","value":false}` for a stored `false`.

## Types

| `--type` | `--value` | reads back as |
|---|---|---|
| `bool` | `true` / `false` / `yes` / `no` / `1` / `0` | `"type":"bool"` |
| `int` | `-42` | `"type":"int"` |
| `float` | `1`, `0.25` (a whole number stays a float) | `"type":"float"` |
| `string` | anything, verbatim | `"type":"string"` |
| `date` | ISO 8601, `2026-01-02T03:04:05Z` | ISO 8601 |
| `data` | base64 | base64 |
| `plist` | an XML fragment: `<array>…</array>`, `<dict>…</dict>` | `"type":"array"` / `"dict"`, every element typed |

A value that isn't its type (`--type int --value 1.5`) is refused. It is never
stored as a string. Arrays and dictionaries go through `plist` because JSON
can't tell `1` from `1.0`.

## HTTP

```
GET    /simulators/<UDID>/defaults.json?bundleId=com.x[&suite=group.x][&key=k]
       → {"bundleId":"com.x","values":{"seen":{"type":"bool","value":false}}}
       → {"key":"k","present":false}                    (with &key=)
POST   /simulators/<UDID>/defaults
       {"bundleId":"com.x","suite":"group.x"?,"key":"seen","type":"bool","value":false,"relaunch":true?}
       → {"ok":true}
POST   /simulators/<UDID>/defaults
       {"bundleId":"com.x","values":{…an export's values…},"relaunch":true?}
       → {"ok":true,"written":3}
DELETE /simulators/<UDID>/defaults?bundleId=com.x[&suite=group.x]&key=seen[&relaunch=1]
       → {"ok":true,"removed":true}
```

The card also uses:

```
GET    /simulators/<UDID>/apps.json                         → {"apps":[{"bundleId","name","system"}]}
GET    /simulators/<UDID>/defaults-groups.json?bundleId=com.x → {"bundleId":"com.x","groups":["group.x"]}
POST   /simulators/<UDID>/relaunch?bundleId=com.x            → {"ok":true}
```

`defaults.json?…&plist=1` adds each array or dictionary's `"plist"` text, so
an editor can show it and post it back as `type: plist`.

`value` may be a JSON string, number or boolean; it is read as `type`. Errors
are `{"ok":false,"error":"…"}`: `400` bad identifier / type / value, `404`
unknown udid, app not installed or App Group not found, `409` simulator not
booted, `500` any other simctl failure. Browser-trusted only; no plugin
capability reaches these routes.

## Gotchas

- **A running app may not see a write.** It keeps its own in-memory copy of
  `UserDefaults`, and its next save can write the old value back. A read that
  shows your value proves it's on disk, not that the app saw it. Use
  `--relaunch` (quit → write → launch). Without it the app is left alone.
- **`--relaunch` launches the app even if it wasn't running.** If the write
  fails, the app stays quit, so a running app never hides the failure.
- **The simulator must be booted.** Reads and writes go through the guest's own
  `cfprefsd`. A shut-down device fails with "not booted".
- **`--suite group.…` is an App Group; any other suite is the app's own.**
  `UserDefaults(suiteName: "group.…")` lives in the group's shared container,
  and a group the app's entitlements don't grant is an error, never a silent
  fallback to standard defaults. `UserDefaults(suiteName: "com.x.debug")` lives
  in the app's data container as `com.x.debug.plist`.
- **Persisted values only.** `register(defaults:)` values live in the app's
  memory and never appear here, and neither do managed preferences, the
  Keychain or app databases.

## See also

- [design.md](design.md): the simctl path, measured exit codes, and why the
  group lookup lists every group
- [mockup.html](mockup.html): the card's design mockup, with its empty, suite, error and relaunch-off states
- [deep-links](../deep-links/README.md): drive the app to a screen after setup
