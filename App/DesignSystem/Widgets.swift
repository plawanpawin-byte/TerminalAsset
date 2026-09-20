import SwiftUI

/// Near-black satin: a dark base with a few soft diagonal folds catching light. Drawn in code so it fills any
/// shape (the calendar tile and the Today widgets share it) and needs no image.
struct SatinBackground: View {
    var body: some View {
        GeometryReader { proxy in
            let unit = max(proxy.size.width, proxy.size.height)
            ZStack {
                LinearGradient(
                    colors: [Color(white: 0.16), Color(white: 0.04), Color(white: 0.11)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white.opacity(0.11), .white.opacity(0.0)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: unit * 1.7, height: unit * 0.26)
                        .rotationEffect(.degrees(-30))
                        .offset(x: CGFloat(index - 2) * unit * 0.06, y: CGFloat(index - 2) * unit * 0.30)
                        .blur(radius: unit * 0.035)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// A rounded-square, home-screen-style widget on the satin surface. White content, fixed height so a row of
/// widgets lines up.
struct WidgetSurface<Content: View>: View {
    var height: CGFloat = 132
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: height)
            .background(SatinBackground())
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
    }
}

/// A translucent panel for weather content that sits over the sky. Always dark-scheme so white text reads on
/// every sky colour.
struct GlassCard<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 1)
            )
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
    }
}

/// Small uppercase heading with an icon, used at the top of glass cards and detail tiles.
struct GlassHeading: View {
    let text: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.white.opacity(0.7))
            .accessibilityAddTraits(.isHeader)
    }
}
