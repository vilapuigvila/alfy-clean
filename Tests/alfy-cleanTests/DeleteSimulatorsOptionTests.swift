import XCTest
@testable import alfy_clean

final class DeleteSimulatorsOptionTests: XCTestCase {
    typealias Option = Clean.OptionInput

    func testValue18MapsToDeleteSimulators() throws {
        XCTAssertEqual(try Option(value: 18), .deleteSimulators)
        XCTAssertEqual(Option.deleteSimulators.rawValue, 18)
    }

    func testIsInTheMenu() {
        XCTAssertTrue(Option.menuOptions.contains(.deleteSimulators))
    }

    func testNeverRunsInAllCleanup() {
        XCTAssertFalse(Option.allCleanupOptions(includingDerivedData: true).contains(.deleteSimulators))
        XCTAssertFalse(Option.allCleanupOptions(includingDerivedData: false).contains(.deleteSimulators))
    }

    func testPickerAttributes() {
        XCTAssertEqual(Option.deleteSimulators.risk, .pick)
        XCTAssertEqual(Option.deleteSimulators.category, .xcodeIOS)
        XCTAssertFalse(Option.deleteSimulators.needsConfirmation)
        XCTAssertTrue(Option.deleteSimulators.picksItemsNext)
        XCTAssertEqual(Option.deleteSimulators.tableName, "Delete simulators")
        XCTAssertThrowsError(try Option.deleteSimulators.command())
    }

    func testExistingNumbersKeepTheirCases() throws {
        let expected: [Option] = [
            .noDerivedData, .simultorsData, .clonedSimulatorsData, .derivedData, .archives, .previews,
            .messagesAttachments, .microsoftTeamsCache, .documentationCache, .trash, .homebrewCache,
            .maestroTests, .claudeJobsTmp, .deviceSupport, .simulatorRuntimes, .largeSystemFolders,
            .swiftPMCache, .userCaches
        ]
        for (number, option) in expected.enumerated() {
            XCTAssertEqual(try Option(value: number), option, "-d \(number)")
        }
        XCTAssertThrowsError(try Option(value: 19))
    }
}
