# Changelog

All notable changes to baguette will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

For releases prior to this changelog, see the
[GitHub Releases](https://github.com/tddworks/baguette/releases) page.

## [Unreleased]

### Fixed
- `baguette stream` no longer crashes on startup and now releases capture resources when stopped by Ctrl-C or SIGTERM.
- `baguette stream --help` no longer offers an `h264` format it rejects, and `baguette logs --help` lists the levels (`default`, `info`, `debug`) and styles (including `ndjson`) it actually accepts.

### Changed
- `CHANGELOG.md` now holds only the current minor; the 0.1.x history moved unchanged to `docs/changelog/0.1.md`.
- Docs reorganised: a short README, one guide per feature under `docs/features/<name>/`, a generated command reference in `docs/commands.md`, and `docs/wire.md` for the gesture JSON. Several examples that never ran are fixed.

### Added
- `baguette screenshot --metadata-output` writes a JSON sidecar with the captured frame's actual pixel sizes and crop or letterbox placement. → [docs](docs/features/screenshot/geometry.md)

---

## [0.2.0] - 2026-09-22

### Changed
* ci: drop the Xcode 27 job's weekly schedule by @crockalet in https://github.com/tddworks/baguette/pull/83
* fix(pasteboard): write through devicectl before simctl pbcopy by @EYHN in https://github.com/tddworks/baguette/pull/84

## New Contributors
* @EYHN made their first contribution in https://github.com/tddworks/baguette/pull/84

## Older releases

[0.1](docs/changelog/0.1.md)

[Unreleased]: https://github.com/tddworks/baguette/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/tddworks/baguette/compare/v0.1.99...v0.2.0
