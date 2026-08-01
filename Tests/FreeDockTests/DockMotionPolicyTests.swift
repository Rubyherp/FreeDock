import Testing

@testable import FreeDock

@Suite("Dock motion policy")
struct DockMotionPolicyTests {
    @Test("Standard motion retains animation timing")
    func standardMotion() {
        #expect(DockMotionPolicy.shouldAnimate(reduceMotion: false))
        #expect(
            DockMotionPolicy.duration(
                0.24,
                reduceMotion: false
            ) == 0.24
        )
    }

    @Test("Reduced motion removes animation timing")
    func reducedMotion() {
        #expect(!DockMotionPolicy.shouldAnimate(reduceMotion: true))
        #expect(
            DockMotionPolicy.duration(
                0.24,
                reduceMotion: true
            ) == 0
        )
    }
}
