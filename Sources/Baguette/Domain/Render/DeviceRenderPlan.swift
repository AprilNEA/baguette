import Foundation

struct DeviceRotation: Equatable, Sendable, Codable {
    let x: Double
    let y: Double
    let z: Double

    static let zero = DeviceRotation(x: 0, y: 0, z: 0)
}

enum ScreenRotation: Int, CaseIterable, Sendable {
    case none = 0
    case quarter = 90
    case half = 180
    case threeQuarters = 270

    var swapsDimensions: Bool { self == .quarter || self == .threeQuarters }
}

enum DeviceScreenFit: String, Equatable, Sendable, Codable {
    case cover
    case contain
    case stretch
}

enum DeviceRenderBackground: Equatable, Sendable {
    case transparent
    case color(String)
}

struct DeviceRenderPlan: Equatable, Sendable {
    let model: InstalledDeviceModel
    let variants: [DeviceVariantSelection]
    let rotation: DeviceRotation
    let outputSize: RenderDimensions
    let fit: DeviceScreenFit
    let background: DeviceRenderBackground
    /// Composite a reflective cover-glass layer over the screen. Off by
    /// default so automation screenshots stay pixel-stable.
    let screenGlass: Bool
    let hingeDegrees: Double?
    let screenRotation: ScreenRotation

    var screenPanel: IntegratedPanel? {
        hingeDegrees.map { HingeAngle(degrees: $0).litPanel }
    }

    /// The glass layer is shaped for the inner screen and is left out when
    /// a pose lights the cover, where it would float beside the shut book.
    var rendersScreenGlass: Bool {
        screenGlass && screenPanel != .primary
    }

    static func build(
        model: InstalledDeviceModel,
        variants: [String: String],
        rotation: DeviceRotation,
        outputSize: RenderDimensions,
        fit: DeviceScreenFit = .cover,
        background: DeviceRenderBackground = .transparent,
        screenGlass: Bool = false,
        hingeDegrees: Double? = nil,
        screenRotation: ScreenRotation = .none
    ) throws -> DeviceRenderPlan {
        guard outputSize.width > 0, outputSize.height > 0 else {
            throw DeviceModelError.invalidOutputSize
        }
        guard rotation.x.isFinite, rotation.y.isFinite, rotation.z.isFinite else {
            throw DeviceModelError.invalidRotation
        }
        if let hingeDegrees {
            guard model.definition.scene.fold != nil else {
                throw DeviceModelError.modelCannotFold(model.definition.id.rawValue)
            }
            guard hingeDegrees.isFinite, (0...180).contains(hingeDegrees) else {
                throw DeviceModelError.invalidHingeAngle
            }
        }
        if case .color(let color) = background {
            let pattern = #"^#[0-9A-Fa-f]{6}$"#
            guard color.range(of: pattern, options: .regularExpression) != nil else {
                throw DeviceModelError.invalidBackground(color)
            }
        }
        return DeviceRenderPlan(
            model: model,
            variants: try model.definition.resolveVariants(variants),
            rotation: rotation,
            outputSize: outputSize,
            fit: fit,
            background: background,
            screenGlass: screenGlass,
            hingeDegrees: hingeDegrees,
            screenRotation: screenRotation
        )
    }
}
