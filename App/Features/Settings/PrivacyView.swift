import SwiftUI

/// Plain answers to "where does my data go?", written to match what the app actually does today.
/// If a feature ever sends something new off the device, this page and its consent step change first.
struct PrivacyView: View {
    private struct Row: Identifiable {
        let id: String
        let symbol: String
        let title: LocalizedStringKey
        let detail: LocalizedStringKey
    }

    private let onDevice = [
        Row(id: "calendar", symbol: "calendar", title: "Your calendar",
            detail: "Read from the system calendar on this iPhone to build Today, Calendar and Search. Events you add are saved to your calendar. Nothing about your calendar is uploaded."),
        Row(id: "context", symbol: "note.text", title: "Notes, links, tasks and files",
            detail: "Stored only on this iPhone, in the app's own storage. Search and quick add run on the device too."),
        Row(id: "shared", symbol: "square.and.arrow.down", title: "Things you share in",
            detail: "Items sent from other apps wait in the Inbox on this iPhone until you attach them to an event.")
    ]

    private let offDevice = [
        Row(id: "city", symbol: "location", title: "City name",
            detail: "If weather is on, a position rounded to about 1 km is sent to Apple's location service to get the name of your city."),
        Row(id: "forecast", symbol: "cloud.sun", title: "Forecast",
            detail: "The same rounded position is sent to Open-Meteo, a free weather service, to get the forecast. It receives no name, account or calendar data.")
    ]

    private let never = [
        Row(id: "account", symbol: "person.crop.circle.badge.xmark", title: "No account",
            detail: "There is nothing to sign up for or sign in to."),
        Row(id: "tracking", symbol: "eye.slash", title: "No tracking",
            detail: "No analytics, no advertising and no data sold or shared.")
    ]

    var body: some View {
        List {
            Section {
                ForEach(onDevice) { item in rowView(item, tint: .green) }
            } header: {
                Text("Stays on this iPhone")
            }

            Section {
                ForEach(offDevice) { item in rowView(item, tint: .orange) }
            } header: {
                Text("Leaves this iPhone")
            } footer: {
                Text("Turn off “Show weather on Today” in Settings and nothing leaves this iPhone.")
            }

            Section {
                ForEach(never) { item in rowView(item, tint: .green) }
            } header: {
                Text("What we never do")
            } footer: {
                Text("If TerminalAsset ever adds a feature that sends something else, it will tell you exactly what is sent and why before it sends anything, and only after you agree.")
            }
        }
        .navigationTitle("Your data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func rowView(_ row: Row, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.symbol)
                .frame(width: 26)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title).font(.body.weight(.medium))
                Text(row.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Your data") {
    NavigationStack { PrivacyView() }
}
