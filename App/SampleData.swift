#if DEBUG
import Foundation
import TerminalAssetCore
import TerminalAssetDomain

/// Demo content for previews and CI screenshots. Compiled out of release builds.
enum SampleData {
    private static let minute: TimeInterval = 60

    /// One clock reading for the whole launch. Event keys embed the occurrence time, so seeding and any later
    /// lookup must use the same reference time or they would address different events.
    static let launchTime = Date()

    static func snapshots(now: Date, calendar: Calendar = .current) -> [CalendarEventSnapshot] {
        let startOfToday = calendar.startOfDay(for: now)
        let tomorrowMorning = (calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday)
            .addingTimeInterval(9 * 60 * minute)
        return [
            make("standup", "Team standup", start: now - 150 * minute, minutes: 30, location: "Room 2"),
            make("audit", "ISO Audit Preparation", start: now - 25 * minute, minutes: 60, location: "Conference Room A"),
            make("vendor", "Vendor security review", start: now + 90 * minute, minutes: 60, location: "Zoom"),
            make("risk", "Risk register walkthrough", start: now + 240 * minute, minutes: 45, location: nil),
            make("allday", "Audit week", start: startOfToday, minutes: 24 * 60, location: nil, allDay: true),
            make("board", "Board prep", start: tomorrowMorning, minutes: 60, location: "HQ")
        ]
    }

    /// Key of the sample event that is "happening now"; used to open its detail screen from a launch argument.
    static func auditKey(now: Date = launchTime) -> EventKey {
        key("audit", now: now)
    }

    static func seed(sync: CalendarSyncService, store: ContextStore, shared: SharedInbox, now: Date) async {
        do {
            try await sync.syncNow(around: now)
            try enqueueSharedItems(into: shared, now: now)
            let audit = key("audit", now: now)
            try await add(store, audit, .task, "Confirm scope with QA lead", now: now)
            try await add(store, audit, .task, "Print risk register summary", now: now)
            let sent = try await add(store, audit, .task, "Send agenda to attendees", now: now)
            try await store.setTaskDone(id: sent.id, isDone: true)
            try await add(
                store, audit, .note, "Last time",
                detail: "Auditor asked for evidence of corrective actions from Q2.", now: now
            )
            try await add(store, audit, .link, "Audit Plan 2026", url: "example.com/audit-plan", now: now)

            let vendor = key("vendor", now: now)
            try await add(store, vendor, .task, "Review questionnaire answers", now: now)
            try await add(store, vendor, .link, "Vendor portal", url: "example.com/vendors", now: now)

            try await add(store, key("standup", now: now), .note, "Blocked on access request", now: now)
        } catch {
            // Demo data is best-effort; the app still runs with whatever was seeded.
            return
        }
    }

    // MARK: - Weather

    /// A fixed forecast for previews and screenshots. `-weather rain`, `-night` and `-weatherPermission` choose the scene.
    @MainActor
    static func weatherModel(now: Date) -> WeatherViewModel {
        let condition = LaunchOptions.weatherCondition.flatMap(WeatherCondition.init(rawValue:)) ?? .partlyCloudy
        let isDaytime = !LaunchOptions.night
        let hourly = sampleHours(now: now, condition: condition)
        let daily = sampleDays(now: now, condition: condition, hourly: hourly)
        let snapshot = WeatherSnapshot(
            temperatureC: condition == .snow ? -2 : 31,
            condition: condition,
            isDaytime: isDaytime,
            highC: daily.first?.highC ?? 33,
            lowC: daily.first?.lowC ?? 26,
            precipitationChance: hourly.prefix(12).map(\.precipitationChance).max() ?? 0,
            cityName: "Bangkok",
            fetchedAt: now,
            hourly: hourly,
            daily: daily,
            details: sampleDetails(now: now)
        )
        let place = WeatherPlace(coordinate: WeatherCoordinate(latitude: 13.7563, longitude: 100.5018), cityName: "Bangkok")
        let location = StubLocationService(
            permission: LaunchOptions.weatherPermission ? .notDetermined : .authorized,
            place: place
        )
        return WeatherViewModel(
            location: location,
            service: WeatherService(provider: StubWeatherProvider(snapshot: snapshot), cacheURL: nil)
        )
    }

    /// 24 hours starting at the current hour. Rain-type scenes are wet now and ease; partly cloudy turns wet later.
    private static func sampleHours(now: Date, condition: WeatherCondition, calendar: Calendar = .current) -> [HourlyForecast] {
        let firstHour = Date(timeIntervalSince1970: (now.timeIntervalSince1970 / 3_600).rounded(.down) * 3_600)
        let wetNow: Set<WeatherCondition> = [.rain, .drizzle, .thunderstorm, .snow]
        let peak: Double = wetNow.contains(condition) ? 0 : 5
        let base: Double = switch condition {
        case .thunderstorm: 90
        case .rain, .snow: 80
        case .drizzle: 65
        case .partlyCloudy: 75
        case .cloudy: 25
        case .fog, .clear: 0
        }
        return (0..<24).map { index in
            let date = firstHour.addingTimeInterval(TimeInterval(index) * 3_600)
            let hourOfDay = calendar.component(.hour, from: date)
            let chance = Int(max(0, base - abs(Double(index) - peak) * 15))
            let wet = chance >= 50
            let hourCondition: WeatherCondition = wet ? (wetNow.contains(condition) ? condition : .rain)
                : (wetNow.contains(condition) ? .cloudy : condition)
            let temperature = 29 + 4 * sin(Double(hourOfDay - 9) * .pi / 12)
            return HourlyForecast(
                date: date,
                temperatureC: condition == .snow ? -2 : temperature,
                condition: hourCondition,
                isDaytime: (6..<18).contains(hourOfDay),
                precipitationChance: chance
            )
        }
    }

    private static func sampleDays(
        now: Date,
        condition: WeatherCondition,
        hourly: [HourlyForecast],
        calendar: Calendar = .current
    ) -> [DailyForecast] {
        let today = calendar.startOfDay(for: now)
        let conditions: [WeatherCondition] = [condition, .partlyCloudy, .rain, .thunderstorm, .cloudy, .partlyCloudy, .clear]
        let highs: [Double] = [33, 32, 30, 29, 31, 33, 34]
        let lows: [Double] = [26, 26, 25, 25, 26, 26, 27]
        let chances: [Int] = [hourly.map(\.precipitationChance).max() ?? 0, 30, 80, 90, 40, 20, 0]
        return (0..<7).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: today).map { date in
                DailyForecast(
                    date: date, highC: highs[offset], lowC: lows[offset],
                    condition: conditions[offset], precipitationChance: chances[offset]
                )
            }
        }
    }

    private static func sampleDetails(now: Date, calendar: Calendar = .current) -> WeatherDetails {
        let today = calendar.startOfDay(for: now)
        return WeatherDetails(
            feelsLikeC: 36,
            humidity: 74,
            windKph: 14,
            uvIndex: 9,
            sunrise: today.addingTimeInterval(6 * 3_600 + 5 * 60),
            sunset: today.addingTimeInterval(18 * 3_600 + 20 * 60)
        )
    }

    // MARK: - Shared items

    /// Queues items exactly as the Share Extension would, so demo mode exercises the real ingestion path.
    private static func enqueueSharedItems(into shared: SharedInbox, now: Date) throws {
        try shared.enqueue(InboxDraft(
            kind: .url, title: "How to prepare for an ISO 27001 surveillance audit",
            urlString: "https://iso.org/audit-preparation", receivedAt: now - 12 * minute
        ))
        try shared.enqueue(InboxDraft(
            kind: .text, title: "Ask Priya about the vendor questionnaire",
            text: "Ask Priya about the vendor questionnaire", receivedAt: now - 8 * minute
        ))
        try shared.enqueue(
            InboxDraft(kind: .image, title: "IMG_4821.jpg", receivedAt: now - 65 * minute),
            payload: try payloadFile(named: "IMG_4821.jpg")
        )
        try shared.enqueue(
            InboxDraft(kind: .file, title: "Q3 vendor list.xlsx", receivedAt: now - 180 * minute),
            payload: try payloadFile(named: "Q3 vendor list.xlsx")
        )
        // Shared with an explicit "next event" choice, so it is attached during ingestion.
        try shared.enqueue(InboxDraft(
            kind: .text, title: "Bring printed copies", text: "Bring printed copies",
            intent: .upcomingEvent, receivedAt: now - minute
        ))
    }

    private static func payloadFile(named name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("sample-payload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try Data("sample".utf8).write(to: url)
        return url
    }

    // MARK: - Helpers

    private static func key(_ id: String, now: Date) -> EventKey {
        let match = snapshots(now: now).first { $0.eventIdentifier == id }
        return match.map { EventIdentity.key(for: $0) } ?? EventKey(rawValue: id)
    }

    @discardableResult
    private static func add(
        _ store: ContextStore,
        _ key: EventKey,
        _ kind: ContextItemKind,
        _ title: String,
        detail: String = "",
        url: String = "",
        now: Date
    ) async throws -> ContextItemValue {
        try await store.addItem(
            to: key,
            draft: ContextItemDraft(kind: kind, title: title, detail: detail, urlString: url),
            now: now
        )
    }

    private static func make(
        _ id: String,
        _ title: String,
        start: Date,
        minutes: Int,
        location: String?,
        allDay: Bool = false
    ) -> CalendarEventSnapshot {
        CalendarEventSnapshot(
            eventIdentifier: id,
            externalIdentifier: "sample-\(id)",
            calendarID: "sample",
            title: title,
            startDate: start,
            endDate: start.addingTimeInterval(TimeInterval(minutes) * 60),
            occurrenceDate: start,
            isAllDay: allDay,
            location: location,
            isRecurring: false
        )
    }
}
#endif
