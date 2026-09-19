import SwiftUI
import TerminalAssetDomain

/// The one thing to look at first: the event happening now (or next) and what to prepare for it.
struct HeroCard: View {
    let hero: HeroEvent
    let now: Date
    let onToggleTask: (UUID, Bool) -> Void

    private var event: TimelineEvent { hero.entry.event }
    private var openTasks: [ContextItemValue] { event.items.filter { $0.kind == .task && !$0.isDone } }
    private let visibleTaskLimit = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NavigationLink(value: event.key) {
                header
            }
            .buttonStyle(.plain)

            if let progress = hero.progress {
                ProgressView(value: progress)
                    .tint(.accentColor)
                    .accessibilityLabel("Event progress")
                    .accessibilityValue("\(Int(progress * 100)) percent")
            }

            Divider()
            prepare
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            if hero.kind == .now {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.4), lineWidth: 1.5)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(eyebrow.text, systemImage: eyebrow.symbol)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(hero.kind == .now ? Color.accentColor : .secondary)

            Text(event.title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.leading)

            Text(TimeText.range(of: event))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if let location = event.location, !location.isEmpty {
                Label(location, systemImage: "mappin.and.ellipse")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(countdown)
                .font(.headline)
                .foregroundStyle(hero.kind == .now ? Color.accentColor : .primary)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var eyebrow: (text: String, symbol: String) {
        switch hero.kind {
        case .now: ("Happening now", "dot.radiowaves.left.and.right")
        case .upNext: ("Up next", "clock")
        case .tomorrow: ("Tomorrow", "sunrise")
        }
    }

    private var countdown: String {
        switch hero.kind {
        case .now: TimeText.remaining(until: event.endDate, from: now)
        case .upNext, .tomorrow: "Starts \(TimeText.relative(event.startDate, to: now))"
        }
    }

    // MARK: - Preparation

    @ViewBuilder
    private var prepare: some View {
        let summary = event.summary
        VStack(alignment: .leading, spacing: 10) {
            Text("To prepare")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if !openTasks.isEmpty {
                ForEach(openTasks.prefix(visibleTaskLimit)) { task in
                    taskRow(task)
                }
                if openTasks.count > visibleTaskLimit {
                    Text("+\(openTasks.count - visibleTaskLimit) more")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if summary.isEmpty {
                Text("Nothing attached yet. Add a note, link or task and it will be here when it matters.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Label("You're all set", systemImage: "checkmark.seal")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack {
                ContextChips(summary: summary)
                Spacer()
                NavigationLink(value: event.key) {
                    Text(summary.isEmpty ? "Add context" : "Open")
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func taskRow(_ task: ContextItemValue) -> some View {
        Button {
            onToggleTask(task.id, true)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "circle")
                    .foregroundStyle(Color.accentColor)
                Text(task.title)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(task.title)
        .accessibilityValue("Not done")
        .accessibilityHint("Marks the task as done")
    }
}
