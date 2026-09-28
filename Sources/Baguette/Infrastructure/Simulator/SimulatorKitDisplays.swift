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
        let output = CapturedOutput(pipe.fileHandleForReading)
        defer { output.close() }
        let exited = DispatchSemaphore(value: 0)
        let complete = DispatchGroup()
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
        // A readability source, unlike DispatchIO, needs no free global-queue worker to
        // make progress, so a host with every worker blocked still drains the pipe.
        pipe.fileHandleForReading.readabilityHandler = { _ in
            switch output.drain() {
            case .more: return
            case .failed: if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
            case .end: break
            }
            if output.close() { complete.leave() }
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

    /// Owns the read end of the pipe. Reads and the close share one lock, so a
    /// readability callback still in flight never reads a closed (or reused) descriptor.
    private final class CapturedOutput: @unchecked Sendable {
        enum Chunk { case more, end, failed }

        private let handle: FileHandle
        private let lock = NSLock()
        private var bytes = Data()
        private var readError: Int32 = 0
        private var closed = false

        init(_ handle: FileHandle) { self.handle = handle }

        func drain() -> Chunk {
            lock.withLock {
                guard !closed else { return .end }
                var buffer = [UInt8](repeating: 0, count: 65536)
                while true {
                    let count = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
                    if count > 0 {
                        bytes.append(contentsOf: buffer[..<count])
                        return .more
                    }
                    if count == 0 { return .end }
                    if errno == EINTR { continue }
                    if errno == EAGAIN { return .more }
                    readError = errno
                    return .failed
                }
            }
        }

        /// Stops the readability source, then closes the descriptor. Returns `true` only
        /// for the call that actually closed it.
        @discardableResult
        func close() -> Bool {
            handle.readabilityHandler = nil
            return lock.withLock {
                guard !closed else { return false }
                closed = true
                try? handle.close()
                return true
            }
        }

        var result: (text: String, error: Int32) {
            lock.withLock { (String(decoding: bytes, as: UTF8.self), readError) }
        }
    }
}
