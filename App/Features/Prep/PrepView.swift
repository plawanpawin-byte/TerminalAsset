import SwiftUI

struct PrepView: View {
    @State private var blocks = UIFixtures.prepBlocks(now: .now)
    @State private var showingPaywall = false
    @State private var path: [PrepBlock] = []

    /// Briefs for events starting within a day are "coming up"; the rest wait under "Later".
    private var comingUp: [PrepBlock] {
        blocks.filter { $0.startsAt < Date.now.addingTimeInterval(24 * 3600) }
    }

    private var later: [PrepBlock] {
        blocks.filter { $0.startsAt >= Date.now.addingTimeInterval(24 * 3600) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if !comingUp.isEmpty {
                    Section("Coming up") {
                        ForEach(comingUp) { block in
                            PrepRow(block: block) { showingPaywall = true }
                        }
                    }
                }
                if !later.isEmpty {
                    Section("Later") {
                        ForEach(later) { block in
                            PrepRow(block: block) { showingPaywall = true }
                        }
                    }
                }
                Section {
                    SampleDataNote()
                } footer: {
                    Text("Ready before you need it. Each brief is drafted from the context attached to an upcoming event.")
                }
                .listRowBackground(Color.clear)
            }
            .navigationTitle("Prep")
            .navigationDestination(for: PrepBlock.self) { block in
                PrepDetailView(block: block)
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .onAppear(perform: applyLaunchOptions)
        }
    }

    private func applyLaunchOptions() {
        #if DEBUG
        if LaunchOptions.prepDetail, path.isEmpty, let first = blocks.first {
            path = [first]
        }
        #endif
    }
}

private struct PrepRow: View {
    let block: PrepBlock
    let onUpgrade: () -> Void

    var body: some View {
        switch block.status {
        case .ready:
            NavigationLink(value: block) { content }
        case .generating, .needsPro, .offline:
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(block.eventTitle)
                    .font(.headline)
                Spacer(minLength: 8)
                status
                    .font(.caption.weight(.medium))
            }
            Text(block.startsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                .font(.footnote)
                .foregroundStyle(.secondary)

            switch block.status {
            case .ready:
                if let summary = block.summary {
                    Text(summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Label("\(block.keyItems.count) items to have ready", systemImage: "tray.full")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

            case .generating:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Preparing your brief…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

            case .needsPro:
                localItems
                Button(action: onUpgrade) {
                    Label("Cloud prep is part of Pro", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)

            case .offline:
                Label("Offline. The written brief needs a connection.", systemImage: "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                localItems
            }
        }
        .labelStyle(.titleAndIcon)
        .padding(.vertical, 4)
    }

    /// One quiet label instead of a coloured capsule: where the brief was drafted, or why there isn't one.
    @ViewBuilder
    private var status: some View {
        switch block.status {
        case .ready:
            if let provider = block.provider {
                Label(provider.title, systemImage: provider.symbol)
                    .foregroundStyle(.green)
            }
        case .generating:
            Label("Preparing", systemImage: "hourglass")
                .foregroundStyle(.blue)
        case .needsPro:
            Label("Pro", systemImage: "lock.fill")
                .foregroundStyle(.purple)
        case .offline:
            Label("Offline", systemImage: "wifi.slash")
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var localItems: some View {
        ForEach(block.keyItems, id: \.self) { item in
            Label(item, systemImage: "doc.text")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview("Prep") {
    PrepView()
}
