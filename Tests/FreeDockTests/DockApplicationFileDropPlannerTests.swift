import Foundation
import Testing
@testable import FreeDock

@Suite("Dock application file drop planner")
struct DockApplicationFileDropPlannerTests {
    @Test("Ready plans normalize URLs and preserve first-seen order")
    func readyPlan() throws {
        let applicationURL = URL(
            fileURLWithPath: "/Applications/../Applications/Editor.APP"
        )
        let firstURL = URL(
            fileURLWithPath: "/tmp/FreeDock Drop/First.txt"
        )
        let secondURL = URL(
            fileURLWithPath: "/tmp/FreeDock Drop/Nested/../Second.txt"
        )

        let outcome = DockApplicationFileDropPlanner.plan(
            applicationURL: applicationURL,
            droppedURLs: [firstURL, secondURL]
        )
        let plan = try #require(outcome.plan)

        #expect(outcome.isReady)
        #expect(outcome.rejection == nil)
        #expect(
            plan.applicationURL.path == "/Applications/Editor.APP"
        )
        #expect(
            plan.fileURLs.map(\.path) == [
                "/tmp/FreeDock Drop/First.txt",
                "/tmp/FreeDock Drop/Second.txt",
            ]
        )
        #expect(plan.duplicateInputIndices.isEmpty)
        #expect(plan.removedDuplicateCount == 0)
    }

    @Test("Lexical duplicates are removed stably and reported")
    func stableDuplicateRemoval() throws {
        let first = URL(fileURLWithPath: "/tmp/Drop/Document.txt")
        let sameWithTraversal = URL(
            fileURLWithPath: "/tmp/Drop/Nested/../Document.txt"
        )
        let distinctCase = URL(
            fileURLWithPath: "/tmp/Drop/document.txt"
        )

        let outcome = DockApplicationFileDropPlanner.plan(
            applicationURL: appURL,
            droppedURLs: [
                first,
                sameWithTraversal,
                distinctCase,
                first,
            ]
        )
        let plan = try #require(outcome.plan)

        #expect(
            plan.fileURLs.map(\.path) == [
                "/tmp/Drop/Document.txt",
                "/tmp/Drop/document.txt",
            ]
        )
        #expect(plan.duplicateInputIndices == [1, 3])
        #expect(plan.removedDuplicateCount == 2)
    }

    @Test("Missing and invalid application URLs have precise rejections")
    func invalidApplicationURLs() {
        let missing = DockApplicationFileDropPlanner.plan(
            applicationURL: nil,
            droppedURLs: [documentURL]
        )
        let webURL = DockApplicationFileDropPlanner.plan(
            applicationURL: URL(string: "https://example.com/Editor.app"),
            droppedURLs: [documentURL]
        )
        let remoteFileURL = DockApplicationFileDropPlanner.plan(
            applicationURL: URL(
                string: "file://files.example.com/Applications/Editor.app"
            ),
            droppedURLs: [documentURL]
        )
        let relativeFileURL = DockApplicationFileDropPlanner.plan(
            applicationURL: URL(string: "file:Editor")!,
            droppedURLs: [documentURL]
        )

        #expect(missing.rejection == .missingApplicationURL)
        #expect(
            webURL.rejection
                == .invalidApplicationURL(.notFileURL)
        )
        #expect(
            remoteFileURL.rejection
                == .invalidApplicationURL(.nonLocalFileURL)
        )
        #expect(
            relativeFileURL.rejection
                == .invalidApplicationURL(.relativePath)
        )
    }

    @Test("Extensionless application targets remain lexically valid")
    func extensionlessApplicationTarget() throws {
        let extensionlessTarget = URL(
            fileURLWithPath: "/Applications/Editor Alias"
        )
        let outcome = DockApplicationFileDropPlanner.plan(
            applicationURL: extensionlessTarget,
            droppedURLs: [documentURL]
        )
        let plan = try #require(outcome.plan)

        #expect(outcome.isReady)
        #expect(plan.applicationURL == extensionlessTarget)
    }

    @Test("Folders and packages remain valid application payloads")
    func foldersAndPackages() throws {
        let folderURL = URL(fileURLWithPath: "/tmp/Project Folder")
        let packageURL = URL(fileURLWithPath: "/tmp/Example.playground")

        let outcome = DockApplicationFileDropPlanner.plan(
            applicationURL: appURL,
            droppedURLs: [folderURL, packageURL]
        )
        let plan = try #require(outcome.plan)

        #expect(plan.fileURLs == [folderURL, packageURL])
    }

    @Test("An empty Finder payload is rejected")
    func emptyDrop() {
        let outcome = DockApplicationFileDropPlanner.plan(
            applicationURL: appURL,
            droppedURLs: []
        )

        #expect(outcome.rejection == .emptyDrop)
    }

    @Test("Invalid dropped URLs identify their original payload index")
    func invalidDroppedURL() {
        let webURL = URL(string: "https://example.com/Document.txt")!
        let outcome = DockApplicationFileDropPlanner.plan(
            applicationURL: appURL,
            droppedURLs: [documentURL, webURL]
        )

        #expect(
            outcome.rejection
                == .invalidDroppedURL(index: 1, reason: .notFileURL)
        )
        #expect(!outcome.isReady)
        #expect(outcome.plan == nil)
    }

    @Test("Remote Finder file URLs are not treated as local paths")
    func remoteDroppedURL() {
        let remoteFileURL = URL(
            string: "file://files.example.com/Shared/Document.txt"
        )!
        let outcome = DockApplicationFileDropPlanner.plan(
            applicationURL: appURL,
            droppedURLs: [remoteFileURL]
        )

        #expect(
            outcome.rejection
                == .invalidDroppedURL(
                    index: 0,
                    reason: .nonLocalFileURL
                )
        )
    }

    @Test("Missing and relative file paths are rejected precisely")
    func malformedFilePaths() {
        let missingPath = DockApplicationFileDropPlanner.plan(
            applicationURL: appURL,
            droppedURLs: [URL(string: "file:")!]
        )
        let relativePath = DockApplicationFileDropPlanner.plan(
            applicationURL: appURL,
            droppedURLs: [URL(string: "file:Document.txt")!]
        )

        #expect(
            missingPath.rejection
                == .invalidDroppedURL(index: 0, reason: .missingPath)
        )
        #expect(
            relativePath.rejection
                == .invalidDroppedURL(index: 0, reason: .relativePath)
        )
    }

    @Test("Localhost file URLs normalize to ordinary local URLs")
    func localhostFileURL() throws {
        let localhostURL = URL(
            string: "file://localhost/tmp/Document.txt"
        )!
        let outcome = DockApplicationFileDropPlanner.plan(
            applicationURL: appURL,
            droppedURLs: [localhostURL]
        )
        let plan = try #require(outcome.plan)

        #expect(plan.fileURLs == [documentURL])
    }

    private var appURL: URL {
        URL(fileURLWithPath: "/Applications/Editor.app")
    }

    private var documentURL: URL {
        URL(fileURLWithPath: "/tmp/Document.txt")
    }
}
