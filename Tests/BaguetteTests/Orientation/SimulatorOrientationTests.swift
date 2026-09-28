import Foundation
import Mockable
import Testing
@testable import Baguette

@Suite("SimulatorOrientation")
struct SimulatorOrientationTests {
    @Test func `unknown panel configuration cannot fall back to a misleading success`() {
        let orientation = SimulatorOrientation(
            isFoldable: { throw HingeError.toolMissing },
            motor: MockHingeMotor(), standard: MockOrientation()
        )
        #expect(orientation.set(.portrait) == .rejected)
    }

    @Test(arguments: DeviceOrientation.allCases)
    func `foldable rotation uses the device hinge channel`(_ target: DeviceOrientation) {
        let motor = MockHingeMotor()
        given(motor).turn(to: .value(target)).willReturn()
        let orientation = SimulatorOrientation(
            isFoldable: { true }, motor: motor, standard: MockOrientation()
        )
        #expect(orientation.set(target) == .delivered)
    }

    @Test func `ordinary devices retain the legacy orientation result`() {
        let standard = MockOrientation()
        given(standard).set(.value(.landscapeLeft)).willReturn(.delivered)
        given(standard).set(.value(.portrait)).willReturn(.rejected)
        let orientation = SimulatorOrientation(
            isFoldable: { false }, motor: MockHingeMotor(), standard: standard
        )
        #expect(orientation.set(.landscapeLeft) == .delivered)
        #expect(orientation.set(.portrait) == .rejected)
    }

    @Test func `failed foldable dispatch is not replaced by a misleading legacy success`() {
        let motor = MockHingeMotor()
        given(motor).turn(to: .any).willThrow(HingeError.toolMissing)
        let orientation = SimulatorOrientation(
            isFoldable: { true }, motor: motor, standard: MockOrientation()
        )
        #expect(orientation.set(.portrait) == .rejected)
    }

    /// The helper was stopped after its deadline: the rotation may have
    /// landed, and will not land later. Neither success nor rejection.
    @Test func `a foldable helper timeout is unconfirmed rather than rejected`() {
        let motor = MockHingeMotor()
        given(motor).turn(to: .any).willThrow(HingeError.toolTimedOut)
        let orientation = SimulatorOrientation(
            isFoldable: { true }, motor: motor, standard: MockOrientation()
        )
        #expect(orientation.set(.landscapeLeft) == .unconfirmed)
    }
}
