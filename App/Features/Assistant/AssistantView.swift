import SwiftUI
import TerminalAssetDomain

/// The Assistant tab: your whole calendar as an Apple-News-style "Top Stories" wall of cards, with a
/// Siri-style liquid-glass voice orb pinned near the top. Pull the orb down to start speaking; drag it
/// back up to dismiss. The history stays visible behind the glass while listening.
struct AssistantView: View {
    let model: AssistantViewModel
    let today: TodayViewModel

    /// 0 = orb resting at the top, 1 = full listening state.
    @State private var progress: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0

    private let calendar = Calendar.current

    /// Live value while a drag is in flight.
    private var effective: CGFloat { min(max(progress + dragOffset / 240, 0), 1) }
    private var listening: Bool { effective > 0.5 }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                background
                feed
                voiceLayer
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: EventKey.self) { key in
                EventDetailView(key: key, today: today)
            }
            .task {
                #if DEBUG
                if LaunchOptions.assistantListening { progress = 1 }
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
            VStack(alignment: .leading, spacing: 20) {
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
            .padding(.top, 118)
            .padding(.bottom, 40)
        }
        .scrollDisabled(effective > 0.05)
    }

    /// Two balanced columns of story cards, newest first.
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
        let titleLines = max(1, ceil(CGFloat(event.title.count) / 15))
        var height: CGFloat = 58 + titleLines * 24
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

    // MARK: - Voice orb

    private var voiceLayer: some View {
        ZStack(alignment: .top) {
            // Only a soft top vignette while listening — the history behind stays readable, never blurred out.
            LinearGradient(
                colors: [Color.black.opacity(0.55 * effective), .clear],
                startPoint: .top, endPoint: .center
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            // A transparent catcher so a tap anywhere cancels once we're actually listening.
            if listening {
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture { collapse() }
            }

            VStack(spacing: 14) {
                AssistantOrb(active: listening)
                    .frame(width: orbSize, height: orbSize)

                ZStack {
                    collapsedHint.opacity(hintOpacity)
                    listeningCaption.opacity(captionOpacity)
                }
                .frame(height: 44)
            }
            .padding(.top, 6 + 30 * effective)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(drag)
        }
    }

    private var orbSize: CGFloat { 56 + 96 * effective }
    private var hintOpacity: Double { Double(max(0, 1 - effective * 4)) }
    private var captionOpacity: Double { Double(max(0, (effective - 0.5) * 2)) }

    private var collapsedHint: some View {
        VStack(spacing: 2) {
            Image(systemName: "line.3.horizontal")
                .font(.subheadline.weight(.semibold))
            Text("Drag down to speak")
                .font(.caption)
        }
        .foregroundStyle(.white.opacity(0.5))
    }

    private var listeningCaption: some View {
        VStack(spacing: 4) {
            Text("Listening…")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
            Text("Drag up to cancel")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var drag: some Gesture {
        DragGesture()
            .updating($dragOffset) { value, state, _ in state = value.translation.height }
            .onEnded { value in
                let projected = progress + value.translation.height / 240
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                    progress = projected > 0.4 ? 1 : 0
                }
            }
    }

    private func collapse() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { progress = 0 }
    }
}

/// One event as an Apple-News-style story card on the dark Assistant wall.
private struct StoryCard: View {
    let event: TimelineEvent
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.45))

            Text(event.title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)

            Text(subtitle)
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)

            if !event.summary.isEmpty {
                ContextChips(summary: event.summary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(hex: 0x1C1C22), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var subtitle: String {
        let time = TimeText.range(of: event)
        if let location = event.location, !location.isEmpty {
            return "\(time) · \(location)"
        }
        return time
    }
}
