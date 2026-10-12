---
description: Read, write and delete an installed app's persisted UserDefaults on a booted simulator, with every value typed, including App Group suites. Use to set up onboarding, feature-flag or preference scenarios before driving the UI.
---

# Defaults

Prepare an app's persisted preferences (its standard `UserDefaults`, or an App
Group suite), then drive the UI with baguette. Values keep their type, a key
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

## Workflows

**Set up a scenario, then verify the UI.** Write each key with `--relaunch` on
the last one (or all of them). The app quits before the write and launches
after, so it starts from what you stored. Then `describe-ui` / `screenshot` as
usual.

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
DELETE /simulators/<UDID>/defaults?bundleId=com.x[&suite=group.x]&key=seen[&relaunch=1]
       → {"ok":true,"removed":true}
```

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
- **The suite name is the App Group identifier**, as in
  `UserDefaults(suiteName: "group.…")`. A group the app's entitlements don't
  grant is an error, never a silent fallback to standard defaults.
- **Persisted values only.** `register(defaults:)` values live in the app's
  memory and never appear here, and neither do managed preferences, the
  Keychain or app databases.

## See also

- [design.md](design.md): the simctl path, measured exit codes, and why the
  group lookup lists every group
- [deep-links](../deep-links/README.md): drive the app to a screen after setup
