import SwiftUI
import TerminalAssetDomain

/// The Assistant tab: your whole calendar as a reverse-chronological feed, with a Siri-style voice orb pinned
/// near the top. Pull the orb down to start speaking; drag it back up to dismiss.
struct AssistantView: View {
    let model: AssistantViewModel
    let today: TodayViewModel

    /// 0 = orb resting at the top, 1 = full listening panel.
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

    // MARK: - History feed

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
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
                    ForEach(model.days) { section in
                        daySection(section)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 116)
            .padding(.bottom, 32)
        }
        .scrollDisabled(effective > 0.05)
    }

    private func daySection(_ section: HistoryDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dayLabel(section.day))
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            ForEach(section.events) { event in
                NavigationLink(value: event.key) {
                    EventFeedCard(event: event)
                }
                .buttonStyle(.plain)
            }
        }
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
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    // MARK: - Voice orb

    private var voiceLayer: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.55 * effective)
                .ignoresSafeArea()
                .allowsHitTesting(effective > 0.05)
                .onTapGesture { collapse() }

            VStack(spacing: 14) {
                AssistantOrb(active: listening)
                    .frame(width: orbSize, height: orbSize)

                ZStack {
                    collapsedHint.opacity(max(0, 1 - effective * 4))
                    listeningCaption.opacity(max(0, (effective - 0.5) * 2))
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

/// One event in the history feed, styled for the dark Assistant surface.
private struct EventFeedCard: View {
    let event: TimelineEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                if event.isAllDay {
                    Image(systemName: "sun.max")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    Text(event.startDate.formatted(.dateTime.hour().minute()))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                Text(TimeText.range(of: event))
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                if let location = event.location, !location.isEmpty {
                    Label(location, systemImage: "mappin.and.ellipse")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
                ContextChips(summary: event.summary)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(14)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
