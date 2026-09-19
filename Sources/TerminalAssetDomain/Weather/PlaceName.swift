import Foundation

/// Picks the name to show for a place from the parts a geocoder returns.
public enum PlaceName {
    /// Prefers the locality (the city). Some places, such as Bangkok, report a district as the locality, so a
    /// district-like name is skipped in favour of the administrative area ("Bangkok").
    public static func choose(
        locality: String?,
        subAdministrativeArea: String?,
        administrativeArea: String?
    ) -> String? {
        let locality = clean(locality)
        let sub = clean(subAdministrativeArea)
        let admin = clean(administrativeArea)

        if let locality, !looksLikeDistrict(locality) { return locality }
        return admin ?? sub ?? locality
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private static func looksLikeDistrict(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.hasSuffix(" district") || lower.hasSuffix(" ward") || lower.hasPrefix("khet ") || lower.hasPrefix("เขต")
    }
}
