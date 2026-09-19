import SwiftUI
import TerminalAssetDomain

/// One row of the day: start time, a rail showing past / now / upcoming, and the event with its context badges.
struct TimelineRow: View {
    let entry: TimelineEntry

    private var event: TimelineEvent { entry.event }

    var body: some View {
        NavigationLink(value: event.key) {
            HStack(alignment: .top, spacing: 12) {
                Text(event.startDate, format: .dateTime.hour().minute())
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(entry.phase == .past ? .secondary : .primary)
                    .frame(minWidth: 56, alignment: .trailing)
                    .padding(.vertical, 12)

                rail

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(event.title)
                            .font(.body.weight(.medium))
                            .foregroundStyle(entry.phase == .past ? .secondary : .primary)
                            .multilineTextAlignment(.leading)
                        if entry.phase == .current {
                            Text("Now")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor, in: Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ContextChips(summary: event.summary)
                        .padding(.top, 2)
                }
                .padding(.vertical, 12)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 16)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the event's context")
    }

    private var subtitle: String {
        let range = TimeText.range(of: event)
        guard let location = event.location, !location.isEmpty else { return range }
        return "\(range) · \(location)"
    }

    private var rail: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color(.separator))
                .frame(width: 2)
            dot
                .padding(.top, 17)
        }
        .frame(width: 14)
    }

    @ViewBuilder
    private var dot: some View {
        switch entry.phase {
        case .past:
            Circle().fill(Color.secondary.opacity(0.5)).frame(width: 10, height: 10)
        case .current:
            Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.accentColor.opacity(0.3), lineWidth: 4))
        case .upcoming:
            Circle().fill(Color(.systemBackground)).frame(width: 10, height: 10)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: 2))
        }
    }
}
