import Foundation

/// Which preferences: an app's standard defaults, or a named suite —
/// one of its App Groups (`UserDefaults(suiteName: "group.…")`) or a
/// suite of its own.
///
/// The domain never guesses a container path. CoreSimulator's
/// `…/Containers/Data/Application/<uuid>/` layout is undocumented and the
/// UUID changes on every reinstall, so `containerArguments` asks simctl
/// for it; only the plist *inside* the reported container is ours to
/// name. For an App Group, simctl lists the groups the app's own entitlements
/// grant, so a group the app doesn't belong to fails loudly instead of
/// quietly landing in standard defaults.
public struct PreferenceDomain: Equatable, Sendable {
    public let bundleID: String
    /// A named suite, or `nil` for the app's standard defaults. A suite
    /// starting `group.` is an App Group (Apple requires the prefix) and
    /// lives in that group's container; any other suite
    /// (`UserDefaults(suiteName: "com.example.debug")`) is the app's own
    /// and lives in its data container. Either way the plist is named for
    /// the suite.
    public let suite: String?

    /// The App Group this suite lives in, or `nil` when the preferences
    /// are in the app's own data container.
    public var group: String? {
        suite.flatMap { $0.hasPrefix("group.") ? $0 : nil }
    }

    /// Both identifiers become a path component and a simctl argument, so
    /// anything that could climb out of the container (`/`, `..`) or read
    /// as a flag (`-…`) is refused here, before it reaches either.
    public init(bundleID: String, suite: String? = nil) throws {
        guard Self.isIdentifier(bundleID) else {
            throw PreferenceDomainError.invalidIdentifier(bundleID)
        }
        if let suite, !Self.isIdentifier(suite) {
            throw PreferenceDomainError.invalidIdentifier(suite)
        }
        self.bundleID = bundleID
        self.suite = suite
    }

    /// `xcrun` argv that prints where these preferences live: the app's
    /// data container, or — for an App Group suite — every App Group
    /// container the app has, as `<group id>\t<path>` lines. simctl's own
    /// `<group id>` form exits 117 even for a group the app has (Xcode
    /// 27), so the group is picked out of the listing instead.
    public func containerArguments(udid: String) -> [String] {
        ["simctl", "get_app_container", udid, bundleID, group == nil ? "data" : "groups"]
    }

    /// The preferences plist inside the container simctl printed, or
    /// `nil` when it names none — for an App Group suite, when the app's
    /// groups don't include it.
    public func plistPath(inContainerOutput output: String) -> String? {
        let container: String?
        if let group {
            container = output.split(separator: "\n").lazy.compactMap { line -> String? in
                let fields = line.split(separator: "\t", maxSplits: 1)
                guard fields.count == 2, fields[0] == group else { return nil }
                return String(fields[1])
            }.first
        } else {
            container = output.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let container, !container.isEmpty else { return nil }
        return container + "/Library/Preferences/\(suite ?? bundleID).plist"
    }

    private static func isIdentifier(_ text: String) -> Bool {
        !text.isEmpty && !text.hasPrefix("-") && !text.contains("/") && !text.contains("..")
    }
}

public enum PreferenceDomainError: Error, Equatable, CustomStringConvertible {
    case invalidIdentifier(String)

    public var description: String {
        switch self {
        case .invalidIdentifier(let text):
            return "\"\(text)\" is not a bundle or App Group identifier"
        }
    }
}
