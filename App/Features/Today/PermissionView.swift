import SwiftUI
import TerminalAssetDomain

/// Explains why calendar access is needed before the system prompt appears, and guides recovery when it is off.
struct PermissionView: View {
    let status: CalendarAuthorization
    let onAllow: () async -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 56))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("See your day with its context")
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(explanation)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if status == .notDetermined {
                Button {
                    Task { await onAllow() }
                } label: {
                    Text("Allow Calendar Access")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else if let settings = URL(string: "app-settings:") {
                Button {
                    openURL(settings)
                } label: {
                    Text("Open Settings")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Label("Your calendar is read on this device and never uploaded.", systemImage: "lock.shield")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var explanation: String {
        switch status {
        case .notDetermined:
            "TerminalAsset shows the notes, links and tasks you need right when each event starts."
        case .denied, .writeOnly:
            "Calendar access is off. Turn on Full Access for TerminalAsset in Settings to see your events."
        case .restricted:
            "Calendar access is restricted on this device, for example by Screen Time or a device policy."
        case .fullAccess:
            "Calendar access is on."
        }
    }
}
