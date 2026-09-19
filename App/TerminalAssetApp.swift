import SwiftUI

@main
struct TerminalAssetApp: App {
    private let bootstrap: Result<TodayViewModel, BootstrapFailure>

    init() {
        bootstrap = AppBootstrap.make()
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .success(let model):
                TodayView(model: model)
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
