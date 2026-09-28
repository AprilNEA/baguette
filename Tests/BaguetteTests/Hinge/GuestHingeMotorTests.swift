import Testing
import Foundation
import Mockable
@testable import Baguette

/// The hinge is moved from inside the guest: `HingeControl serve`, spawned
/// once with `simctl spawn` and kept, registers a HID service shaped like
/// dtuhidd's and plays every sweep it is written on stdin — so a pose
/// change costs no spawn. The motor's job is that child: start it on the
/// first sweep, write each sweep to it, start it again if it went away.
@Suite("GuestHingeMotor")
struct GuestHingeMotorTests {

    final class Captures: @unchecked Sendable {
        var runs: [[String]] = []
        var killed = false
        var executable: URL?
        var written: [String] = []
        var settled: [TimeInterval] = []
        var onExit: (@Sendable (Int32) -> Void)?
    }

    private func make(deviceSetPath: String? = nil, tool: String? = "/tmp/builds/abc/HingeControl", spawnFails: Bool = false, exitStatus: Int32? = 0, diagnostic: String? = nil)
        -> (GuestHingeMotor, Captures) {
        let sub = MockSubprocess()
        let captures = Captures()
        given(sub).runInteractive(executable: .any, arguments: .any, onBytes: .any, onExit: .any)
            .willProduce { exe, args, _, onExit in
                if spawnFails { throw HingeError.toolFailed(status: 1) }
                captures.executable = exe
                captures.runs.append(args)
                captures.onExit = onExit
            }
        given(sub).run(executable: .any, arguments: .any, onBytes: .any, onExit: .any)
            .willProduce { exe, args, onBytes, onExit in
                if spawnFails { throw HingeError.toolFailed(status: 1) }
                captures.executable = exe
                captures.runs.append(args)
                if let diagnostic { onBytes(Data(diagnostic.utf8)) }
                if let exitStatus { onExit(exitStatus) }
            }
        given(sub).kill().willProduce { captures.killed = true }
        given(sub).write(.any).willProduce { data in
            captures.written.append(String(decoding: data, as: UTF8.self))
        }
        given(sub).terminate().willReturn()
        let motor = GuestHingeMotor(
            udid: "duo", deviceSetPath: deviceSetPath, subprocess: { sub }, tool: { tool }, settle: { captures.settled.append($0) }, turnTimeout: 0.05)
        return (motor, captures)
    }

    @Test func `the first sweep starts the guest tool serving; later ones are written to it`() throws {
        let (motor, captures) = make()
        try motor.fold(from: 130, to: 0, over: 0.8)
        try motor.fold(from: 0, to: 180, over: 0.5)
        #expect(captures.executable?.path == "/usr/bin/xcrun")
        #expect(captures.runs == [["simctl", "spawn", "duo", "/tmp/builds/abc/HingeControl", "serve"]])
        #expect(captures.written == ["sweep 130 0 800\n", "sweep 0 180 500\n"])
    }

    @Test func `custom device sets scope both rotation and persistent helper launches`() throws {
        let (motor, captures) = make(deviceSetPath: "/tmp/custom devices")
        try motor.turn(to: .portrait)
        try motor.fold(from: 0, to: 130, over: 0.5)
        #expect(captures.runs == [
            ["simctl", "--set", "/tmp/custom devices", "spawn", "duo", "/tmp/builds/abc/HingeControl", "orientation", "portrait"],
            ["simctl", "--set", "/tmp/custom devices", "spawn", "duo", "/tmp/builds/abc/HingeControl", "serve"],
        ])
    }

    @Test func `shared motors are isolated by device set and device identifier`() {
        let udid = UUID().uuidString
        let a = GuestHingeMotor.forDevice(udid, deviceSetPath: "/sets/a")
        #expect(a === GuestHingeMotor.forDevice(udid, deviceSetPath: "/sets/a"))
        #expect(a !== GuestHingeMotor.forDevice(udid, deviceSetPath: "/sets/b"))
        #expect(a !== GuestHingeMotor.forDevice(udid))
        #expect(a !== GuestHingeMotor.forDevice(UUID().uuidString, deviceSetPath: "/sets/a"))
    }

    @Test func `a hardware key is pressed as Device Hub presses it, for as long as asked`() throws {
        let (motor, captures) = make()
        try motor.press(HIDUsage(page: 12, usage: 233), hold: 0.25)
        try motor.press(HIDUsage(page: 0xFF00, usage: 0x66), hold: 1.5)
        #expect(captures.written == ["button 12 233 250\n", "button 65280 102 1500\n"])
        // The call outlives the hold, so a one-shot CLI press is not cut
        // off with the key down. (The first wait is the tool's start.)
        #expect(captures.settled == [0.15, 0.3, 1.55])
    }

    @Test(arguments: [
        (DeviceOrientation.portrait, "portrait"),
        (.portraitUpsideDown, "pud"),
        (.landscapeLeft, "landscape-right"),
        (.landscapeRight, "landscape-left"),
    ])
    func `rotation uses the native physical orientation values and completes the guest command`(
        orientation: DeviceOrientation, native: String
    ) throws {
        let (motor, captures) = make()
        try motor.turn(to: orientation)
        #expect(captures.runs == [["simctl", "spawn", "duo", "/tmp/builds/abc/HingeControl", "orientation", native]])
        #expect(captures.written.isEmpty)
        // Measured UIDevice values for the native guest commands. The phone
        // backend sends DeviceOrientation.rawValue directly through Purple.
        let physicalValues: [String: UInt32] = [
            "portrait": 1, "pud": 2, "landscape-left": 3, "landscape-right": 4,
        ]
        #expect(physicalValues[native] == orientation.rawValue)
    }

    @Test func `a rejected rotation or missing helper is not success`() {
        let (failed, _) = make(exitStatus: 7)
        #expect(throws: HingeError.toolFailed(status: 7)) { try failed.turn(to: .portrait) }
        let (missing, _) = make(tool: nil)
        #expect(throws: HingeError.toolMissing) { try missing.turn(to: .portrait) }
    }

    @Test func `successful rotation tolerates benign helper output`() throws {
        let (motor, _) = make(diagnostic: "runtime warning\n")
        try motor.turn(to: .landscapeLeft)
    }

    @Test func `a timeout warns that the device may already have moved`() {
        #expect(String(describing: HingeError.toolTimedOut)
            == "HingeControl timed out; the command may already have been dispatched and its outcome is unknown.")
    }

    @Test func `a rotation that never completes is bounded and its child is killed`() {
        let (motor, captures) = make(exitStatus: nil)
        #expect(throws: HingeError.toolTimedOut) { try motor.turn(to: .portrait) }
        #expect(captures.killed)
    }

    @Test func `a tool that went away is started again for the next sweep`() throws {
        let (motor, captures) = make()
        try motor.fold(from: 0, to: 130, over: 0.8)
        captures.onExit?(0)
        try motor.fold(from: 130, to: 0, over: 0.8)
        #expect(captures.runs.count == 2)
    }

    @Test func `a missing tool or a failing spawn is an error`() {
        let (missing, _) = make(tool: nil)
        #expect(throws: HingeError.toolMissing) { try missing.fold(from: 0, to: 130, over: 0.5) }
        let (failing, _) = make(spawnFails: true)
        #expect(throws: HingeError.toolFailed(status: 1)) { try failing.fold(from: 0, to: 130, over: 0.5) }
    }
}
