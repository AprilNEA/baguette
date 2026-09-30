import ArgumentParser
import Foundation
import Testing
@testable import Baguette

@Suite("DeviceRenderPlan")
struct DeviceRenderPlanTests {

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

    @Test(arguments: [(0.0, IntegratedPanel.primary), (89.0, .primary), (90.0, .secondary), (130.0, .secondary), (180.0, .secondary)])
    func `saved fold poses select the corresponding screen`(angle: Double, panel: IntegratedPanel) throws {
        let plan = try Self.foldPlan(angle: angle)
        #expect(plan.screenPanel == panel)
        #expect(plan.hingeDegrees == angle)
        #expect(plan.screenRotation == .quarter)
    }

    @Test(arguments: [-1.0, 181.0, Double.infinity, Double.nan])
    func `render plans reject invalid fold angles`(angle: Double) {
        #expect(throws: DeviceModelError.invalidHingeAngle) {
            _ = try Self.foldPlan(angle: angle)
        }
    }

    /// The glass layer is shaped for the inner screen; over a pose that
    /// lights the cover it floated beside the shut book.
    @Test(arguments: [(nil as Double?, true), (180, true), (90, true), (89, false), (0, false)])
    func `screen glass composites over the inner screen only`(angle: Double?, glass: Bool) throws {
        let plan = try DeviceRenderPlan.build(
            model: Self.installed(fold: DeviceModelFold(
                clip: "fold", shutTime: 5, coverMaterial: "Cover",
                coverTextureSize: RenderDimensions(width: 100, height: 200), openPoseDegrees: 130
            )),
            variants: [:], rotation: .zero, outputSize: RenderDimensions(width: 300, height: 400),
            screenGlass: true, hingeDegrees: angle
        )
        #expect(plan.rendersScreenGlass == glass)
    }

    @Test func `an unspecified fold keeps the existing screen selection`() throws {
        #expect(try Self.foldPlan(angle: nil).screenPanel == nil)
    }

    private static func foldPlan(angle: Double?) throws -> DeviceRenderPlan {
        try DeviceRenderPlan.build(
            model: installed(fold: DeviceModelFold(
                clip: "fold", shutTime: 5, coverMaterial: "Cover",
                coverTextureSize: RenderDimensions(width: 100, height: 200), openPoseDegrees: 130
            )),
            variants: [:], rotation: .zero, outputSize: RenderDimensions(width: 300, height: 400),
            hingeDegrees: angle, screenRotation: .quarter
        )
    }

    @Test func `builds a render plan with mapped variants and requested camera`() throws {
        let model = Self.installed()

        let plan = try DeviceRenderPlan.build(
            model: model,
            variants: ["finish": "silver"],
            rotation: DeviceRotation(x: 18, y: -24, z: 0),
            outputSize: RenderDimensions(width: 1200, height: 900),
            fit: .contain,
            background: .color("#112233")
        )

        #expect(plan.model == model)
        #expect(plan.variants.map(\.usdValue) == ["Silver"])
        #expect(plan.rotation == DeviceRotation(x: 18, y: -24, z: 0))
        #expect(plan.outputSize == RenderDimensions(width: 1200, height: 900))
        #expect(plan.fit == .contain)
        #expect(plan.background == .color("#112233"))
    }

    @Test func `rejects non-positive output dimensions`() {
        #expect(throws: DeviceModelError.invalidOutputSize) {
            _ = try DeviceRenderPlan.build(
                model: Self.installed(),
                variants: [:],
                rotation: .zero,
                outputSize: RenderDimensions(width: 0, height: 900)
            )
        }
    }

    @Test func `rejects a non-finite camera rotation`() {
        #expect(throws: DeviceModelError.invalidRotation) {
            _ = try DeviceRenderPlan.build(
                model: Self.installed(),
                variants: [:],
                rotation: DeviceRotation(x: .infinity, y: 0, z: 0),
                outputSize: RenderDimensions(width: 1200, height: 900)
            )
        }
    }

    @Test func `rejects an invalid background color`() {
        #expect(throws: DeviceModelError.invalidBackground("blue")) {
            _ = try DeviceRenderPlan.build(
                model: Self.installed(),
                variants: [:],
                rotation: .zero,
                outputSize: RenderDimensions(width: 1200, height: 900),
                background: .color("blue")
            )
        }
    }
}

private extension DeviceRenderPlanTests {
    static func installed(fold: DeviceModelFold? = nil) -> InstalledDeviceModel {
        InstalledDeviceModel(
            definition: DeviceModelDefinition(
                schemaVersion: 1,
                id: "macbook",
                displayName: "MacBook",
                matches: DeviceModelMatches(),
                asset: DeviceModelAsset(file: "device.usdz", downloadURL: nil, sha256: nil),
                scene: DeviceModelScene(
                    rootNode: "Device",
                    screenNode: "Screen",
                    screenMaterial: "Screen",
                    nativeOrientation: .landscape,
                    textureSize: RenderDimensions(width: 3024, height: 1964),
                    usesScreenOverlay: false,
                    fold: fold
                ),
                variantSets: [
                    DeviceVariantSet(
                        id: "finish",
                        displayName: "Finish",
                        primPath: "/Device",
                        usdName: "Color",
                        default: "black",
                        choices: [
                            DeviceVariantChoice(
                                id: "black",
                                displayName: "Black",
                                usdValue: "Space_Black",
                                previewColor: nil
                            ),
                            DeviceVariantChoice(
                                id: "silver",
                                displayName: "Silver",
                                usdValue: "Silver",
                                previewColor: nil
                            )
                        ]
                    )
                ]
            ),
            directoryURL: URL(fileURLWithPath: "/models/macbook")
        )
    }
}

@Suite("ScreenQuadProjection attitude")
struct ScreenQuadProjectionAttitudeTests {
    @Test func `a quaternion pose projects identically to its euler twin`() {
        let corners = ScreenLocalCorners(
            topLeft: Vector3(x: -0.4, y: 0.9, z: 0.05),
            topRight: Vector3(x: 0.4, y: 0.9, z: 0.05),
            bottomRight: Vector3(x: 0.4, y: -0.9, z: 0.05),
            bottomLeft: Vector3(x: -0.4, y: -0.9, z: 0.05)
        )
        let half = 30.0 * Double.pi / 360
        let byEuler = ScreenQuadProjection.project(
            corners: corners, rotation: DeviceRotation(x: 0, y: 30, z: 0),
            distance: 5, fieldOfViewDegrees: 32, aspect: 1
        )
        let byAttitude = ScreenQuadProjection.project(
            corners: corners, attitude: Attitude(x: 0, y: sin(half), z: 0, w: cos(half)),
            distance: 5, fieldOfViewDegrees: 32, aspect: 1
        )
        for (a, b) in [(byEuler.topLeft, byAttitude.topLeft),
                       (byEuler.bottomRight, byAttitude.bottomRight)] {
            #expect(abs(a.u - b.u) < 0.0001)
            #expect(abs(a.v - b.v) < 0.0001)
        }
    }
}
