import XCTest
@testable import avp

final class DiskUsageTests: XCTestCase {
    private var root: String!
    private let fm = FileManager.default
    private let size = 8_000_000

    override func setUpWithError() throws {
        // Under the home folder (APFS), never the real simulator folders.
        root = NSHomeDirectory() + "/Library/Caches/avp-tests-\(UUID().uuidString)"
        try fm.createDirectory(atPath: root + "/source", withIntermediateDirectories: true)
        // Random bytes: APFS can't compress or sparsify them.
        let data = Data((0..<size).map { _ in UInt8.random(in: 0...255) })
        fm.createFile(atPath: root + "/source/file", contents: data)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(atPath: root)
    }

    func testCloneSharesItsBlocksSoDeletingItFreesAlmostNothing() throws {
        XCTAssertTrue(runProcess("/bin/cp", ["-c", "-R", root + "/source", root + "/clone"]).success)
        let paths = [root + "/source", root + "/clone"]
        let measured = DiskUsage.measure(paths: paths)
        let reclaimable = DiskUsage.measureReclaimable(paths: paths)

        XCTAssertGreaterThanOrEqual(measured[paths[1]]!.bytes, UInt64(size), "du counts the clone in full")
        XCTAssertLessThan(reclaimable[paths[1]]!.bytes, UInt64(size) / 10, "but its blocks are shared with the source")
    }

    func testIndependentCopyCountsInFull() throws {
        XCTAssertTrue(runProcess("/bin/cp", ["-R", root + "/source", root + "/copy"]).success)
        let reclaimable = DiskUsage.measureReclaimable(paths: [root + "/copy"])
        XCTAssertGreaterThanOrEqual(reclaimable[root + "/copy"]!.bytes, UInt64(size))
    }

    func testMissingPathIsZero() {
        XCTAssertEqual(DiskUsage.measureReclaimable(paths: [root + "/nope"])[root + "/nope"]?.bytes, 0)
    }
}
