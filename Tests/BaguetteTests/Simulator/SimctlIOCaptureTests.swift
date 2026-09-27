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
