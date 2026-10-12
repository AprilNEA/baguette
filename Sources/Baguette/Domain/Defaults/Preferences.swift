import Foundation

/// The persisted preferences of one domain, as `defaults export` printed
/// them — every value typed. Registered defaults (`register(defaults:)`)
/// live only in the app's memory and never appear here.
public struct Preferences: Equatable, Sendable {
    public let values: [String: PreferenceValue]

    public init(values: [String: PreferenceValue]) {
        self.values = values
    }

    /// Read `defaults export <domain> -` output. `nil` when it isn't a
    /// plist dictionary, so garbage on stdout is an error rather than an
    /// empty domain. A domain with nothing stored exports `<dict/>` and
    /// reads as no values.
    public init?(export data: Data) {
        guard let plist = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil
              ),
              plist is [String: Any],
              case .dictionary(let values)? = PreferenceValue(plist: plist)
        else { return nil }
        self.values = values
    }

    /// Every stored value, keyed, each in `PreferenceValue.json`'s typed
    /// shape.
    public var json: [String: Any] {
        values.mapValues(\.json)
    }

    /// The whole domain as a read answers it — which app and suite it
    /// came from, then every value typed. `suite` is omitted for an
    /// app's standard defaults.
    public func json(in domain: PreferenceDomain) -> [String: Any] {
        var envelope: [String: Any] = ["bundleId": domain.bundleID, "values": json]
        if let suite = domain.suite { envelope["suite"] = suite }
        return envelope
    }

    /// One key, with `present` telling a key that was never stored apart
    /// from one stored as `false`, `0` or `""`.
    public func json(forKey key: String) -> [String: Any] {
        guard let value = values[key] else { return ["key": key, "present": false] }
        return value.json.merging(["key": key, "present": true]) { _, new in new }
    }
}
