import Foundation

/// A saved set of preferences written back in one go — what makes an
/// export a repeatable test setup. Like `PreferenceEdit`, the running
/// app's lifecycle is explicit: `relaunch` quits it once before the first
/// value and launches it once after the last, so it starts from the whole
/// set rather than restarting per key.
public struct PreferenceImport: Equatable, Sendable {
    public let suite: PreferenceSuite
    public let preferences: Preferences
    public let relaunch: Bool

    public init(suite: PreferenceSuite, preferences: Preferences, relaunch: Bool = false) {
        self.suite = suite
        self.preferences = preferences
        self.relaunch = relaunch
    }

    /// Write every value, in key order, and return how many were written.
    /// Keys not in the import are left alone. Stops at the first failure
    /// and leaves the app quit, as `PreferenceEdit` does.
    func apply(on defaults: any Defaults, apps: any Apps) async throws -> Int {
        if relaunch { try await apps.terminate(bundleID: suite.bundleID) }
        for key in preferences.values.keys.sorted() {
            try await defaults.write(preferences.values[key]!, forKey: key, in: suite)
        }
        if relaunch { try await apps.launch(bundleID: suite.bundleID) }
        return preferences.values.count
    }
}
