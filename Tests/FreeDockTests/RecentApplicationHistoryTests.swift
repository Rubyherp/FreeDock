import Foundation
import Testing
@testable import FreeDock

@Suite("Recent and running applications")
struct RecentApplicationHistoryTests {
    private let first = RecentApplicationRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        bundleIdentifier: "example.first",
        path: "/Applications/First.app",
        displayName: "First",
        lastUsedAt: Date(timeIntervalSince1970: 10)
    )
    private let second = RecentApplicationRecord(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        bundleIdentifier: "example.second",
        path: "/Applications/Second.app",
        displayName: "Second",
        lastUsedAt: Date(timeIntervalSince1970: 20)
    )

    @Test("Running applications lead recent applications")
    func runningFirst() {
        let items = DynamicApplicationSectionPlanner.items(
            records: [second, first],
            runningBundleIDs: [first.bundleIdentifier],
            pinnedItems: [],
            limit: 5
        )
        #expect(items.map { $0.id } == [first.id, second.id])
    }

    @Test("Pinned applications are excluded and limits are enforced")
    func excludesPinned() {
        let pinned = DockItem.application(
            at: URL(fileURLWithPath: second.path)
        )
        let items = DynamicApplicationSectionPlanner.items(
            records: [second, first],
            runningBundleIDs: [],
            pinnedItems: [pinned],
            limit: 1
        )
        #expect(items.map { $0.id } == [first.id])
    }

    @Test("Recording reuses identity and moves an app to the front")
    func recording() {
        let updated = RecentApplicationHistoryPlanner.recording(
            bundleIdentifier: first.bundleIdentifier,
            path: first.path,
            displayName: first.displayName,
            usedAt: Date(timeIntervalSince1970: 30),
            in: [second, first]
        )
        #expect(updated.first?.id == first.id)
        #expect(updated.first?.lastUsedAt == Date(timeIntervalSince1970: 30))
    }

    @Test("Application history round-trips with config")
    func configRoundTrip() throws {
        let config = AppConfig(recentApplications: [first, second])
        let decoded = try JSONDecoder().decode(
            AppConfig.self,
            from: JSONEncoder().encode(config)
        )
        #expect(decoded.recentApplications.map { $0.id } == [second.id, first.id])
    }
}
