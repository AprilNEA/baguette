import Foundation

/// A foldable's input across folds: each gesture goes to the panel the
/// hinge lights when it starts. iPhone Duo's page keeps one socket while
/// the hinge moves (the book draws both panels), so an input bound once
/// would keep addressing a panel that has gone dark.
///
/// A finger stays on the panel it touched down on until it lifts: a
/// `down` on one panel and an `up` on the other would leave the first
/// one holding a contact nobody releases.
final class LitPanelInput: Input, @unchecked Sendable {
    private let cover: any Input
    private let unfolded: any Input
    private let litPanel: @Sendable () -> IntegratedPanel
    private let lock = NSLock()
    private var touching: IntegratedPanel?

    init(cover: any Input, unfolded: any Input, litPanel: @escaping @Sendable () -> IntegratedPanel) {
        self.cover = cover
        self.unfolded = unfolded
        self.litPanel = litPanel
    }

    private func panel(_ panel: IntegratedPanel) -> any Input {
        panel == .primary ? cover : unfolded
    }

    private var lit: any Input { panel(litPanel()) }

    /// The panel a contact's phase goes to: chosen on `down`, kept
    /// until `up`. A move with no contact down follows the hinge.
    private func contact(_ phase: GesturePhase) -> any Input {
        lock.lock()
        defer { lock.unlock() }
        let chosen: IntegratedPanel
        if phase == .down || touching == nil {
            chosen = litPanel()
            touching = chosen
        } else {
            chosen = touching ?? litPanel()
        }
        if phase == .up { touching = nil }
        return panel(chosen)
    }

    func tap(at point: Point, size: Size, duration: Double, edge: DeviceEdge?) -> Bool {
        lit.tap(at: point, size: size, duration: duration, edge: edge)
    }

    func swipe(from start: Point, to end: Point, size: Size, duration: Double) -> Bool {
        lit.swipe(from: start, to: end, size: size, duration: duration)
    }

    func touch1(phase: GesturePhase, at point: Point, size: Size, edge: DeviceEdge?) -> Bool {
        contact(phase).touch1(phase: phase, at: point, size: size, edge: edge)
    }

    func touch2(phase: GesturePhase, first: Point, second: Point, size: Size) -> Bool {
        contact(phase).touch2(phase: phase, first: first, second: second, size: size)
    }

    func button(_ button: DeviceButton, duration: Double) -> Bool {
        lit.button(button, duration: duration)
    }

    func key(_ key: KeyboardKey, modifiers: Set<KeyModifier>, duration: Double) -> Bool {
        lit.key(key, modifiers: modifiers, duration: duration)
    }

    func scroll(deltaX: Double, deltaY: Double) -> Bool {
        lit.scroll(deltaX: deltaX, deltaY: deltaY)
    }

    func twoFingerPath(
        start1: Point, end1: Point, start2: Point, end2: Point, size: Size, duration: Double
    ) -> Bool {
        lit.twoFingerPath(
            start1: start1, end1: end1, start2: start2, end2: end2, size: size, duration: duration)
    }
}
