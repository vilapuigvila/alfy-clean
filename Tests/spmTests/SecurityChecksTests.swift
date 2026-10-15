import XCTest
@testable import avp

/// Regression tests for SECURITY_AUDIT.md M3 (symlink swap before delete) and L3 (terminal control characters).
final class SecurityChecksTests: XCTestCase {
    private var root: String!

    override func setUpWithError() throws {
        // Under $HOME with a DerivedData component, so the paths are on the safe-to-delete allowlist.
        root = NSHomeDirectory() + "/Library/Caches/avp-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root + "/real/DerivedData/Build", withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    func testRealFolderOnAllowlistIsSafeToDelete() {
        XCTAssertTrue(SystemScanner.isSafeToDeleteNow(root + "/real/DerivedData/Build"))
    }

    func testPathThroughSwappedInSymlinkIsRefused() throws {
        // A parent folder replaced by a link after the scan: removeItem would follow it.
        try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: root + "/real")
        let throughLink = root + "/link/DerivedData/Build"

        XCTAssertNotNil(SystemScanner.safeDeleteNote(for: throughLink), "the text alone passes the allowlist")
        XCTAssertFalse(SystemScanner.isSafeToDeleteNow(throughLink))
    }

    func testFolderGoneSinceScanIsRefused() {
        XCTAssertFalse(SystemScanner.isSafeToDeleteNow(root + "/real/DerivedData/Missing"))
    }

    func testScanListDropsSymlinkedPaths() throws {
        try FileManager.default.createSymbolicLink(atPath: root + "/link", withDestinationPath: root + "/real")
        let output = """
          9.9 GB  \(root!)/real/DerivedData/Build
          9.9 GB  \(root!)/link/DerivedData/Build
        """

        XCTAssertEqual(SystemScanner.safeToDelete(from: output).map(\.path), [root + "/real/DerivedData/Build"])
    }

    func testTerminalSafeReplacesControlCharacters() {
        let crafted = "iPhone\u{1B}[2J\u{1B}]52;c;aGk=\u{07}\nfake line\u{9B}31m"
        XCTAssertEqual(crafted.terminalSafe, "iPhone?[2J?]52;c;aGk=??fake line?31m")
    }

    func testTerminalSafeKeepsOrdinaryText() {
        let name = "iPhone 17 Pro Max · iOS 26.4 (23E5) 🎭"
        XCTAssertEqual(name.terminalSafe, name)
    }
}
