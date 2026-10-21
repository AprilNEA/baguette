import Testing
import Foundation
import Mockable
@testable import Baguette

/// iPhone Duo's page keeps one socket across a fold: the book draws both
/// panels, so nothing reconnects when the hinge lights the other one.
/// Its input follows the lit panel gesture by gesture.
@Suite("LitPanelInput")
struct LitPanelInputTests {

    final class Hinge: @unchecked Sendable {
        var lit: IntegratedPanel = .primary
    }

    private func make() -> (LitPanelInput, cover: MockInput, unfolded: MockInput, Hinge) {
        let cover = MockInput()
        let unfolded = MockInput()
        for panel in [cover, unfolded] {
            given(panel).tap(at: .any, size: .any, duration: .any, edge: .any).willReturn(true)
            given(panel).key(.any, modifiers: .any, duration: .any).willReturn(true)
        }
        let hinge = Hinge()
        let input = LitPanelInput(cover: cover, unfolded: unfolded, litPanel: { hinge.lit })
        return (input, cover, unfolded, hinge)
    }

    private let size = Size(width: 466, height: 678)
    private let point = Point(x: 100, y: 200)

    @Test func `should land a tap on the cover when the device is folded`() {
        let (input, cover, unfolded, _) = make()
        #expect(input.tap(at: point, size: size, duration: 0.05, edge: nil))
        verify(cover).tap(at: .any, size: .any, duration: .any, edge: .any).called(1)
        verify(unfolded).tap(at: .any, size: .any, duration: .any, edge: .any).called(0)
    }

    @Test func `should land a tap on the unfolded panel when the device is unfolded`() {
        let (input, cover, unfolded, hinge) = make()
        hinge.lit = .secondary
        #expect(input.tap(at: point, size: size, duration: 0.05, edge: nil))
        verify(unfolded).tap(at: .any, size: .any, duration: .any, edge: .any).called(1)
        verify(cover).tap(at: .any, size: .any, duration: .any, edge: .any).called(0)
    }

    @Test func `should type into the cover when the device folds between keystrokes`() {
        let (input, cover, unfolded, hinge) = make()
        let a = KeyboardKey.from(wireCode: "KeyA")!
        hinge.lit = .secondary
        #expect(input.key(a, modifiers: [], duration: 0))
        hinge.lit = .primary
        #expect(input.key(a, modifiers: [], duration: 0))
        verify(unfolded).key(.any, modifiers: .any, duration: .any).called(1)
        verify(cover).key(.any, modifiers: .any, duration: .any).called(1)
    }
}
