import Foundation

/// Foldable simulators consume Device Hub pose events; other devices use Purple.
final class SimulatorOrientation: Orientation, @unchecked Sendable {
    private let isFoldable: () -> Bool
    private let motor: any HingeMotor
    private let standard: any Orientation

    init(isFoldable: @escaping () -> Bool, motor: any HingeMotor, standard: any Orientation) {
        self.isFoldable = isFoldable
        self.motor = motor
        self.standard = standard
    }

    func set(_ orientation: DeviceOrientation) -> Bool {
        guard isFoldable() else { return standard.set(orientation) }
        do {
            try motor.turn(to: orientation)
            return true
        } catch {
            return false
        }
    }
}
