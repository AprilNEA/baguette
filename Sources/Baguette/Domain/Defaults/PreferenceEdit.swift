import Foundation

/// One change to an app's persisted preferences — store a value under a
/// key, or remove the key — with what happens to the running app spelled
/// out rather than implied.
///
/// A running app holds its own in-memory copy of `UserDefaults`, so a
/// persisted change it hasn't re-read is invisible to it (and its next
/// save may write the old value back). `relaunch` quits the app first and
/// launches it after, the one order that guarantees the app starts from
/// the edited file. Without it the app is left alone and the edit is only
/// known to be on disk.
public struct PreferenceEdit: Equatable, Sendable {
    public enum Change: Equatable, Sendable {
        case set(PreferenceValue)
        case remove
    }

    public let suite: PreferenceSuite
    public let key: String
    public let change: Change
    public let relaunch: Bool

    public init(suite: PreferenceSuite, key: String, change: Change, relaunch: Bool = false) {
        self.suite = suite
        self.key = key
        self.change = change
        self.relaunch = relaunch
    }

    /// Apply the edit. Returns whether anything changed: always for a
    /// `set`, and for a `remove` only when the key was stored — removing
    /// an absent key is a no-op, so test setup can run it unconditionally.
    ///
    /// When storing fails the app stays quit: launching it would hide the
    /// failure behind a running app showing the old value.
    func apply(on defaults: any Defaults, apps: any Apps) async throws -> Bool {
        if relaunch { try await apps.terminate(bundleID: suite.bundleID) }
        let changed: Bool
        switch change {
        case .set(let value):
            try await defaults.write(value, forKey: key, in: suite)
            changed = true
        case .remove:
            changed = try await defaults.read(suite).values[key] != nil
            if changed { try await defaults.delete(key: key, in: suite) }
        }
        if relaunch { try await apps.launch(bundleID: suite.bundleID) }
        return changed
    }
}
