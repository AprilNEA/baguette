import Foundation
import Synchronization
import Testing

@testable import Baguette

@Suite("IndigoHIDMessageTests", .serialized)
struct IndigoHIDMessageTests {
    @Test(arguments: [false, true])
    func `waits for asynchronous transport completion and reports its result`(fails: Bool) throws {
        let client = DeferredHIDClient()
        let returned = DispatchSemaphore(value: 0)
        let result = Mutex<Bool?>(nil)
        DispatchQueue.global().async {
            defer { returned.signal() }
            do {
                let message = try #require(malloc(8))
                let ok = IndigoHIDMessage.send(message, to: client)
                result.withLock { $0 = ok }
            } catch {
                Issue.record(error)
            }
        }
        defer { client.complete(error: nil) }
        try #require(client.received.wait(timeout: .now() + 1) == .success)
        #expect(returned.wait(timeout: .now() + 0.05) == .timedOut)
        client.complete(error: fails ? Self.error : nil)
        try #require(returned.wait(timeout: .now() + 1) == .success)
        #expect(result.withLock { $0 } == !fails)
    }

    @Test @MainActor
    func `transport completion does not need the waiting main actor`() throws {
        let client = DeferredHIDClient(automaticResults: [nil])
        let message = try #require(malloc(8))
        #expect(IndigoHIDMessage.send(message, to: client))
        #expect(client.sentCount == 1)
    }

    @Test func `rejects a client without the send selector`() throws {
        let message = try #require(malloc(8))
        #expect(!IndigoHIDMessage.send(message, to: NSObject()))
    }

    @Test func `timeout leaves framework ownership intact and accepts a late completion`() throws {
        let client = DeferredHIDClient()
        let message = try #require(malloc(8))
        #expect(!IndigoHIDMessage.send(message, to: client, deadline: .now()))
        #expect(client.received.wait(timeout: .now()) == .success)
        client.complete(error: nil)
        #expect(client.completed.wait(timeout: .now() + 1) == .success)
        #expect(client.sentCount == 1)
    }

    @Test func `digitizer dispatch reports a transport failure`() {
        let client = DeferredHIDClient(automaticResults: [Self.error])
        let ok = IOHIDDigitizerDispatch.send(
            point: CGPoint(x: 0.25, y: 0.5), identifier: 1, phase: .up, edge: .none,
            target: IndigoHIDTouchTarget.phone, on: client
        )
        #expect(client.sentCount == 1)
        #expect(!ok)
    }

    @Test(arguments: [false, true])
    func `tap attempts release and fails when either transport completion fails`(downFails: Bool) {
        let client = DeferredHIDClient(automaticResults: downFails ? [Self.error, nil] : [nil, Self.error])
        let ok = IOHIDDigitizerDispatch.tap(
            point: CGPoint(x: 0.25, y: 0.5), holdSeconds: 0.02, edge: .none,
            identifier: 1, target: IndigoHIDTouchTarget.phone, on: client
        )
        #expect(client.sentCount == 2)
        #expect(!ok)
    }

    @Test(arguments: [false, true])
    func `swipe stops movement after a transport failure and still attempts release`(failsDuringDwell: Bool) {
        // Two moves and three dwell pulses would normally make seven sends.
        let failedIndex = failsDuringDwell ? 3 : 1
        var completions = [NSError?](repeating: nil, count: 7)
        completions[failedIndex] = Self.error
        let client = DeferredHIDClient(automaticResults: completions)
        let ok = IOHIDDigitizerDispatch.swipe(
            from: CGPoint(x: 0.25, y: 0.5), to: CGPoint(x: 0.5, y: 0.25),
            steps: 2, stepMs: 0, dwellMs: 150,
            identifier: 1, target: IndigoHIDTouchTarget.phone, on: client
        )
        #expect(!ok)
        #expect(client.sentCount == failedIndex + 2)
    }

    private static var error: NSError { NSError(domain: "HID transport", code: 17) }
}

/// Implements the real Objective-C selector; the test releases completion
/// independently from method return, as SimulatorKit's send queue does.
/// Mutable state is locked; completions run only on the supplied queue.
private final class DeferredHIDClient: NSObject, @unchecked Sendable {
    let received = DispatchSemaphore(value: 0)
    let completed = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var pending: Pending?
    private var count = 0
    private let automaticResults: [NSError?]?

    init(automaticResults: [NSError?]? = nil) {
        self.automaticResults = automaticResults
    }

    var sentCount: Int { lock.withLock { count } }

    @objc(sendWithMessage:freeWhenDone:completionQueue:completion:)
    func send(
        message: UnsafeMutableRawPointer, freeWhenDone: Bool,
        completionQueue: DispatchQueue?,
        completion: (@convention(block) (NSError?) -> Void)?
    ) {
        #expect(freeWhenDone)
        #expect(completionQueue != nil)
        #expect(completion != nil)
        let index = lock.withLock {
            pending = Pending(message: message, queue: completionQueue, completion: completion)
            count += 1
            return count - 1
        }
        received.signal()
        if let automaticResults { complete(error: automaticResults[index]) }
    }

    func complete(error: NSError?) {
        let delivery = lock.withLock {
            let delivery = pending
            pending = nil
            return delivery
        }
        guard let delivery else { return }
        free(delivery.message)
        // The old adapter supplies neither callback argument.
        guard let queue = delivery.queue else { return }
        queue.async {
            delivery.completion?(error)
            self.completed.signal()
        }
    }

    // Immutable envelope; the message is freed once before queue delivery.
    private final class Pending: @unchecked Sendable {
        let message: UnsafeMutableRawPointer
        let queue: DispatchQueue?
        let completion: (@convention(block) (NSError?) -> Void)?

        init(
            message: UnsafeMutableRawPointer, queue: DispatchQueue?,
            completion: (@convention(block) (NSError?) -> Void)?
        ) {
            self.message = message
            self.queue = queue
            self.completion = completion
        }
    }
}
