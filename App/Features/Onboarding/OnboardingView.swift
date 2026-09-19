import SwiftUI

/// Three short pages explaining the idea before any permission is requested.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var page = 0

    private struct Page: Identifiable {
        let id: Int
        let symbol: String
        let title: String
        let detail: String
    }

    private let pages = [
        Page(id: 0, symbol: "calendar.badge.clock",
             title: "Your calendar, with context",
             detail: "Every event becomes a place for the notes, links, files and tasks that belong to it."),
        Page(id: 1, symbol: "square.and.arrow.up",
             title: "Share it. Don't file it.",
             detail: "Send something from Safari, Photos or Files. TerminalAsset suggests which event it belongs to."),
        Page(id: 2, symbol: "sparkles",
             title: "The right thing, right on time",
             detail: "When an event is close, what you need is already at the top, with no searching and no prompts to write.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Skip", action: onFinish)
                    .font(.body)
                    .opacity(page == pages.count - 1 ? 0 : 1)
                    .disabled(page == pages.count - 1)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)

            TabView(selection: $page) {
                ForEach(pages) { item in
                    pageView(item).tag(item.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            VStack(spacing: 12) {
                Button {
                    if page < pages.count - 1 {
                        withAnimation { page += 1 }
                    } else {
                        onFinish()
                    }
                } label: {
                    Text(page == pages.count - 1 ? "Get Started" : "Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Label("Your data stays on this device unless you choose otherwise.", systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func pageView(_ item: Page) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: item.symbol)
                .font(.system(size: 72))
                .foregroundStyle(Color.accentColor)
                .frame(width: 140, height: 140)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
                .accessibilityHidden(true)
            VStack(spacing: 10) {
                Text(item.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(item.detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
    }
}

#Preview("Onboarding") {
    OnboardingView {}
}
