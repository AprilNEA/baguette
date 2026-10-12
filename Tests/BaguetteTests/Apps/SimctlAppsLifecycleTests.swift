import Testing
import Foundation
import Mockable
@testable import Baguette

/// Quitting and launching an app — what a preferences edit wraps itself
/// in when asked to relaunch, so the app starts from the edited file.
@Suite("SimctlApps lifecycle")
struct SimctlAppsLifecycleTests {

    final class Captures: @unchecked Sendable {
        var arguments: [String]?
    }

    private func makeApps(exitCode: Int32 = 0) -> (SimctlApps, Captures) {
        let sub = MockSubprocess()
        let captures = Captures()
        given(sub).run(
            executable: .any, arguments: .any, onBytes: .any, onExit: .any
        ).willProduce { _, args, _, onExit in
            captures.arguments = args
            onExit(exitCode)
        }
        return (SimctlApps(udid: "U", subprocess: sub), captures)
    }

    @Test func `should quit a running app through simctl terminate`() async throws {
        let (apps, captures) = makeApps()
        try await apps.terminate(bundleID: "com.example.app")
        #expect(captures.arguments == ["simctl", "terminate", "U", "com.example.app"])
    }

    @Test func `should treat quitting an app that isn't running as done`() async throws {
        // simctl exits 3 ("found nothing to terminate") — measured on Xcode 27.
        let (apps, _) = makeApps(exitCode: 3)
        try await apps.terminate(bundleID: "com.example.app")
    }

    @Test func `should report a quit that failed for any other reason`() async {
        let (apps, _) = makeApps(exitCode: 149)
        await #expect(throws: AppsError.terminateFailed(status: 149)) {
            try await apps.terminate(bundleID: "com.example.app")
        }
    }

    @Test func `should launch an app through simctl launch`() async throws {
        let (apps, captures) = makeApps()
        try await apps.launch(bundleID: "com.example.app")
        #expect(captures.arguments == ["simctl", "launch", "U", "com.example.app"])
    }

    @Test func `should report a launch that failed`() async {
        let (apps, _) = makeApps(exitCode: 4)
        await #expect(throws: AppsError.launchFailed(status: 4)) {
            try await apps.launch(bundleID: "com.example.app")
        }
    }
}
