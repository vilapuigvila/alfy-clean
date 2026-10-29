import XCTest
@testable import alfy_clean

final class SystemScannerThresholdTests: XCTestCase {
    private typealias Threshold = SystemScanner.SizeThreshold

    // Fake `du -k` output (KiB). Paths are not nested, so no parent folder is dropped.
    private let duOutput = [
        "1953125\t/opt/at-two-gb",          // exactly 2 GB
        "1953126\t/opt/just-over-two-gb",
        "4882812\t/opt/at-five-gb",         // exactly 5 GB
        "6000000\t/opt/six-gb",
        "9765625\t/opt/at-ten-gb",          // exactly 10 GB
    ].joined(separator: "\n")

    /// The paths in the scan output, in the order they were printed.
    private func listedPaths(_ output: String) -> [String] {
        output.components(separatedBy: "\n").compactMap { line in
            line.components(separatedBy: " GB  ").last.flatMap { $0.hasPrefix("/") ? $0 : nil }
        }
    }

    func testDefaultThresholdIsFiveGB() {
        XCTAssertEqual(Threshold.default, .fiveGB)
        XCTAssertEqual(Threshold.default.rawValue, 5)
    }

    func testMenuChoicesAreTwoFiveAndTenGB() {
        XCTAssertEqual(Threshold.allCases.map(\.description), ["2 GB", "5 GB", "10 GB"])
    }

    func testKilobytesMatchTheGigabyteLabel() {
        XCTAssertEqual(Threshold.twoGB.kilobytes, 1_953_125)
        XCTAssertEqual(Threshold.fiveGB.kilobytes, 4_882_812)
        XCTAssertEqual(Threshold.tenGB.kilobytes, 9_765_625)
    }

    func testFiveGBDefaultListsOnlyFoldersOverFiveGB() {
        // Exactly 5 GB is left out; the 10 GB and 6 GB folders are over 5 GB. Biggest first.
        let output = SystemScanner.largeFolders(fromDU: duOutput)
        XCTAssertEqual(listedPaths(output), ["/opt/at-ten-gb", "/opt/six-gb"])
    }

    func testTwoGBListsFoldersOverTwoGBButNotExactlyTwoGB() {
        let output = SystemScanner.largeFolders(fromDU: duOutput, threshold: .twoGB)
        XCTAssertEqual(listedPaths(output), ["/opt/at-ten-gb", "/opt/six-gb", "/opt/at-five-gb", "/opt/just-over-two-gb"])
    }

    func testTenGBListsOnlyFoldersOverTenGB() {
        let output = SystemScanner.largeFolders(fromDU: duOutput, threshold: .tenGB)
        XCTAssertEqual(listedPaths(output), [])
        XCTAssertEqual(output, "")
    }
}
