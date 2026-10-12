import Foundation
import Mockable

/// An app's persisted `UserDefaults` on a device — read a domain, store a
/// typed value under a key, remove a key. Named for what it is to the
/// developer ("the app's defaults"), like `Apps` / `StatusBar`.
///
/// Every operation goes through the simulator's own `cfprefsd` (`simctl
/// spawn <udid> defaults …`), never a host-side edit of the plist file,
/// so it can't race the daemon's cache. What it *can't* reach is an
/// already-running app's in-memory copy — `PreferenceEdit` makes the
/// quit / relaunch around an edit explicit.
///
/// `@Mockable` so the CLI command, serve routes and `PreferenceEdit` are
/// unit-tested without a booted simulator. The production impl is
/// `SimctlDefaults`.
@Mockable
protocol Defaults: Sendable {
    /// Every persisted value in `domain`. A domain the app has never
    /// written reads as no values.
    func read(_ domain: PreferenceDomain) async throws -> Preferences

    /// Store `value` under `key`, its type intact. Unrelated keys are
    /// untouched.
    func write(_ value: PreferenceValue, forKey key: String, in domain: PreferenceDomain) async throws

    /// Remove `key`. Throws `DefaultsError.simctlFailed` when it isn't
    /// stored — `PreferenceEdit` reads first so callers never see that.
    func delete(key: String, in domain: PreferenceDomain) async throws
}

/// Why a defaults operation failed, each with the step the user can take.
/// The simctl exit codes behind these were measured on Xcode 27
/// (`docs/features/defaults/design.md`).
enum DefaultsError: Error, Equatable, CustomStringConvertible {
    /// `get_app_container` exited 2 — nothing with that bundle id is installed.
    case appNotInstalled(bundleID: String)
    /// The app's App Group listing doesn't include the suite.
    case groupNotFound(group: String, bundleID: String)
    /// simctl exited 149 — the device is shut down.
    case deviceNotBooted
    /// `defaults export` printed something that isn't a domain.
    case unreadableDomain
    /// Any other non-zero simctl exit.
    case simctlFailed(status: Int32)

    var description: String {
        switch self {
        case .appNotInstalled(let bundleID):
            return "\(bundleID) is not installed on this simulator (check `xcrun simctl listapps`)"
        case .groupNotFound(let group, let bundleID):
            return "\(bundleID) has no App Group \(group) (check its com.apple.security.application-groups entitlement)"
        case .deviceNotBooted:
            return "the simulator is not booted (run `baguette boot`)"
        case .unreadableDomain:
            return "defaults export printed something that is not a preferences domain"
        case .simctlFailed(let status):
            return "xcrun simctl exited \(status)"
        }
    }
}
