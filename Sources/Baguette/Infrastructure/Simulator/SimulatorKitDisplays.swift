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
        case outputReadFailed(udid: String, code: Int32)

        var errorDescription: String? {
            switch self {
            case .timedOut(let udid, let seconds):
                return "Display enumeration for \(udid) timed out after \(seconds)s."
            case .failed(let udid, let status, let output):
                return "Display enumeration for \(udid) exited with status \(status): \(output)"
            case .outputReadFailed(let udid, let code):
                return "Display enumeration for \(udid) could not read output (errno \(code))."
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
        let queue = DispatchQueue(label: "baguette.display-enumeration")
        let handle = pipe.fileHandleForReading
        let reader = DispatchIO(type: .stream, fileDescriptor: handle.fileDescriptor, queue: queue) { _ in
            // Dispatch relinquishes the descriptor only after its pending reads have stopped.
            try? handle.close()
        }
        defer { reader.close(flags: .stop) }
        complete.enter()
        process.terminationHandler = { _ in
            exited.signal()
            complete.leave()
        }
        do {
            try process.run()
        } catch {
            complete.leave()
            throw error
        }
        complete.enter()
        reader.read(offset: 0, length: Int.max, queue: queue) { done, data, error in
            output.append(data, error: error)
            if done {
                if error != 0, process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
                complete.leave()
            }
        }
        guard complete.wait(timeout: .now() + timeout) == .success else {
            // A stalled simctl can ignore SIGTERM. Request termination, then bound the exit wait.
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            _ = exited.wait(timeout: .now() + 1)
            throw Failure.timedOut(udid: udid, seconds: timeout)
        }
        let (text, error) = output.result
        guard error == 0 else { throw Failure.outputReadFailed(udid: udid, code: error) }
        guard process.terminationStatus == 0 else {
            throw Failure.failed(udid: udid, status: process.terminationStatus, output: text)
        }
        return text
    }

    // The read callback and caller share bytes and error state under the same lock.
    private final class CapturedOutput: @unchecked Sendable {
        private let lock = NSLock()
        private var bytes = Data()
        private var readError: Int32 = 0

        func append(_ data: DispatchData?, error: Int32) {
            lock.withLock {
                if let data { bytes.append(contentsOf: data) }
                if error != 0 { readError = error }
            }
        }

        var result: (text: String, error: Int32) {
            lock.withLock { (String(decoding: bytes, as: UTF8.self), readError) }
        }
    }
}
