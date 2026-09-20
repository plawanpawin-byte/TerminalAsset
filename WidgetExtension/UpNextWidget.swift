import AppIntents
import SwiftUI
import TerminalAssetDomain
import WidgetKit

/// The widget has nothing to configure, but the async timeline API needs an intent to hang off.
struct UpNextIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Up Next"
    static let description = IntentDescription("Shows the event in progress or coming next, and what to prepare.")
}

/// Qualified: TerminalAssetDomain also has a `TimelineEntry` (for the Today screen).
struct UpNextEntry: WidgetKit.TimelineEntry {
    let date: Date
    /// Nil when the app has not written a snapshot yet (before first launch, or after deleting all data).
    let snapshot: WidgetSnapshot?
}

struct UpNextProvider: AppIntentTimelineProvider {
    typealias Intent = UpNextIntent
    typealias Entry = UpNextEntry

    func placeholder(in context: Context) -> UpNextEntry {
        UpNextEntry(date: .now, snapshot: Self.sample(now: .now))
    }

    func snapshot(for configuration: UpNextIntent, in context: Context) async -> UpNextEntry {
        let now = Date()
        return UpNextEntry(date: now, snapshot: context.isPreview ? Self.sample(now: now) : Self.load())
    }

    /// One entry per moment the display changes (each start and end), so "Next" becomes "Now" on time even though
    /// the app is not running. The app also asks for a reload whenever the calendar changes.
    func timeline(for configuration: UpNextIntent, in context: Context) async -> Timeline<UpNextEntry> {
        let now = Date()
        let snapshot = Self.load()
        let changes = snapshot?.changeDates(after: now).prefix(24) ?? []
        let entries = ([now] + changes).map { UpNextEntry(date: $0, snapshot: snapshot) }
        let policy: TimelineReloadPolicy = changes.isEmpty ? .after(now.addingTimeInterval(3600)) : .atEnd
        return Timeline(entries: entries, policy: policy)
    }

    private static func load() -> WidgetSnapshot? {
        guard let inbox = try? SharedInbox.appGroup() else { return nil }
        return WidgetSnapshot.read(from: inbox.rootURL)
    }

    /// What the widget gallery shows before the user has any events.
    private static func sample(now: Date) -> WidgetSnapshot {
        let start = now.addingTimeInterval(25 * 60)
        return WidgetSnapshot(generatedAt: now, entries: [
            .init(id: "sample-1", title: "Team standup", start: start, end: start.addingTimeInterval(30 * 60),
                  location: "Room 2", openTasks: 2, hasContext: true),
            .init(id: "sample-2", title: "Vendor review", start: start.addingTimeInterval(2 * 3600),
                  end: start.addingTimeInterval(3 * 3600), location: nil, openTasks: 0, hasContext: false)
        ])
    }
}

struct UpNextWidget: Widget {
    let kind = "UpNextWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: UpNextIntent.self, provider: UpNextProvider()) { entry in
            UpNextWidgetView(entry: entry)
        }
        .configurationDisplayName("Up Next")
        .description("The event in progress or coming next, and what to prepare for it.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

// MARK: - Views

struct UpNextWidgetView: View {
    let entry: UpNextEntry
    @Environment(\.widgetFamily) private var family

    private var current: WidgetSnapshot.Entry? { entry.snapshot?.current(at: entry.date) }
    private var upcoming: [WidgetSnapshot.Entry] { entry.snapshot?.upcoming(at: entry.date) ?? [] }
    /// The one event the widget is about: what is happening, else what is next.
    private var focus: WidgetSnapshot.Entry? { current ?? upcoming.first }
    private var following: [WidgetSnapshot.Entry] {
        let rest = current == nil ? Array(upcoming.dropFirst()) : upcoming
        return Array(rest.prefix(3))
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: lockScreen
            case .systemMedium: medium
            default: small
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: Small

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let focus {
                status(for: focus)
                Text(focus.title)
                    .font(.headline)
                    .lineLimit(3)
                Spacer(minLength: 0)
                Text(timeRange(focus))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                prepLine(focus)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Medium

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            small
            if !following.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(following) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.start, format: .dateTime.hour().minute())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(item.title)
                                .font(.footnote.weight(.medium))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    // MARK: Lock screen

    private var lockScreen: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let focus {
                Text(focus.start <= entry.date ? "Now" : "Next")
                    .font(.caption2.weight(.semibold))
                    .widgetAccentable()
                Text(focus.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(timeRange(focus))
                    .font(.caption)
                    .lineLimit(1)
            } else {
                Text("Nothing coming up")
                    .font(.headline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pieces

    private func status(for item: WidgetSnapshot.Entry) -> some View {
        HStack(spacing: 4) {
            if item.start <= entry.date {
                Text("NOW")
                    .foregroundStyle(.green)
            } else {
                Text("NEXT")
                Text("·")
                Text(item.start, style: .relative)
                    .monospacedDigit()
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    @ViewBuilder
    private func prepLine(_ item: WidgetSnapshot.Entry) -> some View {
        if item.openTasks > 0 {
            Label("\(item.openTasks) to do", systemImage: "checklist")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.orange)
        } else if !item.hasContext {
            Label("Nothing attached", systemImage: "paperclip")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else {
            Label("Ready", systemImage: "checkmark.circle")
                .font(.caption2)
                .foregroundStyle(.green)
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "checkmark.circle")
                .font(.title2)
                .foregroundStyle(.green)
            Text("Nothing coming up")
                .font(.headline)
            Text("Open TerminalAsset to see your day.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func timeRange(_ item: WidgetSnapshot.Entry) -> String {
        (item.start..<item.end).formatted(Date.IntervalFormatStyle(date: .omitted, time: .shortened))
    }
}
