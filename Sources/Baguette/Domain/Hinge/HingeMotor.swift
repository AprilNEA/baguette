import Foundation
import Mockable

/// What moves a foldable's hinge — and turns the device — the way Device
/// Hub's pose picker and rotate button do. The production impl is
/// `GuestHingeMotor`, which runs `HingeControl` inside the guest.
@Mockable
protocol HingeMotor: Sendable {
    /// Sweep the hinge from one angle to another over `duration` seconds,
    /// at 60 Hz with an ease-out, as Device Hub's picker plays a pose
    /// change. Returns when the sweep has been delivered.
    func fold(from: Double, to: Double, over duration: TimeInterval) throws

    /// Turn the device to a physical orientation through the same
    /// channel Device Hub's rotate button uses.
    func turn(to orientation: DeviceOrientation) throws
}

enum HingeError: Error, Equatable, CustomStringConvertible, LocalizedError {
    /// The build did not ship `HingeControl`, or it could not be installed.
    case toolMissing
    case toolFailed(status: Int32)
    case toolTimedOut
}

extension HingeError {
    var description: String {
        switch self {
        case .toolMissing: "HingeControl is missing or could not be installed."
        case .toolFailed(let status): "HingeControl exited with status \(status)."
        case .toolTimedOut: "HingeControl timed out; the command may already have been dispatched and its outcome is unknown."
        }
    }

    var errorDescription: String? { description }
}
