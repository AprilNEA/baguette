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

    @Test(arguments: [["--hinge-degrees", "130"], ["--screen-orientation", "landscape-left"], ["--screen-orientation", "portrait"]])
    func `offline pose options reject live capture`(option: [String]) {
        #expect(throws: (any Error).self) {
            _ = try Render3DCommand.parse(["--udid", "device"] + option)
        }
    }

    @Test(arguments: ["portrait", "landscape-left", "landscape-right", "portrait-upside-down"])
    func `offline screenshots take the orientation they were captured in`(name: String) throws {
        let command = try Render3DCommand.parse([
            "--screen", "screen.png", "--device", "iphone-duo",
            "--screen-orientation", name, "--hinge-degrees", "130"
        ])
        #expect(command.screenOrientation == DeviceOrientation(wireName: name))
        #expect(command.hingeDegrees == 130)
    }

    @Test func `existing render arguments retain an unrotated unspecified pose`() throws {
        let command = try Render3DCommand.parse(["--screen", "screen.png", "--device", "iphone-duo"])
        #expect(command.screenOrientation == nil)
        #expect(command.hingeDegrees == nil)
    }

    /// The render plan rejects an angle off 0...180 with
    /// `DeviceModelError.invalidHingeAngle`; the command does not check it twice.
    @Test(arguments: ["181", "nan", "inf"])
    func `leaves the hinge range to the render plan`(value: String) throws {
        let command = try Render3DCommand.parse([
            "--screen", "screen.png", "--device", "iphone-duo", "--hinge-degrees", value
        ])
        #expect(command.hingeDegrees.map { !$0.isFinite || $0 > 180 } == true)
    }

    @Test(arguments: ["landscapeLeft", "90", "sideways"])
    func `rejects unknown screen orientations`(value: String) {
        #expect(throws: (any Error).self) {
            try Render3DCommand.parse([
                "--screen", "screen.png", "--device", "iphone-duo", "--screen-orientation", value
            ])
        }
    }
}
