import XCTest
@testable import alfy_clean

final class ClaudeSessionFoldersTests: XCTestCase {
    typealias Option = Clean.OptionInput
    private var root: URL!
    private let manager = FileManager.default

    override func setUpWithError() throws {
        root = manager.temporaryDirectory.appendingPathComponent("alfy-clean-claude-tests-\(UUID().uuidString)")
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? manager.removeItem(at: root)
    }

    private func makeFolder(_ name: String) throws -> String {
        let url = root.appendingPathComponent(name)
        try manager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.path
    }

    // MARK: Folders

    func testListsOnlyOwnClaudeFoldersDirectlyInsideTheRoot() throws {
        let mine = try makeFolder("claude-501")
        _ = try makeFolder("other")
        _ = try makeFolder("claude-")                              // the prefix alone is not a match
        manager.createFile(atPath: root.appendingPathComponent("claude-file").path, contents: Data())
        try manager.createDirectory(at: root.appendingPathComponent("nested/claude-502"), withIntermediateDirectories: true)

        XCTAssertEqual(ClaudeSessionFolders.folders(in: root.path), [mine])
    }

    func testASymlinkNamedClaudeIsNotListed() throws {
        let target = try makeFolder("somewhere")
        try manager.createSymbolicLink(atPath: root.appendingPathComponent("claude-link").path, withDestinationPath: target)
        XCTAssertEqual(ClaudeSessionFolders.folders(in: root.path), [])
    }

    func testAFolderOfAnotherUserIsNotListed() throws {
        _ = try makeFolder("claude-501")
        XCTAssertEqual(ClaudeSessionFolders.folders(in: root.path, ownedBy: getuid() &+ 1), [])
    }

    // MARK: Safe to delete now

    func testSafeToDeleteNowAcceptsAMatchingDirectChild() throws {
        let folder = try makeFolder("claude-501")
        XCTAssertTrue(ClaudeSessionFolders.isSafeToDeleteNow(folder, root: root.path))
    }

    func testSafeToDeleteNowRefusesASwappedInSymlinkAndOtherNames() throws {
        let target = try makeFolder("precious")
        let link = root.appendingPathComponent("claude-501")
        try manager.createSymbolicLink(atPath: link.path, withDestinationPath: target)
        XCTAssertFalse(ClaudeSessionFolders.isSafeToDeleteNow(link.path, root: root.path))
        XCTAssertFalse(ClaudeSessionFolders.isSafeToDeleteNow(target, root: root.path))
        XCTAssertFalse(ClaudeSessionFolders.isSafeToDeleteNow(root.path, root: root.path))
    }

    func testSafeToDeleteNowRefusesAFolderOutsideTheRootAndNestedOnes() throws {
        let nested = root.appendingPathComponent("a/claude-501")
        try manager.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertFalse(ClaudeSessionFolders.isSafeToDeleteNow(nested.path, root: root.path))
        XCTAssertFalse(ClaudeSessionFolders.isSafeToDeleteNow("/private/tmp/claude-501", root: root.path))
    }

    // MARK: Menu wiring

    func testTheRowIsInTheAISectionBeforeSystemAndApps() {
        XCTAssertEqual(Option.claudeSessionFolders.category, .ai)
        XCTAssertEqual(Option.Category.ai.title, "AI")
        XCTAssertLessThan(Option.Category.ai.rawValue, Option.Category.systemAndApps.rawValue)
        XCTAssertGreaterThan(Option.Category.ai.rawValue, Option.Category.caches.rawValue)
    }

    func testTheRowIsNumber19AndNeverPartOfAllCleanup() throws {
        XCTAssertEqual(try Option(value: 19), .claudeSessionFolders)
        XCTAssertFalse(Option.allCleanupOptions(includingDerivedData: true).contains(.claudeSessionFolders))
        XCTAssertFalse(Option.allCleanupOptions(includingDerivedData: false).contains(.claudeSessionFolders))
        XCTAssertTrue(Option.claudeSessionFolders.needsConfirmation)
        XCTAssertThrowsError(try Option.claudeSessionFolders.command())
    }

    func testRefusalOnlyWhileClaudeCodeIsRunning() {
        XCTAssertNil(ClaudeSessionFolders.refusal(running: 0))
        XCTAssertTrue(ClaudeSessionFolders.refusal(running: 1)?.contains("1 Claude Code process is running") ?? false)
        XCTAssertTrue(ClaudeSessionFolders.refusal(running: 3)?.contains("3 Claude Code processes are running") ?? false)
        XCTAssertTrue(ClaudeSessionFolders.refusal(running: 1)?.hasPrefix("Not deleted") ?? false)
    }

    func testNoProcessIsFoundForAUserWhoRunsNone() {
        // uid 0xFFFFFFFE has no processes, so the count must be 0 whatever else runs on this Mac.
        XCTAssertEqual(ClaudeSessionFolders.runningSessionCount(ownedBy: 0xFFFF_FFFE), 0)
    }

    func testClaudeCodeJobsTmpIsInTheAISectionToo() {
        XCTAssertEqual(Option.claudeJobsTmp.category, .ai)
    }

    func testTheWarningTellsToCloseEverySession() {
        let warning = Option.claudeSessionFolders.warningDescription ?? ""
        XCTAssertTrue(warning.contains("Close every Claude Code session"), warning)
        XCTAssertNil(Option.userCaches.warningDescription)
    }

    // MARK: Info panel

    func testTheInfoPanelShowsTheWarningInEveryLayout() {
        let row = CheckboxTableRow(
            name: "Claude Code session files", group: "AI", bytes: 1, size: "1 MB", risk: .final,
            warning: ClaudeSessionFolders.warning, summary: "Deletes folders.", facts: [("Deletes", "claude-*")]
        )
        let other = CheckboxTableRow(
            name: "Other", group: "Caches", bytes: 1, size: "1 MB", risk: .safe, summary: "x", facts: []
        )
        for rows in [40, 24, 14] {
            for columns in [130, 80] {
                let layout = CheckboxTableLayout(rows: [other, row], question: nil, size: (rows: rows, columns: columns))
                let text = layout.lines(focused: 1, selected: []).joined(separator: "\n")
                    .replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
                XCTAssertTrue(text.contains("Close every"), "\(rows)x\(columns)")
                // No warning for a row that has none.
                let plain = layout.lines(focused: 0, selected: []).joined(separator: "\n")
                XCTAssertFalse(plain.contains("Close every"), "\(rows)x\(columns)")
            }
        }
    }
}
