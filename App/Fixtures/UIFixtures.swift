import Foundation

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
