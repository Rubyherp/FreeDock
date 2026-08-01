import Foundation

enum OnboardingStep: Int, CaseIterable, Equatable, Sendable {
    case welcome
    case organize
    case integrate
}

struct OnboardingProgress: Equatable, Sendable {
    private(set) var step: OnboardingStep = .welcome

    var canGoBack: Bool { step.rawValue > 0 }
    var isLastStep: Bool { step == OnboardingStep.allCases.last }

    mutating func advance() {
        guard let next = OnboardingStep(rawValue: step.rawValue + 1) else {
            return
        }
        step = next
    }

    mutating func goBack() {
        guard let previous = OnboardingStep(rawValue: step.rawValue - 1) else {
            return
        }
        step = previous
    }
}

enum OnboardingLaunchPolicy {
    static func shouldPresent(
        loadedConfigurationFromDisk: Bool,
        hasCompletedOnboarding: Bool
    ) -> Bool {
        !loadedConfigurationFromDisk && !hasCompletedOnboarding
    }
}
