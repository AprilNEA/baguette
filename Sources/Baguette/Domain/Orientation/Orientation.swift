import Foundation
import Mockable

/// Drive a booted simulator's orientation. Foldables use a guest pose event;
/// ordinary devices use the legacy GraphicsServices event. The foreground app
/// still chooses its interface orientation, which can differ from device pose.
@Mockable
protocol Orientation: Sendable {
    /// Returns whether dispatch succeeded, not whether the app rotated.
    /// Foldable dispatch waits for its helper to finish and reports helper
    /// failure; legacy dispatch reports whether the event port accepted it.
    func set(_ orientation: DeviceOrientation) -> Bool
}
