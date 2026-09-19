import SwiftUI

/// Answers, before any cloud call: what is sent, why, and whether it is necessary.
struct CloudPrivacyView: View {
    struct Category: Identifiable {
        enum Necessity {
            case required, optional, never

            var title: String {
                switch self {
                case .required: "Needed"
                case .optional: "Optional"
                case .never: "Never sent"
                }
            }

            var tint: Color {
                switch self {
                case .required: .orange
                case .optional: .blue
                case .never: .green
                }
            }
        }

        let id: String
        let symbol: String
        let title: String
        let why: String
        let necessity: Necessity
    }

    private let categories: [Category] = [
        Category(id: "event", symbol: "calendar", title: "Event title and time",
                 why: "So the brief knows what you are preparing for.", necessity: .required),
        Category(id: "text", symbol: "note.text", title: "Notes and task text",
                 why: "So the brief can summarize what you already know.", necessity: .required),
        Category(id: "links", symbol: "link", title: "Link addresses",
                 why: "So the brief can reference the pages you saved.", necessity: .optional),
        Category(id: "files", symbol: "doc.text", title: "File and image contents",
                 why: "Only if you approve a specific item.", necessity: .never),
        Category(id: "people", symbol: "person.2", title: "Attendees and contacts",
                 why: "Not used to prepare a brief.", necessity: .never)
    ]

    @AppStorage("privacy.sendLinks") private var sendLinks = true

    var body: some View {
        List {
            Section {
                Label {
                    Text("You can use TerminalAsset entirely on this device. The cloud is only used when you choose Hybrid mode and a brief needs more than the device can do.")
                        .font(.subheadline)
                } icon: {
                    Image(systemName: "lock.shield").foregroundStyle(.green)
                }
            }

            Section {
                ForEach(categories) { category in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: category.symbol)
                            .frame(width: 26)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(category.title).font(.body.weight(.medium))
                            Text(category.why)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        Pill(text: category.necessity.title, tint: category.necessity.tint)
                    }
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("What can be sent")
            }

            Section {
                Toggle("Include link addresses", isOn: $sendLinks)
            } footer: {
                Text("Turn this off to keep saved links on your device. Briefs may mention them less precisely.")
            }

            Section { SampleDataNote() }
                .listRowBackground(Color.clear)
        }
        .navigationTitle("Cloud privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Cloud privacy") {
    NavigationStack { CloudPrivacyView() }
}
