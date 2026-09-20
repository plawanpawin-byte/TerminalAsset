import SwiftUI

/// A label and its value on one line, like `LabeledContent`, but stacked when text is at an accessibility size so
/// neither side is squeezed into a few letters per line.
struct AdaptiveRow<Value: View>: View {
    let title: LocalizedStringKey
    let value: Value

    init(_ title: LocalizedStringKey, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                value.foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            LabeledContent(title) { value }
        }
    }
}
