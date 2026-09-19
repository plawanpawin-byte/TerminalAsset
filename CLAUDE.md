# TerminalAsset (Temporal Workspace)

App name: **TerminalAsset**. "Temporal Workspace" is the product concept: a Calendar Event becomes an
Active Context Container, and the app surfaces the context you need (files, notes, links, tasks,
previous events) just in time. Not a chatbot, note app, calendar clone, or AI wrapper.

Role: act as Lead iOS & AI Architect + Senior Swift Engineer. Respond to the user in Thai unless asked otherwise.
Work in incremental vertical slices; do not build the whole architecture ahead of a working feature.

## Architectural principles (non-negotiable)
1. **Local first** — calendar, context, attachments metadata, checklist, local search never depend on cloud AI.
2. **AI is a service** — it sits behind the Context Engine and an `AIProvider` protocol; Domain never imports Gemini/Firebase.
3. **Deterministic before generative** — exact match / metadata / date filter / ranking before any LLM.
4. **Privacy by design** — process on device first; before any cloud call be able to say what is sent, why, and if it is necessary.
5. **Event is not the database** — EventKit is an external temporal reference. The app owns its Domain Model and maps to
   events through a stable key (see below). Never store app metadata inside EKEvent.

## EventKit identity rule
`eventIdentifier` is volatile (especially for recurring events). Identity is a composite key:
`calendarItemExternalIdentifier` + `occurrenceDate` (the occurrence's ORIGINAL start, which survives a moved occurrence).
If the external ID is nil, fall back to a fingerprint (calendar + title + start). Reconciliation must never delete
context: events that disappear become `.missing` (soft state), and only events inside the synced window can go missing.

## Stack
Swift 6 strict concurrency, SwiftUI + Observation, SwiftData, EventKit behind a repository protocol, actors for sync,
Share Extension + App Group (Phase 2), Firebase AI Logic for Gemini (Phase 3, never the legacy GoogleGenerativeAI SDK,
never an API key in the bundle; use App Check), StoreKit 2 behind an Entitlement service (Phase 4).
Verify current Apple/Firebase docs before using version-sensitive APIs; if a required tech is deprecated, tell the user first.

## Layout
`Package.swift` defines a local package:
- `TerminalAssetDomain` — Foundation-only, no UI/SwiftData/EventKit. Builds and tests on any platform (`swift test`).
- `TerminalAssetCore` — SwiftData models, EventKit repository, sync actor. Apple platforms only (guarded by `canImport`).
The iOS app target (Xcode) and the Share Extension import these libraries.

## Code rules
Swift 6 compatible, Sendable-correct, no placeholders/TODOs, no force unwraps, typed errors (never `catch { print(error) }`),
dependency injection, no needless singletons, no business logic in SwiftUI Views, no network or heavy IO on MainActor,
never assume BackgroundTasks run on time. Every feature states Online / Offline / Degraded behavior.
Test with Swift Testing; never assert AI output by exact string equality.

## Feature response format
Architectural Decisions → Data Flow → Implementation (file name before each block) → Project Placement →
Error/Offline behavior → Performance notes → Test strategy.

## Roadmap
- Phase 1 Temporal Core: SwiftData model, EventKit + permission, event mapping, Today timeline, current/upcoming event, context attachment.
- Phase 2 Ingestion: Share Extension, App Group inbox, file/URL/image ingestion, local + temporal semantic search,
  App Intents / Spotlight indexing (small: event + context item entities, one "find context" intent).
- Phase 3 Intelligence: AIProvider, local AI, Gemini, ranking, summarization, action extraction, Prep Blocks.
- Phase 4 v1.0: Live Activities, widgets, App Intents, background prep, StoreKit 2, privacy hardening, telemetry.
- Context Decay (Phase 3/4): embeddings are regenerable so compact them after ~30 days (configurable, pinned/active-series exempt);
  original user attachments are never moved or deleted silently; iCloud cold storage is opt-in and shown as such;
  decay must also run opportunistically (app launch/idle), not only via BGProcessingTask.

## North star
Does this help the user get the right context at the right time with less effort? If not, it does not belong here.
