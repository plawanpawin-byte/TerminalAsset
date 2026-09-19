import SwiftUI

/// Pro upsell. Purchases are not connected yet: the button explains that instead of pretending to charge.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var showingNotice = false

    private struct Feature: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
    }

    private let features = [
        Feature(id: "prep", symbol: "sparkles", title: "Cloud prep briefs",
                detail: "Written summaries, open questions and checklists for every event."),
        Feature(id: "search", symbol: "magnifyingglass", title: "Deeper search",
                detail: "A larger index that understands meaning, not just keywords."),
        Feature(id: "files", symbol: "doc.viewfinder", title: "Long documents and images",
                detail: "Understand PDFs, spreadsheets and photos you attach."),
        Feature(id: "auto", symbol: "bolt.fill", title: "Automation",
                detail: "Have context prepared before each event without lifting a finger.")
    ]

    private let comparison: [(String, Bool, Bool)] = [
        ("Calendar and Today timeline", true, true),
        ("Notes, links and tasks", true, true),
        ("Basic search", true, true),
        ("Cloud prep briefs", false, true),
        ("Deeper semantic search", false, true),
        ("Long-document analysis", false, true)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    hero
                    featureList
                    comparisonTable
                    priceCard
                    footerLinks
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Not available yet", isPresented: $showingNotice) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Purchases will be connected in a later version. Nothing was charged.")
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 44))
                .foregroundStyle(.white)
                .frame(width: 84, height: 84)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .accessibilityHidden(true)
            Text("TerminalAsset Pro")
                .font(.largeTitle.weight(.bold))
            Text("The right context, prepared for you before every event.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(features) { feature in
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: feature.symbol)
                        .font(.title3)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 30)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(feature.title).font(.headline)
                        Text(feature.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .card()
    }

    private var comparisonTable: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Text("Free").frame(width: 56)
                Text("Pro").frame(width: 56)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 8)

            ForEach(comparison, id: \.0) { row in
                Divider()
                HStack {
                    Text(row.0).font(.subheadline)
                    Spacer()
                    mark(row.1).frame(width: 56)
                    mark(row.2).frame(width: 56)
                }
                .padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(row.0). Free: \(row.1 ? "included" : "not included"). Pro: \(row.2 ? "included" : "not included").")
            }
        }
        .card()
    }

    private func mark(_ included: Bool) -> some View {
        Image(systemName: included ? "checkmark.circle.fill" : "minus")
            .foregroundStyle(included ? Color.accentColor : .secondary)
    }

    private var priceCard: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly").font(.headline)
                    Text("Cancel anytime in Settings")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text("$9.99")
                        .font(.title3.weight(.semibold))
                    Text("/ month")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
            .card()
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 2)
            )

            Button {
                showingNotice = true
            } label: {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Sample price. The App Store shows the final price before you confirm.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
    }

    private var footerLinks: some View {
        HStack(spacing: 20) {
            Button("Restore Purchases") { showingNotice = true }
            Text("·").foregroundStyle(.tertiary)
            Button("Terms") {}
            Text("·").foregroundStyle(.tertiary)
            Button("Privacy") {}
        }
        .font(.footnote)
    }
}

#Preview("Paywall") {
    PaywallView()
}
