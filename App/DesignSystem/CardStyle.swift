import SwiftUI

/// Grouped-background card used across the app so every surface has the same shape, padding and contrast
/// in Light and Dark mode.
struct CardStyle: ViewModifier {
    var radius: CGFloat = 18
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color(.secondarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
    }
}

extension View {
    func card(radius: CGFloat = 18, padding: CGFloat = 16) -> some View {
        modifier(CardStyle(radius: radius, padding: padding))
    }
}
