import Foundation

/// Foldable simulators consume Device Hub pose events; other devices use Purple.
final class SimulatorOrientation: Orientation, @unchecked Sendable {
    private let isFoldable: () throws -> Bool
    private let motor: any HingeMotor
    private let standard: any Orientation

    init(isFoldable: @escaping () throws -> Bool, motor: any HingeMotor, standard: any Orientation) {
        self.isFoldable = isFoldable
        self.motor = motor
        self.standard = standard
    }

    func set(_ orientation: DeviceOrientation) -> OrientationDelivery {
        do {
            guard try isFoldable() else { return standard.set(orientation) }
            try motor.turn(to: orientation)
            return .delivered
        } catch HingeError.toolTimedOut {
            logErr("Orientation change unconfirmed: \(HingeError.toolTimedOut)")
            return .unconfirmed
        } catch {
            logErr("Orientation change failed: \(error)")
            return .rejected
        }
    }
}
