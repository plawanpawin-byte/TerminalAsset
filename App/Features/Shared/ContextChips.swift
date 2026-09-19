import SwiftUI
import TerminalAssetDomain

/// Compact "what's attached" badges. Renders nothing for an empty context.
struct ContextChips: View {
    let summary: ContextSummary

    var body: some View {
        if !summary.isEmpty {
            HStack(spacing: 6) {
                if summary.tasks > 0 { chip("checklist", "\(summary.openTasks)/\(summary.tasks)") }
                if summary.notes > 0 { chip("note.text", "\(summary.notes)") }
                if summary.links > 0 { chip("link", "\(summary.links)") }
                if summary.attachments > 0 { chip("paperclip", "\(summary.attachments)") }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(summary.accessibilityDescription)
        }
    }

    private func chip(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.quaternary.opacity(0.6), in: Capsule())
    }
}
