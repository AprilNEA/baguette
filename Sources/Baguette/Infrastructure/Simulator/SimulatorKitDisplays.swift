import Foundation

/// Production `Displays` — phone and CarPlay planes share one
/// enumerate probe so screen ids stay consistent across resolves.
final class SimulatorKitDisplays: Displays, @unchecked Sendable {
    let phone: any Display
    let carPlay: any Display
    private let udid: String
    private let host: any DeviceHost
    private let hinge: any Hinge
    private let keys: (any DeviceKeys)?
    private let enumerateIO: () throws -> String

    /// `keys` presses a foldable's hardware keys through the guest; a
    /// display with several panels routes buttons there.
    init(
        udid: String, host: any DeviceHost, hinge: any Hinge, keys: (any DeviceKeys)? = nil,
        deviceSetPath: String? = nil
    ) {
        let enumerateIO = { try SimctlIOCapture.enumerate(udid: udid, deviceSetPath: deviceSetPath) }
        self.udid = udid
        self.host = host
        self.hinge = hinge
        self.keys = keys
        self.enumerateIO = enumerateIO
        self.phone = SimulatorKitDisplay(
            kind: .phone,
            udid: udid,
            host: host,
            enumerateIO: enumerateIO,
            hinge: hinge,
            keys: keys
        )
        self.carPlay = SimulatorKitDisplay(
            kind: .carPlay,
            udid: udid,
            host: host,
            enumerateIO: enumerateIO,
            hinge: hinge
        )
    }

    func panel(_ panel: IntegratedPanel) -> any Display {
        SimulatorKitDisplay(
            kind: .phone,
            udid: udid,
            host: host,
            enumerateIO: enumerateIO,
            hinge: hinge,
            keys: keys,
            pinnedPanel: panel
        )
    }
}

/// Synchronous display enumeration with a deadline for both process exit and output drain.
enum SimctlIOCapture {
    enum Failure: Error, Equatable, LocalizedError {
        case timedOut(udid: String, seconds: TimeInterval)
        case failed(udid: String, status: Int32, output: String)

        var errorDescription: String? {
            switch self {
            case .timedOut(let udid, let seconds):
                return "Display enumeration for \(udid) timed out after \(seconds)s."
            case .failed(let udid, let status, let output):
                return "Display enumeration for \(udid) exited with status \(status): \(output)"
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
        process.executableURL = xcrun
        process.arguments =
            ["simctl"] + (deviceSetPath.map { ["--set", $0] } ?? [])
            + ["io", udid, "enumerate"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.environment = ProcessInfo.processInfo.environment
        process.standardInput = FileHandle.nullDevice
        let output = CapturedOutput()
        let exited = DispatchSemaphore(value: 0)
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
            exited.signal()
            complete.leave()
        }
        defer {
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
        }
        try process.run()
        guard complete.wait(timeout: .now() + timeout) == .success else {
            // A stalled simctl can ignore SIGTERM. Request termination, then bound the exit wait.
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            _ = exited.wait(timeout: .now() + 1)
            throw Failure.timedOut(udid: udid, seconds: timeout)
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
