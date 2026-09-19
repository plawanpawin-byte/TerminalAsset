import Foundation

// MARK: - Search

enum SearchScope: String, CaseIterable, Identifiable {
    case all, files, notes, links, tasks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .files: "Files"
        case .notes: "Notes"
        case .links: "Links"
        case .tasks: "Tasks"
        }
    }
}

enum ResultKind {
    case file, image, note, voice, link, task

    var symbol: String {
        switch self {
        case .file: "doc.text"
        case .image: "photo"
        case .note: "note.text"
        case .voice: "waveform"
        case .link: "link"
        case .task: "checklist"
        }
    }

    var scope: SearchScope {
        switch self {
        case .file, .image: .files
        case .note, .voice: .notes
        case .link: .links
        case .task: .tasks
        }
    }
}

/// A "why this result" reason. Ranking mixes several signals, so the UI shows which ones applied.
struct RankingSignal: Hashable {
    enum Kind { case temporal, related, previousEvent, semantic, recent }
    let kind: Kind
    let text: String

    var symbol: String {
        switch kind {
        case .temporal: "clock"
        case .related: "paperclip"
        case .previousEvent: "arrow.triangle.branch"
        case .semantic: "sparkle.magnifyingglass"
        case .recent: "calendar.badge.clock"
        }
    }
}

struct SearchResult: Identifiable, Hashable {
    let id = UUID()
    let kind: ResultKind
    let title: String
    let snippet: String
    let eventTitle: String?
    let signals: [RankingSignal]
    let score: Double
}

// MARK: - Prep

enum PrepStatus: Hashable {
    case ready
    case generating
    case needsPro
    case offline
}

enum PrepProvider: Hashable {
    case onDevice, cloud

    var title: String {
        switch self {
        case .onDevice: "On-device"
        case .cloud: "Cloud"
        }
    }

    var symbol: String {
        switch self {
        case .onDevice: "iphone"
        case .cloud: "cloud"
        }
    }
}

struct PrepSource: Hashable, Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let sentToCloud: Bool
}

struct PrepBlock: Identifiable, Hashable {
    let id = UUID()
    let eventTitle: String
    let startsAt: Date
    let status: PrepStatus
    let provider: PrepProvider?
    let summary: String?
    let keyItems: [String]
    let questions: [String]
    let checklist: [String]
    let sources: [PrepSource]
}

// MARK: - Fixtures

/// Demo content for screens whose real data arrives in later phases. Dates are relative to `now`.
enum UIFixtures {
    static let recentSearches = ["risk register", "vendor questionnaire", "corrective actions"]

    static func searchResults() -> [SearchResult] {
        [
            SearchResult(
                kind: .file, title: "Audit Plan 2026.pdf",
                snippet: "Scope, schedule and responsibilities for the 2026 ISO 27001 audit.",
                eventTitle: "ISO Audit Preparation",
                signals: [
                    RankingSignal(kind: .temporal, text: "Event is happening now"),
                    RankingSignal(kind: .related, text: "Attached to event")
                ],
                score: 0.96
            ),
            SearchResult(
                kind: .file, title: "Risk Register 2026.xlsx",
                snippet: "Top 12 risks with owners and treatment status.",
                eventTitle: "ISO Audit Preparation",
                signals: [
                    RankingSignal(kind: .related, text: "Attached to event"),
                    RankingSignal(kind: .recent, text: "Edited 2 days ago")
                ],
                score: 0.91
            ),
            SearchResult(
                kind: .note, title: "Last time: evidence for corrective actions",
                snippet: "Auditor asked for evidence of corrective actions from Q2.",
                eventTitle: "ISO Audit Preparation",
                signals: [
                    RankingSignal(kind: .previousEvent, text: "From a previous event"),
                    RankingSignal(kind: .semantic, text: "Similar meaning")
                ],
                score: 0.84
            ),
            SearchResult(
                kind: .link, title: "Vendor security questionnaire",
                snippet: "example.com/vendors/questionnaire",
                eventTitle: "Vendor security review",
                signals: [RankingSignal(kind: .temporal, text: "Next event")],
                score: 0.78
            ),
            SearchResult(
                kind: .voice, title: "Voice memo · Supplier call",
                snippet: "They can share their SOC 2 report by Friday.",
                eventTitle: "Vendor security review",
                signals: [RankingSignal(kind: .semantic, text: "Similar meaning")],
                score: 0.66
            ),
            SearchResult(
                kind: .task, title: "Send corrective action log to QA",
                snippet: "Open task · due before the audit",
                eventTitle: "ISO Audit Preparation",
                signals: [RankingSignal(kind: .related, text: "Attached to event")],
                score: 0.6
            ),
            SearchResult(
                kind: .image, title: "Whiteboard photo · audit scope.jpg",
                snippet: "Photo added 3 weeks ago",
                eventTitle: nil,
                signals: [RankingSignal(kind: .semantic, text: "Similar meaning")],
                score: 0.55
            )
        ]
    }

    static func prepBlocks(now: Date) -> [PrepBlock] {
        [
            PrepBlock(
                eventTitle: "Vendor security review",
                startsAt: now + 90 * 60,
                status: .ready,
                provider: .onDevice,
                summary: "Review the vendor's questionnaire answers against your security baseline. Their SOC 2 report is due Friday, so confirm the date and ask what the report scope covers.",
                keyItems: ["Vendor security questionnaire", "Voice memo · Supplier call", "Q3 vendor list.xlsx"],
                questions: ["Does the SOC 2 scope include the hosting provider?", "Who owns incident notification on their side?"],
                checklist: ["Review questionnaire answers", "Confirm SOC 2 delivery date"],
                sources: [
                    PrepSource(symbol: "link", title: "Vendor security questionnaire", sentToCloud: false),
                    PrepSource(symbol: "waveform", title: "Voice memo · Supplier call", sentToCloud: false),
                    PrepSource(symbol: "checklist", title: "Review questionnaire answers", sentToCloud: false)
                ]
            ),
            PrepBlock(
                eventTitle: "Risk register walkthrough",
                startsAt: now + 240 * 60,
                status: .ready,
                provider: .cloud,
                summary: "Walk through the 12 highest risks. Three changed owner since last review and two have overdue treatment dates. Bring evidence for the corrective actions the auditor asked about.",
                keyItems: ["Risk Register 2026.xlsx", "Audit Plan 2026.pdf"],
                questions: ["Which overdue treatments need a new date?", "Who signs off the ownership changes?"],
                checklist: ["Print risk register summary", "Collect corrective action evidence"],
                sources: [
                    PrepSource(symbol: "doc.text", title: "Risk Register 2026.xlsx", sentToCloud: true),
                    PrepSource(symbol: "note.text", title: "Last time: evidence for corrective actions", sentToCloud: true),
                    PrepSource(symbol: "doc.text", title: "Audit Plan 2026.pdf", sentToCloud: false)
                ]
            ),
            PrepBlock(
                eventTitle: "Board prep",
                startsAt: now + 22 * 3600,
                status: .generating,
                provider: .cloud,
                summary: nil, keyItems: [], questions: [], checklist: [], sources: []
            ),
            PrepBlock(
                eventTitle: "Supplier onboarding call",
                startsAt: now + 26 * 3600,
                status: .needsPro,
                provider: nil,
                summary: nil,
                keyItems: ["Supplier onboarding checklist", "Contract draft v3.pdf"],
                questions: [], checklist: [], sources: []
            ),
            PrepBlock(
                eventTitle: "Quarterly compliance sync",
                startsAt: now + 50 * 3600,
                status: .offline,
                provider: .cloud,
                summary: nil,
                keyItems: ["Compliance calendar", "Open findings list"],
                questions: [], checklist: ["Review open findings"], sources: []
            )
        ]
    }
}
