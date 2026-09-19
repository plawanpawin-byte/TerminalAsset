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

/// Small rounded label for statuses, sources and ranking signals.
struct Pill: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol {
                Image(systemName: symbol).imageScale(.small)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.14), in: Capsule())
    }
}

/// Footer shown on screens whose content is still demo data, so nobody mistakes it for real user data.
struct SampleDataNote: View {
    var body: some View {
        Label("Sample data · UI preview", systemImage: "hammer")
            .font(.footnote)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .accessibilityLabel("This screen shows sample data")
    }
}

struct SectionTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title3.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }
}
