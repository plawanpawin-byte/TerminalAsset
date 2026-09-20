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

## Principles

See `CLAUDE.md`: local first, AI only behind a protocol, deterministic before generative, privacy by design, and the
event calendar is a reference, not the database.
