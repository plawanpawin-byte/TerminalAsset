import SwiftUI

struct PrepDetailView: View {
    let block: PrepBlock

    @State private var done: Set<String> = []

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(block.eventTitle)
                        .font(.title2.weight(.bold))
                    Text(block.startsAt.formatted(.dateTime.weekday(.wide).hour().minute()))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        if let provider = block.provider {
                            Label("Drafted \(provider.title.lowercased())", systemImage: provider.symbol)
                                .foregroundStyle(.green)
                        }
                        Label("AI draft", systemImage: "sparkles")
                            .foregroundStyle(.purple)
                    }
                    .font(.caption.weight(.medium))
                }
                .padding(.vertical, 4)
            } footer: {
                Text("AI drafts can be wrong. Check anything important against your sources.")
            }

            if let summary = block.summary {
                Section("Summary") {
                    Text(summary)
                        .font(.body)
                }
            }

            if !block.keyItems.isEmpty {
                Section("Have ready") {
                    ForEach(block.keyItems, id: \.self) { item in
                        Label(item, systemImage: "doc.text")
                    }
                }
            }

            if !block.questions.isEmpty {
                Section("Questions to settle") {
                    ForEach(block.questions, id: \.self) { question in
                        Label(question, systemImage: "questionmark.bubble")
                    }
                }
            }

            if !block.checklist.isEmpty {
                Section("Checklist") {
                    ForEach(block.checklist, id: \.self) { item in
                        Button {
                            if done.contains(item) { done.remove(item) } else { done.insert(item) }
                        } label: {
                            Label {
                                Text(item)
                                    .strikethrough(done.contains(item))
                                    .foregroundStyle(done.contains(item) ? .secondary : .primary)
                            } icon: {
                                Image(systemName: done.contains(item) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .accessibilityValue(done.contains(item) ? "Done" : "Not done")
                    }
                }
            }

            if !block.sources.isEmpty {
                sourcesSection
            }

            Section {
                Button {
                } label: {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
                .disabled(true)
            } footer: {
                Text("Regenerating arrives with the AI phase.")
            }

            Section { SampleDataNote() }
                .listRowBackground(Color.clear)
        }
        .navigationTitle("Prep brief")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Transparency about exactly what fed the draft and what left the device.
    private var sourcesSection: some View {
        Section {
            ForEach(block.sources) { source in
                HStack {
                    Label(source.title, systemImage: source.symbol)
                    Spacer()
                    if source.sentToCloud {
                        Label("Sent", systemImage: "cloud")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.orange)
                    } else {
                        Label("On device", systemImage: "iphone")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            NavigationLink {
                CloudPrivacyView()
            } label: {
                Label("What is sent to the cloud?", systemImage: "hand.raised")
            }
        } header: {
            Text("Sources used")
        } footer: {
            Text("Only the items marked Sent left this device, and only as text.")
        }
    }
}
