import SwiftUI

enum AIProcessingMode: String, CaseIterable, Identifiable {
    case onDeviceOnly
    case hybrid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDeviceOnly: "On-device only"
        case .hybrid: "Hybrid"
        }
    }

    var explanation: String {
        switch self {
        case .onDeviceOnly: "Nothing leaves your iPhone. Briefs are simpler."
        case .hybrid: "On-device first. The cloud is used only for long or complex briefs, and you can see what is sent."
        }
    }
}

struct SettingsView: View {
    @AppStorage("settings.aiMode") private var aiMode: AIProcessingMode = .onDeviceOnly
    @AppStorage("settings.backgroundPrep") private var backgroundPrep = true
    @AppStorage("settings.decayDays") private var decayDays = 30
    @AppStorage("settings.coldStorage") private var coldStorage = false
    @AppStorage(WeatherViewModel.enabledKey) private var showWeather = true

    @State private var workCalendar = true
    @State private var personalCalendar = true
    @State private var holidaysCalendar = false
    @State private var showingPaywall = false
    @State private var confirmingDelete = false
    @State private var path: [SettingsRoute] = []

    enum SettingsRoute: Hashable {
        case privacy
    }

    var body: some View {
        NavigationStack(path: $path) {
            Form {
                planSection
                calendarSection
                weatherSection
                intelligenceSection
                storageSection
                privacySection
                aboutSection
                Section { SampleDataNote() }
                    .listRowBackground(Color.clear)
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { _ in CloudPrivacyView() }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .confirmationDialog(
                "Delete all TerminalAsset data?",
                isPresented: $confirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive) {}
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all context, attachments and search indexes from this device. Your calendar is not changed.")
            }
            .onAppear(perform: applyLaunchOptions)
        }
    }

    // MARK: - Sections

    private var planSection: some View {
        Section {
            Button {
                showingPaywall = true
            } label: {
                HStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Free plan")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("Calendar, local context and basic search")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Text("Upgrade")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Shows the Pro plan")
        }
    }

    private var calendarSection: some View {
        Section {
            LabeledContent("Access") {
                Text("Full access").foregroundStyle(.green)
            }
            Toggle("Work", isOn: $workCalendar)
            Toggle("Personal", isOn: $personalCalendar)
            Toggle("Holidays", isOn: $holidaysCalendar)
        } header: {
            Text("Calendars")
        } footer: {
            Text("Choose which calendars TerminalAsset reads. Your calendar is never uploaded.")
        }
    }

    private var weatherSection: some View {
        Section {
            Toggle("Show weather on Today", isOn: $showWeather)
        } header: {
            Text("Weather")
        } footer: {
            Text("Uses your approximate location. Only a coordinate rounded to about 1 km is sent to the free Open-Meteo weather service to get the forecast: no name, account or calendar data. Turn this off to stop using your location.")
        }
    }

    private var intelligenceSection: some View {
        Section {
            Picker("AI processing", selection: $aiMode) {
                ForEach(AIProcessingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            Toggle("Prepare events in the background", isOn: $backgroundPrep)
            NavigationLink(value: SettingsRoute.privacy) {
                Label("What is sent to the cloud", systemImage: "hand.raised")
            }
        } header: {
            Text("Intelligence")
        } footer: {
            Text(aiMode.explanation + " Background preparation runs when iOS allows it, so timing can vary.")
        }
    }

    private var storageSection: some View {
        Section {
            LabeledContent("Used on this device", value: "48 MB")
            Picker("Compact old context after", selection: $decayDays) {
                Text("14 days").tag(14)
                Text("30 days").tag(30)
                Text("60 days").tag(60)
                Text("90 days").tag(90)
            }
            Toggle("Move large files to iCloud", isOn: $coldStorage)
        } header: {
            Text("Storage")
        } footer: {
            Text("Search indexes for old events are compacted to save space and battery. Your original files are never moved or deleted without you seeing it.")
        }
    }

    private var privacySection: some View {
        Section("Privacy & data") {
            Button {
            } label: {
                Label("Export my data", systemImage: "square.and.arrow.up")
            }
            Button(role: .destructive) {
                confirmingDelete = true
            } label: {
                Label("Delete all data", systemImage: "trash")
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "0.1.0")
            Button {
            } label: {
                Label("Send feedback", systemImage: "bubble.left")
            }
        }
    }

    private func applyLaunchOptions() {
        #if DEBUG
        if LaunchOptions.showPaywall { showingPaywall = true }
        if LaunchOptions.privacyDetail, path.isEmpty { path = [.privacy] }
        #endif
    }
}

#Preview("Settings") {
    SettingsView()
}
