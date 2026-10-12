---
description: How baguette defaults finds an app's preferences plist through simctl and edits it through the guest's cfprefsd, with the measured exit codes and the group-lookup dead end. Read before changing the defaults adapter.
---

# Defaults: design

## Path

- CLI `baguette defaults read|write|delete`, `GET /simulators/<UDID>/defaults.json`,
  `POST|DELETE /simulators/<UDID>/defaults`
- → `PreferenceDomain` (which container, which plist) + `PreferenceValue` (typed value)
  → `PreferenceEdit` (the optional quit / relaunch around a change)
- → `Defaults` (`Simulator.defaults()` vends a fresh handle) → `SimctlDefaults`, two
  `Subprocess` children per operation:
  1. `xcrun simctl get_app_container <udid> <bundle> data | groups`
  2. `xcrun simctl spawn <udid> defaults export <plist> - | write <plist> <key> <fragment> | delete <plist> <key>`
- Relaunch: `Apps.terminate` / `Apps.launch` → `simctl terminate | launch`.

## Why `spawn defaults`, not a host-side plist edit

The plist is reachable from the Mac, but the guest's `cfprefsd` caches it. A
host-side write can be overwritten by the daemon's next flush, and a host-side
read can miss a change the daemon hasn't flushed yet. Running the guest's own
`defaults` tool goes through `cfprefsd`, so it agrees with what the daemon
holds. `defaults` accepts an absolute plist path as its domain. That is how
both a sandboxed app's container and a group container are addressed without
running inside the app.

## Typed writes

`defaults write <domain> <key> <value>` parses `<value>` as a property list
when it is one. Writing the XML element (`<false/>`, `<integer>3</integer>`,
`<real>1.0</real>`, `<date>…Z</date>`, `<data>base64</data>`, `<array>`,
`<dict>`) stores that exact type. All eight were checked with `defaults
read-type` against an iOS 27.0 simulator (Xcode 27). Strings are always written
as an escaped `<string>` element, so a string that looks like markup stays a
string. `defaults export <plist> -` returns the whole domain as an XML plist,
which keeps the types on the way back. `CFBoolean` tells a stored bool from an
integer, and `CFNumberIsFloatType` tells a real from an integer.

## Measured exit codes (Xcode 27)

| command | exit | meaning | maps to |
|---|---|---|---|
| `get_app_container … data / groups` | `2` | no such app installed | `appNotInstalled` (404) |
| any `simctl` on a shut-down device | `149` | SimError 405, not booted | `deviceNotBooted` (409) |
| `defaults delete` of an absent key | `1` | "Could not find key" | avoided: `PreferenceEdit` reads first |
| `simctl terminate` of an app not running | `3` | "found nothing to terminate" | treated as done |

## Dead end: `get_app_container <bundle> <group id>`

simctl's help offers a named-group form. On Xcode 27 it exits `117` and prints
usage even for a group the app *does* have (Safari and
`group.com.apple.BrowserKit`, which `… groups` lists). The adapter therefore
asks for `groups`, which prints `<group id>\t<path>` lines, and picks the
suite out of them (`PreferenceDomain.plistPath(inContainerOutput:)`). A suite
missing from that listing is `groupNotFound`. That keeps a misspelt or
unentitled group from silently landing in standard defaults.

## Identifiers

The bundle id and suite become a path component and a simctl argument, so
`PreferenceDomain` refuses empty values, `/`, `..` and a leading `-` before
either sees them. That matters on the HTTP route, where they come from a query
string.

## Known limits

- A running app's in-memory `UserDefaults` is out of reach. `--relaunch` is the
  supported way to make it observe a change.
- Only persisted values. Registered defaults, managed preferences, the Keychain
  and app databases are out of scope.
- A suite name that differs from its group identifier (rare) isn't addressable.
