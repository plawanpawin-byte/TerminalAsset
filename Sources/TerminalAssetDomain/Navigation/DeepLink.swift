import Foundation

/// Where a tap from outside the app (a notification, the widget) should land.
///
/// Encoded as `terminalasset://event?key=<event key>`. Only this app's own scheme and shape are accepted, so a link
/// from elsewhere can at most open an event that already exists in the app; it cannot change anything.
public enum DeepLink: Sendable, Equatable {
    case event(EventKey)

    public static let scheme = "terminalasset"

    public var url: URL? {
        switch self {
        case .event(let key):
            var components = URLComponents()
            components.scheme = Self.scheme
            components.host = "event"
            components.queryItems = [URLQueryItem(name: "key", value: key.rawValue)]
            return components.url
        }
    }

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }

        switch components.host?.lowercased() {
        case "event":
            guard let raw = components.queryItems?.first(where: { $0.name == "key" })?.value, !raw.isEmpty else {
                return nil
            }
            self = .event(EventKey(rawValue: raw))
        default:
            return nil
        }
    }
}
