import Foundation
import Mockable
import Testing
@testable import Baguette

@Suite("SimulatorOrientation")
struct SimulatorOrientationTests {
    @Test(arguments: DeviceOrientation.allCases)
    func `foldable rotation uses the device hinge channel`(_ target: DeviceOrientation) {
        let motor = MockHingeMotor()
        given(motor).turn(to: .value(target)).willReturn()
        let orientation = SimulatorOrientation(
            isFoldable: { true }, motor: motor, standard: MockOrientation()
        )
        #expect(orientation.set(target))
    }

    @Test func `ordinary devices retain the legacy orientation result`() {
        let standard = MockOrientation()
        given(standard).set(.value(.landscapeLeft)).willReturn(true)
        given(standard).set(.value(.portrait)).willReturn(false)
        let orientation = SimulatorOrientation(
            isFoldable: { false }, motor: MockHingeMotor(), standard: standard
        )
        #expect(orientation.set(.landscapeLeft))
        #expect(!orientation.set(.portrait))
    }

    @Test func `failed foldable dispatch is not replaced by a misleading legacy success`() {
        let motor = MockHingeMotor()
        given(motor).turn(to: .any).willThrow(HingeError.toolMissing)
        let orientation = SimulatorOrientation(
            isFoldable: { true }, motor: motor, standard: MockOrientation()
        )
        #expect(!orientation.set(.portrait))
    }
}
