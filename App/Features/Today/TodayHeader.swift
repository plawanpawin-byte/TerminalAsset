import SwiftUI
import TerminalAssetDomain

/// Top of Today: the weather (or just the date when there is none) on the left and the calendar tile on the right.
struct TodayHeader: View {
    let now: Date
    let stats: DayStats
    let weather: WeatherViewModel
    let onOpenCalendar: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var temperatureSize: CGFloat = 68
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                info
                Spacer(minLength: 8)
                Button(action: onOpenCalendar) {
                    CalendarTile(date: now)
                }
                .buttonStyle(.plain)
            }
            prompt
        }
    }

    // MARK: - Left side

    @ViewBuilder
    private var info: some View {
        if case .ready(let snapshot, let isStale) = weather.state {
            forecast(snapshot, isStale: isStale)
        } else {
            dateOnly
        }
    }

    private func forecast(_ snapshot: WeatherSnapshot, isStale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let city = snapshot.cityName {
                Label(city, systemImage: "location.fill")
                    .font(.headline)
                    .labelStyle(.titleAndIcon)
            }

            Text(TemperatureText.format(celsius: snapshot.temperatureC))
                .font(.system(size: temperatureSize, weight: .thin, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .accessibilityLabel("Temperature \(TemperatureText.format(celsius: snapshot.temperatureC))")

            HStack(spacing: 6) {
                Image(systemName: snapshot.condition.symbol(isDaytime: snapshot.isDaytime))
                    .symbolRenderingMode(.multicolor)
                Text(snapshot.condition.title)
                    .font(.headline)
            }
            Text("H:\(TemperatureText.format(celsius: snapshot.highC))  L:\(TemperatureText.format(celsius: snapshot.lowC))")
                .font(.subheadline)
                .opacity(0.85)

            if snapshot.precipitationChance >= 10 {
                Label("\(snapshot.precipitationChance)% chance of rain", systemImage: "umbrella.fill")
                    .font(.subheadline)
                    .opacity(0.9)
                    .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(now, format: .dateTime.hour().minute())
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                Text(summary)
            }
            .font(.footnote)
            .opacity(0.85)
            .padding(.top, 6)

            if isStale {
                Label("Updated \(snapshot.fetchedAt.formatted(.relative(presentation: .named)))", systemImage: "wifi.slash")
                    .font(.caption)
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
        .accessibilityElement(children: .combine)
    }

    private var dateOnly: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(now, format: .dateTime.hour().minute())
                .font(.system(size: 44, weight: .thin, design: .rounded))
                .monospacedDigit()
            Text(now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.title3.weight(.semibold))
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var summary: String {
        guard stats.total > 0 else { return String(localized: "No events scheduled") }
        if stats.remaining == 0 { return String(localized: "All \(stats.total) done for today") }
        return String(localized: "\(stats.remaining) left today · \(stats.completed) done")
    }

    // MARK: - Permission and problems

    @ViewBuilder
    private var prompt: some View {
        switch weather.state {
        case .needsPermission(.notDetermined):
            promptCard(
                title: "Show the weather here?",
                message: "TerminalAsset can show today's forecast for where you are. It uses your approximate location and sends only a rounded coordinate (about 1 km) to the free Open-Meteo weather service. No name, account or calendar data is sent.",
                primary: ("Allow Location", { Task { await weather.allow() } }),
                secondary: ("Not Now", { weather.dismissPrompt() })
            )
        case .needsPermission:
            promptCard(
                title: "Location is off",
                message: "Turn on location for TerminalAsset in Settings to see the weather. Everything else works without it.",
                primary: ("Open Settings", {
                    if let url = URL(string: "app-settings:") { openURL(url) }
                }),
                secondary: ("Hide", { weather.dismissPrompt() })
            )
        case .unavailable(let message):
            HStack {
                Label(message, systemImage: "cloud.slash")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Retry") { Task { await weather.refresh(force: true) } }
                    .font(.footnote.weight(.semibold))
            }
        case .hidden, .loading, .ready:
            EmptyView()
        }
    }

    private func promptCard(
        title: LocalizedStringKey,
        message: LocalizedStringKey,
        primary: (LocalizedStringKey, () -> Void),
        secondary: (LocalizedStringKey, () -> Void)
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: "location.circle.fill")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Button(primary.0, action: primary.1)
                    .buttonStyle(.borderedProminent)
                Button(secondary.0, action: secondary.1)
                    .buttonStyle(.bordered)
            }
            .controlSize(.small)
        }
        .card()
    }
}
