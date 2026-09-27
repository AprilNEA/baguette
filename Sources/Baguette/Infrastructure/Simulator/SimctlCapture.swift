import Foundation

/// Bounded synchronous simctl output, including process exit and pipe drain.
enum SimctlCapture {
    enum Failure: Error, Equatable, LocalizedError {
        case timedOut(udid: String, seconds: TimeInterval, processExited: Bool, output: String)
        case failed(udid: String, status: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .timedOut(let udid, let seconds, let processExited, let output):
                let phase = processExited ? "output EOF" : "process exit"
                return "Simulator query for \(udid) timed out after \(seconds)s waiting for \(phase): \(output)"
            case .failed(let udid, let status, let output):
                return "Simulator query for \(udid) exited with status \(status): \(output)"
            }
        }
    }

    static func enumerate(
        udid: String,
        deviceSetPath: String? = nil,
        xcrun: URL = URL(fileURLWithPath: "/usr/bin/xcrun"),
        timeout: TimeInterval = 5,
        process: Process = Process()
    ) throws -> String {
        try run(
            udid: udid,
            arguments: ["simctl"] + (deviceSetPath.map { ["--set", $0] } ?? []) + ["io", udid, "enumerate"],
            xcrun: xcrun, timeout: timeout, process: process
        )
    }

    static func run(
        udid: String,
        arguments: [String],
        xcrun: URL = URL(fileURLWithPath: "/usr/bin/xcrun"),
        timeout: TimeInterval = 5,
        process: Process = Process()
    ) throws -> String {
        process.executableURL = xcrun
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = FileHandle.nullDevice
        let output = CapturedOutput()
        let complete = DispatchGroup()
        complete.enter()
        complete.enter()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let bytes = handle.availableData
            if bytes.isEmpty {
                handle.readabilityHandler = nil
                complete.leave()
            } else {
                output.append(bytes)
            }
        }
        process.terminationHandler = { _ in
            complete.leave()
        }
        defer {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
        }
        try process.run()
        guard complete.wait(timeout: .now() + timeout) == .success else {
            // A stalled simctl can ignore SIGTERM. Request termination, then bound the exit wait.
            let processExited = !process.isRunning
            if !processExited { Darwin.kill(process.processIdentifier, SIGKILL) }
            _ = complete.wait(timeout: .now() + 1)
            throw Failure.timedOut(
                udid: udid, seconds: timeout, processExited: processExited, output: output.text
            )
        }
        let text = output.text
        guard process.terminationStatus == 0 else {
            throw Failure.failed(udid: udid, status: process.terminationStatus, output: text)
        }
        return text
    }

    // Every access to the mutable bytes is protected by the lock.
    private final class CapturedOutput: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()

        func append(_ data: Data) { lock.withLock { bytes.append(data) } }
        var text: String { lock.withLock { String(decoding: bytes, as: UTF8.self) } }
    }
}
