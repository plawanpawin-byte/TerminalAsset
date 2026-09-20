import SwiftUI
import TerminalAssetDomain

private let widgetHeight: CGFloat = 144

/// Two home-screen-style widgets under the weather: what is on now or next, and how the day is going.
struct TodayWidgets: View {
    let snapshot: TodaySnapshot
    let now: Date
    let onOpenCalendar: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            UpNextWidget(hero: snapshot.hero, now: now)
            DayProgressWidget(stats: snapshot.stats, openTasks: snapshot.openTasks, onOpenCalendar: onOpenCalendar)
                .frame(width: 132)
        }
    }
}

private struct UpNextWidget: View {
    let hero: HeroEvent?
    let now: Date

    var body: some View {
        if let hero {
            NavigationLink(value: hero.entry.event.key) {
                WidgetSurface(height: widgetHeight) { content(for: hero) }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the event")
        } else {
            WidgetSurface(height: widgetHeight) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Up next", systemImage: "checkmark.circle")
                        .font(.caption.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color(hex: 0x64D2FF))
                    Spacer(minLength: 0)
                    Text("Nothing else today")
                        .font(.title3.weight(.semibold))
                    Text("Enjoy the free time.")
                        .font(.caption)
                        .opacity(0.7)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func content(for hero: HeroEvent) -> some View {
        let event = hero.entry.event
        return VStack(alignment: .leading, spacing: 4) {
            Label(eyebrow(for: hero.kind).text, systemImage: eyebrow(for: hero.kind).symbol)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(hero.kind == .now ? Color(hex: 0xFF9F0A) : Color(hex: 0x64D2FF))

            Text(event.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)

            Text(headline(for: hero))
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            if let progress = hero.progress {
                ProgressView(value: progress)
                    .tint(.white)
            } else {
                Text(TimeText.range(of: event))
                    .font(.caption)
                    .opacity(0.7)
            }
        }
    }

    private func eyebrow(for kind: HeroKind) -> (text: String, symbol: String) {
        switch kind {
        case .now: ("Happening now", "dot.radiowaves.left.and.right")
        case .upNext: ("Up next", "clock")
        case .tomorrow: ("Tomorrow", "sunrise")
        }
    }

    private func headline(for hero: HeroEvent) -> String {
        let event = hero.entry.event
        switch hero.kind {
        case .now: return TimeText.remaining(until: event.endDate, from: now)
        case .upNext: return TimeText.countdown(to: event.startDate, from: now)
        case .tomorrow: return event.startDate.formatted(.dateTime.hour().minute())
        }
    }
}

private struct DayProgressWidget: View {
    let stats: DayStats
    let openTasks: Int
    let onOpenCalendar: () -> Void

    private var fraction: Double {
        stats.total == 0 ? 0 : Double(stats.completed) / Double(stats.total)
    }

    var body: some View {
        Button(action: onOpenCalendar) {
            WidgetSurface(height: widgetHeight) {
                VStack(spacing: 6) {
                    if stats.total == 0 {
                        Image(systemName: "sun.max")
                            .font(.system(size: 30))
                            .frame(width: 64, height: 64)
                        Text("No events today")
                            .font(.caption)
                            .multilineTextAlignment(.center)
                            .opacity(0.8)
                    } else {
                        ring
                        VStack(spacing: 1) {
                            Text("events done")
                                .font(.caption)
                                .opacity(0.8)
                            if openTasks > 0 {
                                Text("\(openTasks) \(openTasks == 1 ? "task" : "tasks") open")
                                    .font(.caption2)
                                    .opacity(0.6)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Today's progress")
        .accessibilityValue(accessibilityValue)
        .accessibilityHint("Opens the calendar")
    }

    private var ring: some View {
        ZStack {
            Circle().stroke(.white.opacity(0.18), lineWidth: 7)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    stats.remaining == 0 ? Color(hex: 0x5BE08A) : Color.white,
                    style: StrokeStyle(lineWidth: 7, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            Text("\(stats.completed)/\(stats.total)")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 64, height: 64)
    }

    private var accessibilityValue: String {
        if stats.total == 0 { return "No events today" }
        let tasks = openTasks > 0 ? ", \(openTasks) open \(openTasks == 1 ? "task" : "tasks")" : ""
        return "\(stats.completed) of \(stats.total) events done\(tasks)"
    }
}
