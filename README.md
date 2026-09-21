# TerminalAsset

A calendar event becomes a container for the context you need for it: files, notes, links, tasks and the
previous events in the series, surfaced just in time. Local first: the calendar, context, search and reminders
never depend on a cloud service.

## Layout

| Path | What it is |
| --- | --- |
| `Sources/TerminalAssetDomain` | Foundation-only rules: event identity, reconciliation, text parsing, search, reminders planning, weather models. Builds and tests on any platform. |
| `Sources/TerminalAssetCore` | SwiftData store, EventKit repository, sync actor, notification scheduler. Apple platforms only. |
| `App`, `ShareExtension`, `WidgetExtension` | The iOS app, the Share Extension and the Up Next widget (SwiftUI). They share the App Group `group.com.terminalasset.app`. |
| `project.yml` | XcodeGen project definition. `xcodegen generate` produces the Xcode project. |
| `scripts/capture-screenshots.sh` | Runs the app in the simulator and captures the main screens (used by CI). |
| `docs/PUBLIC_RELEASE.md` | What is done for a public release, known caveats, and the steps only the owner can take. |

## Build and test

- Domain rules, on any OS with Swift 6: `swift test`
- Everything else needs macOS with Xcode: `xcodegen generate`, then build the `TerminalAsset` scheme.
  CI (`.github/workflows`) runs the Core tests and builds the app on every push.

## Running it on a Mac after `git pull`

1. `bash scripts/open-in-xcode.sh` regenerates `TerminalAsset.xcodeproj` from `project.yml` and opens it. The project
   file is not committed, so do this after every pull; edits made inside Xcode (signing team, bundle ID) are lost
   each time.
2. To sign for a real iPhone, copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and put your Team ID
   in it. That file is ignored by git, so the team survives regeneration.
3. Do not change the bundle identifiers (`com.terminalasset.app`, `.share`, `.widget`). A different identifier is a
   different app to iOS: you get a second icon and the first one's data stays behind. If a duplicate already exists,
   delete the older icon from the device or simulator.

## Principles

See `CLAUDE.md`: local first, AI only behind a protocol, deterministic before generative, privacy by design, and the
event calendar is a reference, not the database.
