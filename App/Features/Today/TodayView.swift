import SwiftUI
import TerminalAssetDomain

struct TodayView: View {
    let model: TodayViewModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [EventKey]

    init(model: TodayViewModel, initialPath: [EventKey] = []) {
        self.model = model
        _path = State(initialValue: initialPath)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                switch model.phase {
                case .loading:
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .needsPermission(let status):
                    PermissionView(status: status) { await model.requestAccess() }
                case .failed(let message):
                    ContentUnavailableView {
                        Label("Can't load your day", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(message)
                    } actions: {
                        Button("Try Again") { Task { await model.reload() } }
                    }
                case .ready:
                    TodayContent(model: model)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: EventKey.self) { key in
                EventDetailView(key: key, today: model, initialAdding: launchAddSheet)
            }
        }
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.didBecomeActive() } }
        }
    }

    /// Debug launch argument so CI can screenshot the add sheet; always nil in release builds.
    private var launchAddSheet: AddKind? {
        #if DEBUG
        return LaunchOptions.addSheet.flatMap(AddKind.init(rawValue:))
        #else
        return nil
        #endif
    }
}

private struct TodayContent: View {
    let model: TodayViewModel

    var body: some View {
        // Re-evaluated every minute so countdowns, progress and past/now/upcoming stay current.
        TimelineView(.everyMinute) { context in
            let snapshot = model.snapshot(at: context.date)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    DayHeader(now: context.date, stats: snapshot.stats)

                    if let problem = model.problem {
                        Label(problem, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }

                    if let hero = snapshot.hero {
                        HeroCard(hero: hero, now: context.date) { id, done in
                            Task { await model.setTask(id, done: done) }
                        }
                    }

                    if !snapshot.allDay.isEmpty {
                        AllDayStrip(entries: snapshot.allDay)
                    }

                    if !snapshot.timeline.isEmpty {
                        schedule(snapshot)
                    } else if snapshot.isEmpty {
                        ContentUnavailableView(
                            "A clear day",
                            systemImage: "sun.max",
                            description: Text("Nothing is scheduled. Context you add to events shows up here when it matters.")
                        )
                    }

                    if snapshot.stats.missing > 0 {
                        Label(
                            "\(snapshot.stats.missing) event\(snapshot.stats.missing == 1 ? "" : "s") no longer in Calendar. Their context is kept.",
                            systemImage: "tray.full"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable { await model.reload() }
        }
    }

    private func schedule(_ snapshot: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(snapshot.timeline) { entry in
                    TimelineRow(entry: entry)
                }
            }
            .padding(.horizontal, 12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct DayHeader: View {
    let now: Date
    let stats: DayStats

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.title3.weight(.semibold))
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        guard stats.total > 0 else { return "No events scheduled" }
        if stats.remaining == 0 { return "All \(stats.total) done for today" }
        return "\(stats.remaining) left today · \(stats.completed) done"
    }
}

private struct AllDayStrip: View {
    let entries: [TimelineEntry]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(entries) { entry in
                    NavigationLink(value: entry.event.key) {
                        Label(entry.event.title, systemImage: "sun.max")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Today · sample") {
    if let app = try? AppBootstrap.makeSampleModel() {
        TodayView(model: app.today)
    }
}

#Preview("Today · dark") {
    if let app = try? AppBootstrap.makeSampleModel() {
        TodayView(model: app.today)
            .preferredColorScheme(.dark)
    }
}
#endif
