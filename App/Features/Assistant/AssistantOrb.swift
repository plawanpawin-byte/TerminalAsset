import SwiftUI

/// A Siri-like glass orb: a dark sphere with a rainbow light that sweeps inside it. When `active` it also
/// breathes, so it clearly reads as "listening". Purely decorative — no audio is wired to it yet.
struct AssistantOrb: View {
    var active: Bool = false

    @State private var spin = false
    @State private var breathe = false

    private let rainbow: [Color] = [
        Color(hex: 0xFF3B7B), Color(hex: 0xFF9F0A), Color(hex: 0xFFD60A),
        Color(hex: 0x30D158), Color(hex: 0x40C8E0), Color(hex: 0x5E5CE6),
        Color(hex: 0xBF5AF2), Color(hex: 0xFF3B7B)
    ]

    var body: some View {
        ZStack {
            // Dark glass base.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.20), Color(white: 0.04)],
                        center: .center, startRadius: 0, endRadius: 90
                    )
                )

            // Rainbow light swept round the inside and softened to a glow.
            Circle()
                .fill(AngularGradient(colors: rainbow, center: .center))
                .blur(radius: 26)
                .opacity(active ? 0.95 : 0.7)
                .rotationEffect(.degrees(spin ? 360 : 0))

            // A bright horizontal light bar, like the reference sphere.
            Capsule()
                .fill(.white)
                .frame(height: 10)
                .blur(radius: 10)
                .opacity(active ? 0.9 : 0.55)
                .rotationEffect(.degrees(spin ? 360 : 0))

            // Glass rim and a top-left highlight.
            Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [.white.opacity(0.45), .clear],
                        center: UnitPoint(x: 0.32, y: 0.28), startRadius: 0, endRadius: 60
                    )
                )
                .blendMode(.screen)
        }
        .clipShape(Circle())
        .scaleEffect(breathe ? 1.05 : 0.97)
        .shadow(color: Color(hex: 0x5E5CE6).opacity(active ? 0.6 : 0.3), radius: active ? 28 : 14)
        .onAppear {
            withAnimation(.linear(duration: 7).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    ZStack {
        Color.black
        AssistantOrb(active: true).frame(width: 150, height: 150)
    }
    .ignoresSafeArea()
}
