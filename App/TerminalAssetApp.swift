import SwiftUI

@main
struct TerminalAssetApp: App {
    private let bootstrap: Result<AppModel, BootstrapFailure>

    init() {
        bootstrap = AppBootstrap.make()
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .success(let model):
                RootView(app: model)
            case .failure(let failure):
                ContentUnavailableView {
                    Label("TerminalAsset can't start", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure.message)
                }
            }
        }
    }
}
