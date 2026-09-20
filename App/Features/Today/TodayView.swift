import SwiftUI
import TerminalAssetDomain

struct TodayView: View {
    let model: TodayViewModel
    let looseEnds: LooseEndsViewModel
    let router: AppRouter
    let weather: WeatherViewModel

    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [EventKey]
    @State private var showingCalendar: Bool
    private let calendarMode: CalendarViewModel.Mode

    init(
        model: TodayViewModel,
        looseEnds: LooseEndsViewModel,
        router: AppRouter,
        weather: WeatherViewModel,
        initialPath: [EventKey] = [],
        initialCalendar: CalendarViewModel.Mode? = nil
    ) {
        self.model = model
        self.looseEnds = looseEnds
        self.router = router
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
                    TodayContent(model: model, looseEnds: looseEnds, weather: weather, sky: sky) {
                        showingCalendar = true
                    }
                }
            }
            .background { background.ignoresSafeArea() }
            .navigationTitle(sky == nil ? String(localized: "Today") : "")
            .navigationBarTitleDisplayMode(sky == nil ? .large : .inline)
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
        .task { await looseEnds.load(readCalendar: true) }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await model.didBecomeActive()
                await weather.reconcile()
                await looseEnds.load(readCalendar: true)
            }
        }
        .onChange(of: model.events) { Task { await looseEnds.load() } }
        .onChange(of: router.pendingEvent, initial: true) { _, pending in
            guard let pending else { return }
            path = [pending]
            router.clearEvent()
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

/// Scroll targets on Today.
enum TodaySection: String, Hashable {
    case widgets, hourly, looseEnds, daily, details
}

private struct TodayContent: View {
    let model: TodayViewModel
    let looseEnds: LooseEndsViewModel
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
            let forecast = weather.forecast
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        TodayHeader(now: context.date, stats: snapshot.stats, weather: weather, onOpenCalendar: openCalendar)
                            .foregroundStyle(outerText)

                        TodayWidgets(snapshot: snapshot, now: context.date, onOpenCalendar: openCalendar)
                            .id(TodaySection.widgets)

                        if let forecast, !forecast.upcomingHours(from: context.date).isEmpty {
                            HourlyForecastCard(snapshot: forecast, now: context.date)
                                .id(TodaySection.hourly)
                        }

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

                        if !looseEnds.events.isEmpty {
                            looseEndsSection(events: looseEnds.events, now: context.date)
                                .id(TodaySection.looseEnds)
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
                                "\(snapshot.stats.missing) events no longer in Calendar. Their context is kept.",
                                systemImage: "tray.full"
                            )
                            .font(.footnote)
                            .foregroundStyle(outerSecondary)
                        }

                        if let forecast {
                            if !forecast.daily.isEmpty {
                                DailyForecastCard(snapshot: forecast, now: context.date)
                                    .id(TodaySection.daily)
                            }
                            WeatherDetailsGrid(snapshot: forecast, now: context.date)
                                .id(TodaySection.details)
                            WeatherAttribution()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await model.reload()
                    await weather.refresh(force: true)
                }
                #if DEBUG
                .task {
                    // Lets CI screenshot the lower half of Today without scripting a swipe.
                    guard let section = LaunchOptions.todaySection.flatMap(TodaySection.init(rawValue:)) else { return }
                    try? await Task.sleep(for: .milliseconds(1500))
                    proxy.scrollTo(section, anchor: .top)
                }
                #endif
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

    /// Past events that still have open tasks: a friendly "you left this behind" nudge. Grouped section
    /// so it reads as its own thing, above the day's schedule.
    private func looseEndsSection(events: [TimelineEvent], now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Loose ends")
                .font(.title3.weight(.semibold))
                .foregroundStyle(outerText)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    NavigationLink(value: event.key) {
                        LooseEndRow(event: event, now: now)
                    }
                    .buttonStyle(.plain)
                    if index < events.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }
}

private struct LooseEndRow: View {
    let event: TimelineEvent
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.body.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        let open = event.summary.openTasks
        return String(localized: "\(open) tasks open") + " · " + TimeText.relative(event.endDate, to: now)
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
        TodayView(model: app.today, looseEnds: app.looseEnds, router: app.router, weather: app.weather)
    }
}

#Preview("Today · dark") {
    if let app = try? AppBootstrap.makeSampleModel() {
        TodayView(model: app.today, looseEnds: app.looseEnds, router: app.router, weather: app.weather)
            .preferredColorScheme(.dark)
    }
}
#endif
