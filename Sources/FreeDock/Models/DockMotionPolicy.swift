import Foundation

enum DockMotionPolicy {
    static func shouldAnimate(reduceMotion: Bool) -> Bool {
        !reduceMotion
    }

    static func duration(
        _ standardDuration: TimeInterval,
        reduceMotion: Bool
    ) -> TimeInterval {
        reduceMotion ? 0 : standardDuration
    }
}
