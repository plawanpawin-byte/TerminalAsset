import SwiftUI

/// Settings > Language: pick the language TerminalAsset uses, or follow the iPhone.
struct LanguageView: View {
    let model: SettingsViewModel

    @State private var showingRestartNotice = false

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases) { language in
                    Button {
                        showingRestartNotice = model.chooseLanguage(language)
                    } label: {
                        HStack {
                            Text(language.title)
                                .foregroundStyle(.primary)
                            Spacer()
                            if model.language == language {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(model.language == language ? .isSelected : [])
                }
            } footer: {
                Text("Choose the language TerminalAsset uses. Only this app changes; the widget and the share sheet follow the language of your iPhone.")
            }
        }
        .navigationTitle("Language")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Language", isPresented: $showingRestartNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The language changes the next time TerminalAsset opens. Close it from the app switcher and open it again.")
        }
    }
}

#if DEBUG
#Preview("Language") {
    if let app = try? AppBootstrap.makeSampleModel() {
        NavigationStack { LanguageView(model: app.settings) }
    }
}
#endif
