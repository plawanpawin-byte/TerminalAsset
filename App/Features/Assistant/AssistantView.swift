import SwiftUI
import TerminalAssetDomain

/// The Assistant tab: your whole calendar as an Apple-News-style "Top Stories" wall of story cards,
/// with a liquid-glass "Ask" bar pinned at the bottom. Tap it (or the mic) to talk; the history stays
/// visible behind the glass while listening.
struct AssistantView: View {
    let model: AssistantViewModel
    let today: TodayViewModel

    @State private var listening = false

    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                background
                feed
                if listening { listeningOverlay }
                askBar
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: EventKey.self) { key in
                EventDetailView(key: key, today: today)
            }
            .task {
                #if DEBUG
                if LaunchOptions.assistantListening { listening = true }
                #endif
                await model.load()
            }
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

    // MARK: - History feed (Apple-News "Top Stories" wall)

    private var feed: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

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
                    masonry
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 96) // room for the floating Ask bar
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Timeline")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(.white)
            Spacer()
            Text(headerSubtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    private var headerSubtitle: String {
        let count = model.days.reduce(0) { $0 + $1.events.count }
        guard count > 0 else { return "" }
        return "\(count) events"
    }

    /// Two balanced columns of story cards, newest day first.
    private var masonry: some View {
        let split = balancedColumns(events)
        return HStack(alignment: .top, spacing: 12) {
            column(split.left)
            column(split.right)
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
            Text("Once your calendar syncs, every event shows up here as a history you can scroll through.")
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

    // MARK: - Ask bar

    private var askBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.title3)
                .foregroundStyle(Color(hex: 0x7A78F0))
            Text("Ask Assistant…")
                .font(.body)
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
            Image(systemName: "mic.fill")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 15)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 16, y: 6)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
        .contentShape(Capsule())
        .onTapGesture { startListening() }
        .opacity(listening ? 0 : 1)
    }

    // MARK: - Listening overlay

    private var listeningOverlay: some View {
        ZStack(alignment: .top) {
            // Soft top vignette only — the history behind stays readable, never blurred out.
            LinearGradient(
                colors: [.black.opacity(0.5), .black.opacity(0.1)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
            .contentShape(Rectangle())
            .onTapGesture { stopListening() }

            VStack(spacing: 16) {
                AssistantOrb(active: true)
                    .frame(width: 156, height: 156)
                Text("Listening…")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Tap anywhere to cancel")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
            }
            .padding(.top, 150)
        }
        .transition(.opacity)
    }

    private func startListening() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { listening = true }
    }

    private func stopListening() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { listening = false }
    }
}

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
