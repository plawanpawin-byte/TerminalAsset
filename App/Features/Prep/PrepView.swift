import SwiftUI

struct PrepView: View {
    @State private var blocks = UIFixtures.prepBlocks(now: .now)
    @State private var showingPaywall = false
    @State private var path: [PrepBlock] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    Text("Ready before you need it. Each block is drafted from the context attached to an upcoming event.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    ForEach(blocks) { block in
                        PrepCard(block: block) { showingPaywall = true }
                    }

                    SampleDataNote().padding(.top, 8)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(Color(.systemGroupedBackground))
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

private struct PrepCard: View {
    let block: PrepBlock
    let onUpgrade: () -> Void

    var body: some View {
        switch block.status {
        case .ready:
            NavigationLink(value: block) { content }
                .buttonStyle(.plain)
        case .generating, .needsPro, .offline:
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            switch block.status {
            case .ready:
                if let summary = block.summary {
                    Text(summary)
                        .font(.subheadline)
                        .lineLimit(3)
                }
                HStack {
                    Label("\(block.keyItems.count) items to have ready", systemImage: "tray.full")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

            case .generating:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Preparing your brief…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

            case .needsPro:
                localItems
                VStack(alignment: .leading, spacing: 8) {
                    Label("Cloud prep is part of Pro", systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                    Text("Get a written brief, open questions and a checklist drafted for this event.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("See Pro", action: onUpgrade)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }

            case .offline:
                Label("You're offline. The written brief needs a connection.", systemImage: "wifi.slash")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                localItems
                Text("Your context still works offline — nothing here is lost.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(block.eventTitle)
                    .font(.headline)
                    .multilineTextAlignment(.leading)
                Text(block.startsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            statusPill
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        switch block.status {
        case .ready:
            if let provider = block.provider {
                Pill(text: provider.title, symbol: provider.symbol, tint: .green)
            }
        case .generating:
            Pill(text: "Preparing", symbol: "hourglass", tint: .blue)
        case .needsPro:
            Pill(text: "Pro", symbol: "lock.fill", tint: .purple)
        case .offline:
            Pill(text: "Offline", symbol: "wifi.slash", tint: .orange)
        }
    }

    @ViewBuilder
    private var localItems: some View {
        if !block.keyItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("In your context")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                ForEach(block.keyItems, id: \.self) { item in
                    Label(item, systemImage: "doc.text")
                        .font(.subheadline)
                }
            }
        }
    }
}

#Preview("Prep") {
    PrepView()
}
