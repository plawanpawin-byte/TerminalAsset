import SwiftUI

/// Small rounded-square calendar icon whose number and month follow the date it is given.
/// The dark satin surface is drawn in code, so it needs no image and the number is always crisp.
struct CalendarTile: View {
    let date: Date
    var size: CGFloat = 76

    var body: some View {
        ZStack {
            silk
            VStack(spacing: -size * 0.02) {
                Text(date.formatted(.dateTime.day()))
                    .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(date.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(.system(size: size * 0.17, weight: .bold, design: .rounded))
                    .tracking(size * 0.02)
                    .opacity(0.9)
            }
            .foregroundStyle(
                LinearGradient(colors: [.white, Color(white: 0.82)], startPoint: .top, endPoint: .bottom)
            )
            .padding(.horizontal, size * 0.06)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .strokeBorder(.white.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendar")
        .accessibilityValue(date.formatted(date: .complete, time: .omitted))
        .accessibilityAddTraits(.isButton)
    }

    /// Near-black satin: a dark base with a few soft diagonal folds catching light.
    private var silk: some View {
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
                    .frame(width: size * 1.7, height: size * 0.26)
                    .rotationEffect(.degrees(-30))
                    .offset(x: CGFloat(index - 2) * size * 0.06, y: CGFloat(index - 2) * size * 0.30)
                    .blur(radius: size * 0.035)
            }
        }
    }
}

#Preview("Calendar tile") {
    HStack(spacing: 20) {
        CalendarTile(date: .now)
        CalendarTile(date: .now, size: 120)
    }
    .padding()
    .background(Color.blue.gradient)
}
