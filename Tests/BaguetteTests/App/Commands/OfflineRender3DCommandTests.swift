import ArgumentParser
import Testing
@testable import Baguette

@Suite("OfflineRender3DCommand")
struct OfflineRender3DCommandTests {
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
