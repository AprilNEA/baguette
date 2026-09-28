import Foundation
import Mockable

/// Drive a booted simulator's orientation. Foldables use a guest pose event;
/// ordinary devices use the legacy GraphicsServices event. The foreground app
/// still chooses its interface orientation, which can differ from device pose.
@Mockable
protocol Orientation: Sendable {
    /// Reports dispatch, not whether the app rotated. Foldable dispatch
    /// waits for its helper's answer; legacy dispatch reports whether the
    /// event port accepted the event.
    func set(_ orientation: DeviceOrientation) -> OrientationDelivery
}

/// What an orientation dispatch established.
enum OrientationDelivery: Equatable, Sendable {
    case delivered
    case rejected
    /// The helper stopped answering and was stopped: the change may have
    /// been delivered before its deadline, but will not be delivered later.
    case unconfirmed
}
