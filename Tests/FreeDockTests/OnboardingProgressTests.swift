import Testing
@testable import FreeDock

@Suite("First-run onboarding")
struct OnboardingProgressTests {
    @Test("Progress advances, stops, and returns safely")
    func navigation() {
        var progress = OnboardingProgress()
        #expect(progress.step == .welcome)
        #expect(!progress.canGoBack)
        #expect(!progress.isLastStep)

        progress.goBack()
        #expect(progress.step == .welcome)
        progress.advance()
        #expect(progress.step == .organize)
        #expect(progress.canGoBack)
        progress.advance()
        #expect(progress.step == .integrate)
        #expect(progress.isLastStep)
        progress.advance()
        #expect(progress.step == .integrate)
        progress.goBack()
        #expect(progress.step == .organize)
    }

    @Test("Automatic onboarding appears only for unfinished fresh installs")
    func launchPolicy() {
        #expect(OnboardingLaunchPolicy.shouldPresent(
            loadedConfigurationFromDisk: false,
            hasCompletedOnboarding: false
        ))
        #expect(!OnboardingLaunchPolicy.shouldPresent(
            loadedConfigurationFromDisk: true,
            hasCompletedOnboarding: false
        ))
        #expect(!OnboardingLaunchPolicy.shouldPresent(
            loadedConfigurationFromDisk: false,
            hasCompletedOnboarding: true
        ))
    }
}
