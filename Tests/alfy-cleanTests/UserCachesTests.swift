import XCTest
@testable import alfy_clean

final class UserCachesTests: XCTestCase {
    private var root: String!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        // Scratch "Caches" folder under the real one: never touches real cache folders.
        root = NSHomeDirectory() + "/Library/Caches/alfy-clean-tests-\(UUID().uuidString)"
        for name in ["BigApp", "SmallApp", "org.swift.swiftpm", "Homebrew"] {
            try fm.createDirectory(atPath: root + "/" + name, withIntermediateDirectories: true)
        }
        fm.createFile(atPath: root + "/loose-file", contents: Data())
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(atPath: root)
    }

    func testRootFoldersListsOnlyRealFoldersWithoutTheOnesThatHaveARow() throws {
        try fm.createSymbolicLink(atPath: root + "/Link", withDestinationPath: root + "/BigApp")
        let names = UserCaches.rootFolders(in: root).map { ($0 as NSString).lastPathComponent }
        XCTAssertEqual(names, ["BigApp", "SmallApp"])
    }

    func testLargeFoldersKeepsOnlyThoseAtOrOverTheMinimumBiggestFirst() {
        let usages = [
            "/a": DiskUsage(bytes: 1_000_000_000, isPartial: false),
            "/b": DiskUsage(bytes: 999_999_999, isPartial: false),
            "/c": DiskUsage(bytes: 9_000_000_000, isPartial: false)
        ]
        let large = UserCaches.largeFolders(["/a", "/b", "/c", "/missing"], usages: usages)
        XCTAssertEqual(large.map { $0.path }, ["/c", "/a"])
    }

    func testDirectRealFolderIsSafeToDelete() {
        XCTAssertTrue(UserCaches.isSafeToDeleteNow(root + "/BigApp", root: root))
    }

    func testNestedFolderOutsideFolderAndOwnRowFoldersAreRefused() throws {
        try fm.createDirectory(atPath: root + "/BigApp/inner", withIntermediateDirectories: true)
        XCTAssertFalse(UserCaches.isSafeToDeleteNow(root + "/BigApp/inner", root: root), "not a direct child")
        XCTAssertFalse(UserCaches.isSafeToDeleteNow(root, root: root), "the Caches folder itself")
        XCTAssertFalse(UserCaches.isSafeToDeleteNow(NSHomeDirectory() + "/Library", root: root), "outside the root")
        XCTAssertFalse(UserCaches.isSafeToDeleteNow(root + "/org.swift.swiftpm", root: root), "has its own row")
        XCTAssertFalse(UserCaches.isSafeToDeleteNow(root + "/Missing", root: root), "gone since the scan")
        XCTAssertFalse(UserCaches.isSafeToDeleteNow(root + "/loose-file", root: root), "a file, not a folder")
    }

    func testSymlinkSwappedInIsRefused() throws {
        try fm.removeItem(atPath: root + "/SmallApp")
        try fm.createSymbolicLink(atPath: root + "/SmallApp", withDestinationPath: NSHomeDirectory() + "/Library")
        XCTAssertFalse(UserCaches.isSafeToDeleteNow(root + "/SmallApp", root: root))
    }

    func testDotDotPathCannotEscapeTheRoot() {
        XCTAssertFalse(UserCaches.isSafeToDeleteNow(root + "/BigApp/../../Preferences", root: root))
    }

    func testSwiftPMOptionDeletesOnlyItsFolder() throws {
        let command = try Clean.OptionInput.swiftPMCache.command()
        XCTAssertEqual(command.executable, "/bin/rm")
        XCTAssertEqual(command.arguments, ["-rf", NSHomeDirectory() + "/Library/Caches/org.swift.swiftpm"])
    }

    func testCachesSectionReplacesDeveloperTools() {
        XCTAssertEqual(Clean.OptionInput.Category.caches.title, "Caches")
        XCTAssertEqual(Clean.OptionInput.homebrewCache.category, .caches)
        XCTAssertEqual(Clean.OptionInput.swiftPMCache.category, .caches)
        XCTAssertEqual(Clean.OptionInput.userCaches.category, .caches)
    }
}
