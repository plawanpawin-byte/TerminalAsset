import SwiftUI
import TerminalAssetDomain

struct SettingsView: View {
    let model: SettingsViewModel

    @AppStorage(WeatherViewModel.enabledKey) private var showWeather = true
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var confirmingDelete = false
    @State private var exportDocument = ExportDocument()
    @State private var exporting = false
    @State private var path: [SettingsRoute] = []

    enum SettingsRoute: Hashable {
        case privacy
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                calendarSection
                weatherSection
                storageSection
                privacySection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { _ in PrivacyView() }
            .fileExporter(
                isPresented: $exporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: exportDocument.fileName
            ) { model.exportFinished($0) }
            .confirmationDialog(
                "Delete all TerminalAsset data?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {
                    Task { await model.eraseEverything() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all notes, links, tasks, attached files and the share history from this device. Your calendar is not changed.")
            }
            .alert(
                "TerminalAsset",
                isPresented: Binding(get: { model.notice != nil }, set: { if !$0 { model.clearNotice() } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.notice ?? "")
            }
            .task { await model.refresh() }
            // The permission can be changed in the Settings app while this screen is in the background.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.refresh() } }
            }
            .onAppear(perform: applyLaunchOptions)
        }
    }

    // MARK: - Sections

    private var calendarSection: some View {
        Section {
            LabeledContent("Access") {
                Text(model.calendarAccess.settingsTitle)
                    .foregroundStyle(model.calendarAccess == .fullAccess ? .green : .orange)
            }
            switch model.calendarAccess {
            case .notDetermined:
                Button("Allow Calendar Access") {
                    Task { await model.requestCalendarAccess() }
                }
            case .denied, .writeOnly:
                Button("Open Settings") { openSystemSettings() }
            case .fullAccess, .restricted:
                EmptyView()
            }
        } header: {
            Text("Calendar")
        } footer: {
            Text(model.calendarAccess.settingsExplanation)
        }
    }

    private var weatherSection: some View {
        Section {
            Toggle("Show weather on Today", isOn: $showWeather)
        } header: {
            Text("Weather")
        } footer: {
            Text("Uses your approximate location. A position rounded to about 1 km is used to look up the city name (Apple) and to get the forecast (Open-Meteo). No account, name or calendar data is sent. Turn this off to stop using your location.")
        }
    }

    private var storageSection: some View {
        Section {
            LabeledContent("Attached files", value: model.attachmentsBytes.formatted(.byteCount(style: .file)))
        } header: {
            Text("Storage")
        } footer: {
            Text("Files you share into TerminalAsset are kept on this device. They are never moved or deleted unless you delete them or choose Delete all data.")
        }
    }

    private var privacySection: some View {
        Section {
            NavigationLink(value: SettingsRoute.privacy) {
                Label("How your data is used", systemImage: "hand.raised")
            }
            Button {
                Task {
                    guard let document = await model.makeExport() else { return }
                    exportDocument = document
                    exporting = true
                }
            } label: {
                Label("Export my data", systemImage: "square.and.arrow.up")
            }
            .disabled(model.isWorking)
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete all data", systemImage: "trash")
            }
            .disabled(model.isWorking)
        } header: {
            Text("Privacy & data")
        } footer: {
            Text("Export saves your notes, links, tasks and file names as a JSON file you choose where to keep.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: Self.versionText)
        }
    }

    // MARK: - Helpers

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func openSystemSettings() {
        if let url = URL(string: "app-settings:") { openURL(url) }
    }

    private func applyLaunchOptions() {
        #if DEBUG
        if LaunchOptions.privacyDetail, path.isEmpty { path = [.privacy] }
        #endif
    }
}

#if DEBUG
#Preview("Settings") {
    if let app = try? AppBootstrap.makeSampleModel() {
        SettingsView(model: app.settings)
    }
}
#endif
