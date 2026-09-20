import SwiftUI

/// A Siri-style *liquid glass* orb: clear, wet glass that refracts what's behind it with only a faint
/// iridescent sheen — never a solid rainbow disc. When `active` it breathes so it reads as "listening".
/// Purely decorative — no audio is wired to it yet.
struct AssistantOrb: View {
    var active: Bool = false

    @State private var spin = false
    @State private var breathe = false

    /// Soft spectrum used only as a thin sheen inside the glass, not as a fill.
    private let iris: [Color] = [
        Color(hex: 0xFF5E9C), Color(hex: 0xFFB340), Color(hex: 0xFFE45E),
        Color(hex: 0x4CD98A), Color(hex: 0x53C9E8), Color(hex: 0x7A78F0),
        Color(hex: 0xC77CF5), Color(hex: 0xFF5E9C)
    ]

    var body: some View {
        GeometryReader { geo in
            let d = min(geo.size.width, geo.size.height)

            ZStack {
                // Real glass — blurs and refracts the history sitting behind the orb.
                Circle().fill(.ultraThinMaterial)

                // A gentle darkening toward the lower edge so the glass reads as a rounded sphere.
                Circle().fill(
                    RadialGradient(
                        colors: [.clear, Color.black.opacity(0.40)],
                        center: UnitPoint(x: 0.5, y: 0.40),
                        startRadius: d * 0.05, endRadius: d * 0.62
                    )
                )

                // Iridescent sheen: kept faint and softened, so it stays "clear glass with a hint of colour".
                Circle()
                    .fill(AngularGradient(colors: iris, center: .center))
                    .blur(radius: d * 0.22)
                    .opacity(active ? 0.42 : 0.26)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .blendMode(.plusLighter)

                // Bright top-left specular highlight — the wet shine of glass.
                Circle().fill(
                    RadialGradient(
                        colors: [.white.opacity(0.85), .clear],
                        center: UnitPoint(x: 0.34, y: 0.24),
                        startRadius: 0, endRadius: d * 0.5
                    )
                )
                .blendMode(.screen)

                // A slim curved light streak across the upper third.
                Capsule()
                    .fill(.white)
                    .frame(width: d * 0.62, height: d * 0.045)
                    .blur(radius: d * 0.05)
                    .opacity(active ? 0.55 : 0.4)
                    .offset(y: -d * 0.2)
                    .rotationEffect(.degrees(-12))

                // Glass rim: brighter at the top, fading round.
                Circle().strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.55), .white.opacity(0.08)],
                        startPoint: .top, endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
            .frame(width: d, height: d)
            .clipShape(Circle())
            .scaleEffect(active && breathe ? 1.04 : 1.0)
            .shadow(color: .black.opacity(0.45), radius: d * 0.14, y: d * 0.05)
            .shadow(color: Color(hex: 0x7A78F0).opacity(active ? 0.35 : 0), radius: d * 0.18)
        }
        .onAppear {
            withAnimation(.linear(duration: 9).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        LinearGradient(colors: [Color(hex: 0x0B0B12), Color(hex: 0x1A1A24)],
                       startPoint: .top, endPoint: .bottom)
        AssistantOrb(active: true).frame(width: 150, height: 150)
    }
    .ignoresSafeArea()
}
