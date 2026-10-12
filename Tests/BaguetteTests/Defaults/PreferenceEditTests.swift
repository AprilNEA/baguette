import Testing
import Foundation
import Mockable
@testable import Baguette

/// An edit to an app's persisted preferences, with the app lifecycle
/// made explicit: a running app keeps its own copy of `UserDefaults` in
/// memory, so the only edit it is guaranteed to observe is one made
/// while it isn't running. `relaunch` quits it first and launches it
/// after; without it, the app is left alone.
@Suite("PreferenceEdit")
struct PreferenceEditTests {

    final class Journal: @unchecked Sendable {
        var steps: [String] = []
    }

    private static let suite = try! PreferenceSuite(bundleID: "com.example.app")

    private func host(
        stored: [String: PreferenceValue] = [:],
        writeFails: Bool = false
    ) -> (MockDefaults, MockApps, Journal) {
        let defaults = MockDefaults()
        let apps = MockApps()
        let journal = Journal()
        given(defaults).read(.any).willReturn(Preferences(values: stored))
        if writeFails {
            given(defaults).write(.any, forKey: .any, in: .any)
                .willThrow(DefaultsError.simctlFailed(status: 1))
        } else {
            given(defaults).write(.any, forKey: .any, in: .any).willProduce { value, key, _ in
                journal.steps.append("write \(key)=\(value.xmlFragment)")
            }
        }
        given(defaults).delete(key: .any, in: .any).willProduce { key, _ in
            journal.steps.append("delete \(key)")
        }
        given(apps).terminate(bundleID: .any).willProduce { journal.steps.append("terminate \($0)") }
        given(apps).launch(bundleID: .any).willProduce { journal.steps.append("launch \($0)") }
        return (defaults, apps, journal)
    }

    @Test func `should store a value and leave the app alone when not asked to relaunch`() async throws {
        let (defaults, apps, journal) = host()
        let edit = PreferenceEdit(suite: Self.suite, key: "seen", change: .set(.bool(false)))

        let changed = try await edit.apply(on: defaults, apps: apps)

        #expect(changed)
        #expect(journal.steps == ["write seen=<false/>"])
    }

    @Test func `should quit the app before storing and launch it after when asked to relaunch`() async throws {
        let (defaults, apps, journal) = host()
        let edit = PreferenceEdit(
            suite: Self.suite, key: "seen", change: .set(.bool(false)), relaunch: true
        )

        _ = try await edit.apply(on: defaults, apps: apps)

        #expect(journal.steps
            == ["terminate com.example.app", "write seen=<false/>", "launch com.example.app"])
    }

    @Test func `should remove a stored key`() async throws {
        let (defaults, apps, journal) = host(stored: ["seen": .bool(true), "other": .integer(1)])
        let edit = PreferenceEdit(suite: Self.suite, key: "seen", change: .remove)

        #expect(try await edit.apply(on: defaults, apps: apps))
        #expect(journal.steps == ["delete seen"])
    }

    @Test func `should report nothing removed when the key was never stored`() async throws {
        let (defaults, apps, journal) = host(stored: ["other": .integer(1)])
        let edit = PreferenceEdit(suite: Self.suite, key: "seen", change: .remove, relaunch: true)

        #expect(try await edit.apply(on: defaults, apps: apps) == false)
        #expect(journal.steps == ["terminate com.example.app", "launch com.example.app"])
    }

    @Test func `should leave the app quit when storing fails`() async {
        let (defaults, apps, journal) = host(writeFails: true)
        let edit = PreferenceEdit(
            suite: Self.suite, key: "seen", change: .set(.bool(false)), relaunch: true
        )

        await #expect(throws: DefaultsError.simctlFailed(status: 1)) {
            try await edit.apply(on: defaults, apps: apps)
        }
        #expect(journal.steps == ["terminate com.example.app"])
    }
}
