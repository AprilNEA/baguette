import Foundation

/// `Defaults` backed by two simctl children per operation:
///
/// 1. `xcrun simctl get_app_container <udid> <bundle> data|groups` — where
///    the preferences live, so no container path is ever guessed.
/// 2. `xcrun simctl spawn <udid> defaults export|write|delete <plist> …` —
///    the simulator's own `defaults` tool, which goes through its
///    `cfprefsd` and so can't race the daemon's cache the way a host-side
///    file edit would.
///
/// The orchestration (argv assembly via `PreferenceDomain` /
/// `PreferenceValue`, exit-code mapping, export parsing) is unit-covered
/// through `MockSubprocess`; only `HostSubprocess`'s real spawn is
/// integration-only.
final class SimctlDefaults: Defaults, @unchecked Sendable {
    private let udid: String
    private let subprocess: any Subprocess
    private let xcrun: URL

    init(
        udid: String,
        subprocess: any Subprocess = HostSubprocess(),
        xcrun: URL = URL(fileURLWithPath: "/usr/bin/xcrun")
    ) {
        self.udid = udid
        self.subprocess = subprocess
        self.xcrun = xcrun
    }

    func read(_ domain: PreferenceDomain) async throws -> Preferences {
        let output = try await defaults(["export", plist(of: domain), "-"])
        guard let preferences = Preferences(export: output) else {
            throw DefaultsError.unreadableDomain
        }
        return preferences
    }

    func write(_ value: PreferenceValue, forKey key: String, in domain: PreferenceDomain) async throws {
        _ = try await defaults(["write", plist(of: domain), key, value.xmlFragment])
    }

    func delete(key: String, in domain: PreferenceDomain) async throws {
        _ = try await defaults(["delete", plist(of: domain), key])
    }

    // MARK: - the two children

    /// The preferences plist inside the container simctl reports. Exit
    /// codes measured against Xcode 27: 2 = no such app, 149 = shut down.
    /// A suite missing from the app's group listing is `groupNotFound`.
    private func plist(of domain: PreferenceDomain) async throws -> String {
        let (status, output) = try await capture(domain.containerArguments(udid: udid))
        switch status {
        case 0: break
        case 2: throw DefaultsError.appNotInstalled(bundleID: domain.bundleID)
        default: throw Self.failure(status)
        }
        guard let plist = domain.plistPath(inContainerOutput: String(decoding: output, as: UTF8.self)) else {
            if let suite = domain.suite {
                throw DefaultsError.groupNotFound(group: suite, bundleID: domain.bundleID)
            }
            throw DefaultsError.simctlFailed(status: status)
        }
        return plist
    }

    private func defaults(_ arguments: [String]) async throws -> Data {
        let (status, output) = try await capture(["simctl", "spawn", udid, "defaults"] + arguments)
        guard status == 0 else { throw Self.failure(status) }
        return output
    }

    private static func failure(_ status: Int32) -> DefaultsError {
        status == 149 ? .deviceNotBooted : .simctlFailed(status: status)
    }

    /// Accumulates a child's output across chunks that may land on any queue.
    private final class ByteBox: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()

        func append(_ chunk: Data) {
            lock.lock(); defer { lock.unlock() }
            bytes.append(chunk)
        }

        func collected() -> Data {
            lock.lock(); defer { lock.unlock() }
            return bytes
        }
    }

    /// Run `xcrun <arguments>` to completion; hand back its exit status and
    /// everything it wrote, parsed once at exit rather than per chunk.
    private func capture(_ arguments: [String]) async throws -> (Int32, Data) {
        let buffer = ByteBox()
        return try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<(Int32, Data), Error>) in
            do {
                try subprocess.run(
                    executable: xcrun,
                    arguments: arguments,
                    onBytes: { buffer.append($0) },
                    onExit: { continuation.resume(returning: ($0, buffer.collected())) }
                )
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
