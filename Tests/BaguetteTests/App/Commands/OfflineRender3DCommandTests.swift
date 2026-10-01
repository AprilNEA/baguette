import ArgumentParser
import Testing
@testable import Baguette

@Suite("OfflineRender3DCommand")
struct OfflineRender3DCommandTests {
    @Test func `fold option errors explain the unsupported request`() {
        #expect(Render3DCommand.message(for: DeviceModelError.modelCannotFold("iphone-17"))
            == "Model 'iphone-17' cannot fold; omit --hinge-degrees or choose a foldable model.")
        #expect(Render3DCommand.message(for: DeviceModelError.invalidHingeAngle)
            == "The hinge angle must be finite and between 0 and 180 degrees.")
    }

    @Test func `an unreadable screen image says so instead of naming the error case`() {
        #expect(Render3DCommand.message(for: DeviceModelError.screenImageInvalid)
            == "The screen image is not a readable PNG or JPEG.")
    }

    @Test(arguments: [["--hinge-degrees", "130"], ["--screen-rotation", "90"], ["--screen-rotation", "0"]])
    func `offline pose options reject live capture`(option: [String]) {
        #expect(throws: (any Error).self) {
            _ = try Render3DCommand.parse(["--udid", "device"] + option)
        }
    }

    @Test(arguments: [0, 90, 180, 270])
    func `offline screenshots accept quarter-turn orientation`(degrees: Int) throws {
        let command = try Render3DCommand.parse([
            "--screen", "screen.png", "--device", "iphone-duo",
            "--screen-rotation", String(degrees), "--hinge-degrees", "130"
        ])
        #expect(command.screenRotation?.rawValue == degrees)
        #expect(command.hingeDegrees == 130)
    }

    @Test func `existing render arguments retain an unrotated unspecified pose`() throws {
        let command = try Render3DCommand.parse(["--screen", "screen.png", "--device", "iphone-duo"])
        #expect(command.screenRotation == nil)
        #expect(command.hingeDegrees == nil)
    }

    @Test(arguments: ["-1", "181", "nan", "inf"])
    func `rejects invalid hinge angles`(value: String) {
        #expect(throws: (any Error).self) {
            try Render3DCommand.parse([
                "--screen", "screen.png", "--device", "iphone-duo", "--hinge-degrees", value
            ])
        }
    }

    @Test(arguments: ["45", "-90", "360"])
    func `rejects unsupported screen rotations`(value: String) {
        #expect(throws: (any Error).self) {
            try Render3DCommand.parse([
                "--screen", "screen.png", "--device", "iphone-duo", "--screen-rotation", value
            ])
        }
    }
}
