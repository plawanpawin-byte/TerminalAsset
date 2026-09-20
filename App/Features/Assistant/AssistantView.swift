import SwiftUI
import TerminalAssetDomain

/// The Assistant tab: a local-first briefing of what needs attention (the next event to prepare for and
/// past events with loose ends), followed by your whole calendar as an Apple-News-style "Top Stories" wall.
struct AssistantView: View {
    let model: AssistantViewModel
    let today: TodayViewModel

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack {
                background
                feed
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: EventKey.self) { key in
                EventDetailView(key: key, today: today)
            }
            .task { await model.load() }
            // The first sync (or a share attached elsewhere) can finish after this screen loaded.
            .onChange(of: today.events) { Task { await model.load() } }
        }
        .preferredColorScheme(.dark)
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(hex: 0x0B0B12), Color(hex: 0x15151F)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("Assistant")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.white)

                if let problem = model.problem {
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if model.isLoading && model.days.isEmpty {
                    ProgressView().tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 80)
                } else if model.days.isEmpty {
                    emptyState
                } else {
                    briefing
                    timeline
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Briefing

    @ViewBuilder private var briefing: some View {
        if !model.briefing.isEmpty {
            // The clock drives the live countdown and "ended … ago" wording without a timer of our own.
            TimelineView(.everyMinute) { context in
                VStack(alignment: .leading, spacing: 18) {
                    if let event = model.briefing.upNext {
                        section("Up next") {
                            NavigationLink(value: event.key) {
                                UpNextCard(event: event, now: context.date)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if !model.briefing.looseEnds.isEmpty {
                        section("Loose ends") {
                            LooseEndsCard(events: model.briefing.looseEnds, now: context.date)
                        }
                    }
                }
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.45))
                .tracking(0.5)
            content()
        }
    }

    // MARK: - Timeline wall (Apple-News "Top Stories")

    private var timeline: some View {
        section("Timeline") {
            let split = balancedColumns(events)
            HStack(alignment: .top, spacing: 12) {
                column(split.left)
                column(split.right)
            }
        }
    }

    private func column(_ events: [TimelineEvent]) -> some View {
        LazyVStack(spacing: 12) {
            ForEach(events) { event in
                NavigationLink(value: event.key) {
                    StoryCard(event: event, label: dayLabel(event.startDate))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// Every active event, newest day first, ready to flow into columns.
    private var events: [TimelineEvent] { model.days.flatMap(\.events) }

    /// Greedily drops each card into whichever column is currently shorter, so the two sides stay even.
    private func balancedColumns(_ events: [TimelineEvent]) -> (left: [TimelineEvent], right: [TimelineEvent]) {
        var left: [TimelineEvent] = []
        var right: [TimelineEvent] = []
        var leftHeight: CGFloat = 0
        var rightHeight: CGFloat = 0
        for event in events {
            let height = estimatedHeight(event)
            if leftHeight <= rightHeight {
                left.append(event)
                leftHeight += height
            } else {
                right.append(event)
                rightHeight += height
            }
        }
        return (left, right)
    }

    /// Rough card height so the greedy split balances; exact layout is still done by SwiftUI.
    private func estimatedHeight(_ event: TimelineEvent) -> CGFloat {
        let style = StoryStyle(seed: event.key.rawValue)
        let titleLines = max(1, ceil(CGFloat(event.title.count) / 15))
        var height = style.heroHeight + 44 + titleLines * 24
        if let location = event.location, !location.isEmpty { height += 18 }
        if !event.summary.isEmpty { height += 26 }
        return height
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
            Text("No events yet")
                .font(.headline)
                .foregroundStyle(.white)
            Text("Once your calendar syncs, everything you need to prepare for shows up here.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    private func dayLabel(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(date: .numeric, time: .omitted)
    }
}

// MARK: - Up next card

private struct UpNextCard: View {
    let event: TimelineEvent
    let now: Date

    private var isOngoing: Bool { event.startDate <= now && now < event.endDate }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(event.startDate.formatted(date: .abbreviated, time: .omitted), systemImage: "calendar")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer()
                countdownPill
            }

            Text(event.title)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            Text(detailLine)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.7))

            if event.summary.isEmpty {
                Label("No context attached yet — tap to prepare", systemImage: "paperclip")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Color(hex: 0xFFD166))
            } else {
                ContextChips(summary: event.summary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: 0x2A2A57), Color(hex: 0x1B1B2E)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color(hex: 0x7A78F0).opacity(0.35), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var countdownPill: some View {
        let text = isOngoing
            ? "Now · \(TimeText.remaining(until: event.endDate, from: now))"
            : TimeText.countdown(to: event.startDate, from: now)
        let color = isOngoing ? Color(hex: 0x30D158) : Color(hex: 0x7A78F0)
        return Text(text)
            .font(.caption.weight(.bold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(color.opacity(0.9), in: Capsule())
    }

    private var detailLine: String {
        let time = TimeText.range(of: event)
        if let location = event.location, !location.isEmpty {
            return "\(time) · \(location)"
        }
        return time
    }
}

// MARK: - Loose ends card

private struct LooseEndsCard: View {
    let events: [TimelineEvent]
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                NavigationLink(value: event.key) {
                    row(event)
                }
                .buttonStyle(.plain)
                if index < events.count - 1 {
                    Divider().overlay(Color.white.opacity(0.08))
                        .padding(.leading, 44)
                }
            }
        }
        .background(Color(hex: 0x1C1C22), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func row(_ event: TimelineEvent) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checklist")
                .font(.body.weight(.semibold))
                .foregroundStyle(Color(hex: 0xFF9F0A))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(subtitle(event))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func subtitle(_ event: TimelineEvent) -> String {
        let open = event.summary.openTasks
        let tasks = "\(open) task\(open == 1 ? "" : "s") open"
        return "\(tasks) · \(TimeText.relative(event.endDate, to: now))"
    }
}

// MARK: - Story card

/// Deterministic look for a story card's hero: a gradient, an SF Symbol, and a height. Same event → same
/// look every launch (seeded from the event key), and different events vary so the wall reads like a
/// magazine rather than a uniform list.
private struct StoryStyle {
    let heroHeight: CGFloat
    let colors: [Color]
    let symbol: String

    init(seed: String) {
        let palettes: [[Color]] = [
            [Color(hex: 0x3A2E4D), Color(hex: 0x6C5B9E)],
            [Color(hex: 0x1F3A5F), Color(hex: 0x3E77A8)],
            [Color(hex: 0x24463A), Color(hex: 0x4E8C6A)],
            [Color(hex: 0x4A2E3A), Color(hex: 0x9E5B72)],
            [Color(hex: 0x3A3320), Color(hex: 0x8C7A3E)],
            [Color(hex: 0x2C2C46), Color(hex: 0x5B5B8C)]
        ]
        let symbols = [
            "calendar", "person.2.fill", "doc.text.fill", "checklist",
            "bubble.left.and.bubble.right.fill", "chart.bar.xaxis",
            "briefcase.fill", "mappin.and.ellipse"
        ]
        let heights: [CGFloat] = [96, 118, 140]

        var hash = 5381
        for scalar in seed.unicodeScalars {
            hash = (hash &* 33 &+ Int(scalar.value)) & 0x7fffffff
        }
        colors = palettes[hash % palettes.count]
        symbol = symbols[(hash / 7) % symbols.count]
        heroHeight = heights[(hash / 13) % heights.count]
    }
}

/// One event as an Apple-News-style story card: a gradient hero, then day label, bold headline and detail.
private struct StoryCard: View {
    let event: TimelineEvent
    let label: String

    private var style: StoryStyle { StoryStyle(seed: event.key.rawValue) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            VStack(alignment: .leading, spacing: 6) {
                Text(label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.45))

                Text(event.title)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(3)

                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)

                if !event.summary.isEmpty {
                    ContextChips(summary: event.summary)
                        .padding(.top, 2)
                }
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0x1C1C22))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: style.colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: style.symbol)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(14)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        }
        .frame(height: style.heroHeight)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    private var subtitle: String {
        let time = TimeText.range(of: event)
        if let location = event.location, !location.isEmpty {
            return "\(time) · \(location)"
        }
        return time
    }
}
