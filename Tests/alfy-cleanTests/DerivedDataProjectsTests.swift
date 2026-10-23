import XCTest
@testable import alfy_clean

final class DerivedDataProjectsTests: XCTestCase {
    private var root: String!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "alfy-clean-ddp-\(UUID().uuidString)"
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(atPath: root)
    }

    private let suffix = "abcdefghijklmnopqrstuvwxyzab" // 28 letters

    @discardableResult
    private func makeProject(_ name: String, plist: String?) throws -> String {
        let dir = root + "/" + name
        try fm.createDirectory(atPath: dir + "/Build", withIntermediateDirectories: true)
        if let plist { try plist.write(toFile: dir + "/info.plist", atomically: true, encoding: .utf8) }
        return dir
    }

    private func plist(workspace: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict><key>WorkspacePath</key><string>\(workspace)</string></dict></plist>
        """
    }

    func testReadsWorkspacePathFromPlist() throws {
        let dir = try makeProject("App-\(suffix)", plist: plist(workspace: "/Users/x/App.xcworkspace"))
        XCTAssertEqual(DerivedDataProjects.workspacePath(infoPlist: dir + "/info.plist"), "/Users/x/App.xcworkspace")
    }

    func testWorkspacePathNilForMissingOrGarbagePlist() throws {
        let missing = try makeProject("A-\(suffix)", plist: nil)
        let garbage = try makeProject("B-\(suffix)", plist: "not a plist")
        XCTAssertNil(DerivedDataProjects.workspacePath(infoPlist: missing + "/info.plist"))
        XCTAssertNil(DerivedDataProjects.workspacePath(infoPlist: garbage + "/info.plist"))
    }

    func testOrphanDetection() throws {
        let existing = root + "/Real.xcworkspace"
        try fm.createDirectory(atPath: existing, withIntermediateDirectories: true)
        try makeProject("Real-\(suffix)", plist: plist(workspace: existing))
        try makeProject("Gone-\(suffix)", plist: plist(workspace: root + "/Gone.xcworkspace"))
        try makeProject("Missing-\(suffix)", plist: nil)
        try makeProject("Broken-\(suffix)", plist: "garbage")

        let byName = Dictionary(uniqueKeysWithValues: DerivedDataProjects.projects(in: root).map { ($0.name.prefix(while: { $0 != "-" }), $0) })
        XCTAssertFalse(try XCTUnwrap(byName["Real"]).isOrphan)
        XCTAssertTrue(try XCTUnwrap(byName["Gone"]).isOrphan)
        XCTAssertFalse(try XCTUnwrap(byName["Missing"]).isOrphan, "no plist = unknown, not orphan")
        XCTAssertFalse(try XCTUnwrap(byName["Broken"]).isOrphan, "unreadable plist = unknown, not orphan")
    }

    func testSharedCachesGroupingAndProjectListingExcludeThem() throws {
        for name in ["ModuleCache.noindex", "CompilationCache.noindex", "SDKExplicitPrecompiledModules", "SDKStatCaches.noindex", "SymbolCache.noindex", "builtin"] {
            try fm.createDirectory(atPath: root + "/" + name, withIntermediateDirectories: true)
        }
        try makeProject("App-\(suffix)", plist: plist(workspace: "/x/App.xcodeproj"))

        XCTAssertEqual(DerivedDataProjects.sharedCaches(in: root).map { ($0 as NSString).lastPathComponent },
                       ["ModuleCache.noindex", "CompilationCache.noindex", "SDKExplicitPrecompiledModules"])
        XCTAssertEqual(DerivedDataProjects.projects(in: root).map { $0.name }, ["App-\(suffix)"])
    }

    func testDeletableOnlyDirectChildrenOfAllowedFolders() throws {
        let project = try makeProject("App-\(suffix)", plist: nil)
        let outside = NSTemporaryDirectory() + "alfy-clean-outside-\(UUID().uuidString)"
        try fm.createDirectory(atPath: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: outside) }
        let link = root + "/Link-\(suffix)"
        try fm.createSymbolicLink(atPath: link, withDestinationPath: outside)

        let result = DerivedDataProjects.deletable([project, project + "/Build", outside, link, "/"], allowedFolders: [root])
        XCTAssertEqual(result, [project])
    }

    func testFreedBytesPositiveZeroNegative() {
        XCTAssertEqual(DerivedDataProjects.freedBytes(before: 1_000, after: 5_000), 4_000)
        XCTAssertEqual(DerivedDataProjects.freedBytes(before: 5_000, after: 5_000), 0)
        XCTAssertEqual(DerivedDataProjects.freedBytes(before: 5_000, after: 1_000), -4_000)
        XCTAssertTrue(DerivedDataProjects.freedSpaceMessage(before: 1_000_000_000, after: 3_000_000_000).hasPrefix("Freed 2.0 GB"))
        XCTAssertTrue(DerivedDataProjects.freedSpaceMessage(before: 5, after: 5).hasPrefix("No change"))
        XCTAssertTrue(DerivedDataProjects.freedSpaceMessage(before: 3_000_000_000, after: 1_000_000_000).hasPrefix("No space freed"))
    }

    func testWorktreePathMatching() {
        XCTAssertTrue(DerivedDataProjects.isInside("/a/wt/App.xcworkspace", root: "/a/wt"))
        XCTAssertTrue(DerivedDataProjects.isInside("/a/wt", root: "/a/wt/"))
        XCTAssertFalse(DerivedDataProjects.isInside("/b/App.xcworkspace", root: "/a/wt"))
        XCTAssertFalse(DerivedDataProjects.isInside("/a/wt-other/App.xcworkspace", root: "/a/wt"))
        XCTAssertFalse(DerivedDataProjects.isInside("/a/anything", root: "/"))
    }

    func testProjectsInsideWorktreeFilter() {
        let inside = DerivedDataProject(path: "/dd/A", workspacePath: "/a/wt/A.xcworkspace")
        let sibling = DerivedDataProject(path: "/dd/B", workspacePath: "/a/wt-other/B.xcworkspace")
        let unknown = DerivedDataProject(path: "/dd/C", workspacePath: nil)
        XCTAssertEqual(DerivedDataProjects.projects([inside, sibling, unknown], inside: "/a/wt"), [inside])
    }
}
