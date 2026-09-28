import Foundation
import Testing

@testable import Baguette

@Suite("SimctlIOCapture")
struct SimctlIOCaptureTests {
    @Test func `enumeration preserves the resolved custom device set`() throws {
        let script = try Script("printf '%s\\n' \"$@\"")
        defer { script.remove() }
        let output = try SimctlIOCapture.enumerate(
            udid: "device-id", deviceSetPath: "/custom set/Devices", xcrun: script.url)
        #expect(output == "simctl\n--set\n/custom set/Devices\nio\ndevice-id\nenumerate\n")
    }

    @Test func `default enumeration does not override the device set`() throws {
        let script = try Script("printf '%s\\n' \"$@\"")
        defer { script.remove() }
        #expect(
            try SimctlIOCapture.enumerate(udid: "device-id", xcrun: script.url)
                == "simctl\nio\ndevice-id\nenumerate\n")
    }

    @Test func `output larger than the pipe buffer is drained completely`() throws {
        let script = try Script("/usr/bin/head -c 262144 /dev/zero; printf end")
        defer { script.remove() }
        let output = try SimctlIOCapture.enumerate(udid: "device-id", xcrun: script.url, timeout: 10)
        #expect(output.utf8.count == 262147)
        #expect(output.hasSuffix("end"))
    }

    @Test func `enumeration finishes while every dispatch worker is blocked`() throws {
        let script = try Script("printf ready")
        defer { script.remove() }
        // A loaded host (a busy `serve`, a full test run) can park every global-queue
        // worker; the capture must not depend on one becoming free.
        let release = DispatchSemaphore(value: 0)
        let blockers = 128
        let started = DispatchGroup()
        for _ in 0..<blockers {
            started.enter()
            DispatchQueue.global().async {
                started.leave()
                release.wait()
            }
        }
        defer { for _ in 0..<blockers { release.signal() } }
        _ = started.wait(timeout: .now() + 0.5)
        #expect(try SimctlIOCapture.enumerate(udid: "device-id", xcrun: script.url, timeout: 2) == "ready")
    }

    @Test func `a child that closes output but ignores termination is killed at the deadline`() throws {
        let script = try Script("trap '' TERM; exec 1>&- 2>&-; exec /bin/sleep 30")
        defer { script.remove() }
        let process = Process()
        let start = ContinuousClock.now
        #expect(throws: SimctlIOCapture.Failure.timedOut(udid: "device-id", seconds: 1)) {
            try SimctlIOCapture.enumerate(udid: "device-id", xcrun: script.url, timeout: 1, process: process)
        }
        #expect(start.duration(to: .now) < .seconds(5))
        let pid = process.processIdentifier
        #expect(pid > 0)
        try #require(!process.isRunning)
        #expect(process.terminationReason == .uncaughtSignal)
        #expect(process.terminationStatus == SIGKILL)
        #expect(kill(pid, 0) == -1)
        #expect(errno == ESRCH)
    }

    @Test func `failed enumeration retains the device status and diagnostics`() throws {
        let script = try Script("echo 'CoreSimulator unavailable' >&2; exit 7")
        defer { script.remove() }
        #expect(
            throws: SimctlIOCapture.Failure.failed(
                udid: "device-id", status: 7, output: "CoreSimulator unavailable\n")
        ) {
            try SimctlIOCapture.enumerate(udid: "device-id", xcrun: script.url)
        }
    }

    @Test func `timeout cancels an open output pipe and releases its reader`() async throws {
        let script = try Script("printf started; exec /bin/sleep 30")
        defer { script.remove() }
        let process = Process()
        let start = ContinuousClock.now
        #expect(throws: SimctlIOCapture.Failure.timedOut(udid: "device-id", seconds: 1)) {
            try SimctlIOCapture.enumerate(udid: "device-id", xcrun: script.url, timeout: 1, process: process)
        }
        #expect(start.duration(to: .now) < .seconds(5))
        try #require(!process.isRunning)
        #expect(process.terminationStatus == SIGKILL)
        let pipe = try #require(process.standardOutput as? Pipe)
        try await Self.expectClosed(pipe.fileHandleForReading)
    }

    @Test func `launch failure releases the output reader without waiting for the deadline`() async throws {
        let script = try Script("exit 0")
        defer { script.remove() }
        let process = Process()
        let start = ContinuousClock.now
        #expect(throws: CocoaError.self) {
            try SimctlIOCapture.enumerate(
                udid: "device-id", xcrun: script.directory.appendingPathComponent("missing"),
                timeout: 30, process: process)
        }
        #expect(start.duration(to: .now) < .seconds(5))
        let pipe = try #require(process.standardOutput as? Pipe)
        try await Self.expectClosed(pipe.fileHandleForReading)
    }

    private static func expectClosed(_ handle: FileHandle) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while ContinuousClock.now < deadline {
            do {
                _ = try handle.read(upToCount: 0)
            } catch {
                #expect(error is CocoaError)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("The output reader remained open after cancellation")
    }

    private struct Script {
        let directory: URL
        var url: URL { directory.appendingPathComponent("xcrun") }

        init(_ body: String) throws {
            directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("#!/bin/sh\n\(body)\n".utf8).write(to: url)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        }

        func remove() { try? FileManager.default.removeItem(at: directory) }
    }
}
