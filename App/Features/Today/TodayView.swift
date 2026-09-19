import SwiftUI
import TerminalAssetDomain

struct TodayView: View {
    let model: TodayViewModel
    let weather: WeatherViewModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [EventKey]
    @State private var showingCalendar: Bool
    private let calendarMode: CalendarViewModel.Mode

    init(
        model: TodayViewModel,
        weather: WeatherViewModel,
        initialPath: [EventKey] = [],
        initialCalendar: CalendarViewModel.Mode? = nil
    ) {
        self.model = model
        self.weather = weather
        _path = State(initialValue: initialPath)
        _showingCalendar = State(initialValue: initialCalendar != nil)
        calendarMode = initialCalendar ?? .month
    }

    /// The sky is only painted once the day itself has loaded, so the calendar-permission and error screens keep
    /// their normal light or dark appearance.
    private var sky: SkyStyle? {
        model.phase == .ready ? weather.sky : nil
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
                    TodayContent(model: model, weather: weather, sky: sky) {
                        showingCalendar = true
                    }
                }
            }
            .background { background.ignoresSafeArea() }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(sky == nil ? nil : .dark, for: .navigationBar)
            .navigationDestination(for: EventKey.self) { key in
                EventDetailView(key: key, today: model, initialAdding: launchAddSheet)
            }
            .navigationDestination(isPresented: $showingCalendar) {
                CalendarScreen(today: model, mode: calendarMode)
            }
        }
        .task { await model.start() }
        .task { await weather.reconcile() }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await model.didBecomeActive()
                await weather.reconcile()
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        if let sky {
            sky.gradient
        } else {
            Color(.systemGroupedBackground)
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
    let weather: WeatherViewModel
    let sky: SkyStyle?
    let openCalendar: () -> Void

    /// Text that sits directly on the background (not inside a card) turns white over the sky.
    private var outerText: Color { sky == nil ? .primary : .white }
    private var outerSecondary: Color { sky == nil ? .secondary : .white.opacity(0.8) }

    var body: some View {
        // Re-evaluated every minute so countdowns, progress and past/now/upcoming stay current.
        TimelineView(.everyMinute) { context in
            let snapshot = model.snapshot(at: context.date)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    TodayHeader(now: context.date, stats: snapshot.stats, weather: weather, onOpenCalendar: openCalendar)
                        .foregroundStyle(outerText)

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
                        .foregroundStyle(outerText)
                    }

                    if snapshot.stats.missing > 0 {
                        Label(
                            "\(snapshot.stats.missing) event\(snapshot.stats.missing == 1 ? "" : "s") no longer in Calendar. Their context is kept.",
                            systemImage: "tray.full"
                        )
                        .font(.footnote)
                        .foregroundStyle(outerSecondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .refreshable {
                await model.reload()
                await weather.refresh(force: true)
            }
        }
    }

    private func schedule(_ snapshot: TodaySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Schedule")
                .font(.title3.weight(.semibold))
                .foregroundStyle(outerText)
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
        TodayView(model: app.today, weather: app.weather)
    }
}

#Preview("Today · dark") {
    if let app = try? AppBootstrap.makeSampleModel() {
        TodayView(model: app.today, weather: app.weather)
            .preferredColorScheme(.dark)
    }
}
#endif
