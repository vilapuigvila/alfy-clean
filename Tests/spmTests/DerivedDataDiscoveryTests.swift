import XCTest
@testable import avp

final class DerivedDataDiscoveryTests: XCTestCase {
    private var root: String!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = NSHomeDirectory() + "/Library/Caches/avp-tests-\(UUID().uuidString)"
        try fm.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(atPath: root)
    }

    private func make(_ paths: String...) throws {
        for path in paths {
            try fm.createDirectory(atPath: root + "/" + path, withIntermediateDirectories: true)
        }
    }

    private func discover(maxDepth: Int = 7) -> [String] {
        // Default and custom locations are switched off so only the scratch tree is searched.
        DerivedDataDiscovery.find(
            searchRoot: root,
            maxDepth: maxDepth,
            defaultLocation: root + "/no-such-default",
            customLocation: nil
        )
    }

    func testFindsDerivedDataNextToXcodeproj() throws {
        try make("a/App.xcodeproj", "a/DerivedData/Build")
        XCTAssertEqual(discover(), [root + "/a/DerivedData"])
    }

    func testFindsDerivedDataNextToXcworkspace() throws {
        try make("b/App.xcworkspace", "b/DerivedData/Build")
        XCTAssertEqual(discover(), [root + "/b/DerivedData"])
    }

    func testFindsDerivedDataOneLevelBelowProject() throws {
        try make("c/ios/build/DerivedData/Build", "c/ios/App.xcodeproj")
        // Project in the grandparent: ios/ holds the project, DerivedData is in ios/build/.
        XCTAssertEqual(discover(), [root + "/c/ios/build/DerivedData"])
    }

    func testIgnoresDerivedDataWithoutXcodeProject() throws {
        try make("d/DerivedData/Build", "d/docs")
        XCTAssertEqual(discover(), [])
    }

    func testIgnoresPrunedFolders() throws {
        try make("e/node_modules/pkg/App.xcodeproj", "e/node_modules/pkg/DerivedData",
                 "e/Pods/App.xcodeproj", "e/Pods/DerivedData", "e/.build/App.xcodeproj", "e/.build/DerivedData")
        XCTAssertEqual(discover(), [])
    }

    func testIgnoresDerivedDataBeyondDepthLimit() throws {
        try make("f/g/h/App.xcodeproj", "f/g/h/DerivedData")   // depth 4 below the root
        XCTAssertEqual(discover(maxDepth: 4), [root + "/f/g/h/DerivedData"])
        XCTAssertEqual(discover(maxDepth: 3), [])
    }

    func testOnlyExactName() throws {
        try make("i/App.xcodeproj", "i/DerivedData-old", "i/MyDerivedData")
        XCTAssertEqual(discover(), [])
    }

    func testDoesNotDescendIntoFoundDerivedData() throws {
        try make("j/App.xcodeproj", "j/DerivedData/x/App.xcodeproj", "j/DerivedData/x/DerivedData")
        XCTAssertEqual(discover(), [root + "/j/DerivedData"])
    }

    func testCustomLocationInsideHomeIsIncludedAndOutsideIsNot() throws {
        try make("custom/dd")
        let inside = DerivedDataDiscovery.find(searchRoot: root + "/none", defaultLocation: root + "/none",
                                               customLocation: root + "/custom/dd")
        XCTAssertEqual(inside, [root + "/custom/dd"])
        let outside = DerivedDataDiscovery.find(searchRoot: root + "/none", defaultLocation: root + "/none",
                                                customLocation: "/tmp")
        XCTAssertEqual(outside, [])
    }

    func testDeleteCommandRemovesOnlyDiscoveredFolders() throws {
        try make("k/App.xcodeproj", "k/DerivedData/Build", "keep/DerivedData")
        let found = discover()
        let result = runProcess("/bin/rm", ["-rf"] + found)
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(fm.fileExists(atPath: root + "/k/DerivedData"))
        XCTAssertTrue(fm.fileExists(atPath: root + "/keep/DerivedData"))
    }
}
