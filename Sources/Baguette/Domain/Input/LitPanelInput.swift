import Foundation

/// A foldable's input across folds: each gesture goes to the panel the
/// hinge lights. iPhone Duo's page keeps one socket while the hinge
/// moves (the book draws both panels), so an input bound once would
/// keep addressing a panel that has gone dark.
struct LitPanelInput: Input {
    let cover: any Input
    let unfolded: any Input
    let litPanel: @Sendable () -> IntegratedPanel

    private var lit: any Input { litPanel() == .primary ? cover : unfolded }

    func tap(at point: Point, size: Size, duration: Double, edge: DeviceEdge?) -> Bool {
        lit.tap(at: point, size: size, duration: duration, edge: edge)
    }

    func swipe(from start: Point, to end: Point, size: Size, duration: Double) -> Bool {
        lit.swipe(from: start, to: end, size: size, duration: duration)
    }

    func touch1(phase: GesturePhase, at point: Point, size: Size, edge: DeviceEdge?) -> Bool {
        lit.touch1(phase: phase, at: point, size: size, edge: edge)
    }

    func touch2(phase: GesturePhase, first: Point, second: Point, size: Size) -> Bool {
        lit.touch2(phase: phase, first: first, second: second, size: size)
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
