import Foundation
import OSLog

struct PerformanceTraceInterval {
    fileprivate let name: StaticString
    fileprivate let identifier: OSSignpostID
}

enum PerformanceTrace {
    private static let log = OSLog(
        subsystem: "com.freedock.app",
        category: .pointsOfInterest
    )

    static func begin(_ name: StaticString) -> PerformanceTraceInterval {
        let identifier = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: identifier)
        return PerformanceTraceInterval(
            name: name,
            identifier: identifier
        )
    }

    static func end(_ interval: PerformanceTraceInterval) {
        os_signpost(
            .end,
            log: log,
            name: interval.name,
            signpostID: interval.identifier
        )
    }

}
