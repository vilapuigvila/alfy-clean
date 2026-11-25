import XCTest
@testable import alfy_clean

final class MenuAutoRefreshTests: XCTestCase {
    // MARK: Timing

    func testRefreshIsNotDueBeforeTheInterval() {
        let last = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(isRefreshDue(lastMeasured: last, now: last.addingTimeInterval(3599), interval: 3600, isRunning: false))
    }

    func testRefreshIsDueAtAndAfterTheInterval() {
        let last = Date(timeIntervalSince1970: 1_000)
        XCTAssertTrue(isRefreshDue(lastMeasured: last, now: last.addingTimeInterval(3600), interval: 3600, isRunning: false))
        XCTAssertTrue(isRefreshDue(lastMeasured: last, now: last.addingTimeInterval(9000), interval: 3600, isRunning: false))
    }

    func testRefreshIsNeverDueWhileOneRuns() {
        let last = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(isRefreshDue(lastMeasured: last, now: last.addingTimeInterval(99_999), interval: 3600, isRunning: true))
    }

    // MARK: Remap

    func testTicksAndFocusFollowTheOptionAcrossReorder() {
        let result = remap(selected: [0, 2], focused: 1, from: [10, 20, 30], to: [30, 10, 20])
        XCTAssertEqual(result.selected, [0, 1])      // 30 -> 0, 10 -> 1
        XCTAssertEqual(result.focused, 2)            // 20 -> 2
    }

    func testRowAddedKeepsTicksAndFocusOnTheSameOptions() {
        let result = remap(selected: [1], focused: 1, from: [10, 20], to: [5, 10, 20])
        XCTAssertEqual(result.selected, [2])
        XCTAssertEqual(result.focused, 2)
    }

    func testRowRemovedDropsItsTickAndKeepsTheOthers() {
        let result = remap(selected: [0, 2], focused: 2, from: [10, 20, 30], to: [10, 30])
        XCTAssertEqual(result.selected, [0, 1])
        XCTAssertEqual(result.focused, 1)
    }

    func testFocusedRowRemovedClampsToAValidIndex() {
        let result = remap(selected: [2], focused: 2, from: [10, 20, 30], to: [10, 20])
        XCTAssertEqual(result.focused, 1)
        XCTAssertTrue(result.selected.isEmpty)
        XCTAssertEqual(remap(selected: [], focused: 1, from: [10, 20, 30], to: [20, 30, 40]).focused, 0)
    }

    // MARK: Notification

    func testNotificationShowsPositiveDelta() {
        XCTAssertEqual(refreshNotificationMessage(busyBefore: 400_000_000_000, busyAfter: 403_200_000_000),
                       "Sizes refreshed — busy 403.2 GB (+3.2 GB since last)")
    }

    func testNotificationShowsNegativeDelta() {
        XCTAssertEqual(refreshNotificationMessage(busyBefore: 401_100_000_000, busyAfter: 400_000_000_000),
                       "Sizes refreshed — busy 400.0 GB (−1.1 GB since last)")
    }

    func testNotificationShowsZeroDelta() {
        XCTAssertEqual(refreshNotificationMessage(busyBefore: 400_000_000_000, busyAfter: 400_000_000_000),
                       "Sizes refreshed — busy 400.0 GB (±0 GB since last)")
        XCTAssertTrue(refreshNotificationMessage(busyBefore: 400_000_000_000, busyAfter: 400_010_000_000).contains("±0 GB"))
    }

    // MARK: Hint line

    private func row(_ name: String) -> CheckboxTableRow {
        CheckboxTableRow(name: name, group: "Caches", bytes: 1, size: "1 GB", risk: .safe, summary: "s",
                         facts: [("Deletes", "d"), ("Comes back", "c"), ("Asks first", "a")])
    }

    func testHintShowsRefreshKeyAndStatusAtEveryLayoutLevel() {
        let rows = (0..<12).map { row("Row \($0)") }
        // From tall to very short, wide to narrow: every layout level gets exercised.
        for size in [(rows: 80, columns: 130), (rows: 30, columns: 130), (rows: 24, columns: 100), (rows: 20, columns: 90),
                     (rows: 14, columns: 70), (rows: 8, columns: 60)] {
            for status in ["updated 09:41", "refreshing…"] {
                let frame = CheckboxTableLayout(rows: rows, question: "Q\nQ2", size: size, status: status)
                    .lines(focused: 0, selected: [])
                    .joined(separator: "\n")
                XCTAssertTrue(frame.contains("r refresh"), "\(size) \(status)")
                XCTAssertTrue(frame.contains(status), "\(size) \(status)")
            }
        }
    }

    func testPlainHintIsUnchangedWithoutStatus() {
        let frame = CheckboxTableLayout(rows: [row("A")], question: nil, size: (rows: 40, columns: 120))
            .lines(focused: 0, selected: []).joined(separator: "\n")
        XCTAssertTrue(frame.contains("space select  •  enter confirm  •  q cancel"))
        XCTAssertFalse(frame.contains("r refresh"))
    }

    func testStatusTextFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = Date(timeIntervalSince1970: 9 * 3600 + 5 * 60)
        XCTAssertEqual(refreshStatusText(isRefreshing: false, updatedAt: date, calendar: calendar), "updated 09:05")
        XCTAssertEqual(refreshStatusText(isRefreshing: true, updatedAt: date, calendar: calendar), "refreshing…")
    }

    // MARK: Controller

    private func snapshot(_ ids: [Int], busy: UInt64, at date: Date) -> MenuSnapshot {
        MenuSnapshot(ids: ids, rows: ids.map { row("R\($0)") }, question: "Q", busyBytes: busy, measuredAt: date)
    }

    func testControllerRefreshSwapsSnapshotRemapsAndNotifiesOnce() {
        let start = Date(timeIntervalSince1970: 0)
        var clock = start
        let next = snapshot([30, 10, 20], busy: 5, at: start)
        var notified: [(UInt64, UInt64)] = []
        let config = MenuAutoRefresh(measure: { next }, didRefresh: { notified.append(($0.busyBytes, $1.busyBytes)) })
        let controller = MenuRefreshController(snapshot: snapshot([10, 20, 30], busy: 1, at: start), config: config, now: { clock })
        var focused = 1
        var selected: Set<Int> = [0]

        XCTAssertFalse(controller.tick(focused: &focused, selected: &selected))   // not due yet
        XCTAssertTrue(controller.startRefresh())
        XCTAssertFalse(controller.startRefresh())                                  // already running
        XCTAssertTrue(controller.isRefreshing)

        clock = start.addingTimeInterval(5)
        let deadline = Date().addingTimeInterval(5)
        while controller.isRefreshing && Date() < deadline {
            _ = controller.tick(focused: &focused, selected: &selected)
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertFalse(controller.isRefreshing)
        XCTAssertEqual(controller.snapshot.ids, [30, 10, 20])
        XCTAssertEqual(selected, [1])        // option 10 moved from 0 to 1
        XCTAssertEqual(focused, 2)           // option 20 moved from 1 to 2
        XCTAssertEqual(notified.count, 1)
    }

    // MARK: Refresh loader

    func testLoaderLineUsesTheStartupSpinnerAndWords() {
        let line = refreshLoaderLine(frame: 0, word: "Pondering")
        XCTAssertTrue(line.contains(TerminalLoader.spinnerFrames[0]))
        XCTAssertTrue(line.contains("Pondering"))
        XCTAssertTrue(line.contains("processing"))
        // The spinner advances and wraps around, including a negative frame.
        XCTAssertTrue(refreshLoaderLine(frame: 1, word: "x").contains(TerminalLoader.spinnerFrames[1]))
        XCTAssertTrue(refreshLoaderLine(frame: TerminalLoader.spinnerFrames.count, word: "x").contains(TerminalLoader.spinnerFrames[0]))
        XCTAssertTrue(refreshLoaderLine(frame: -1, word: "x").contains(TerminalLoader.spinnerFrames.last!))
    }

    func testLoaderReplacesTheHintWhileRefreshingAtEveryLayoutLevel() {
        let rows = (0..<12).map { row("Row \($0)") }
        let loader = refreshLoaderLine(frame: 3, word: "Mulling")
        for size in [(rows: 80, columns: 130), (rows: 24, columns: 100), (rows: 14, columns: 70), (rows: 8, columns: 60)] {
            let frame = CheckboxTableLayout(rows: rows, question: "Q", size: size, status: "refreshing…", loader: loader)
                .lines(focused: 0, selected: []).joined(separator: "\n")
            XCTAssertTrue(frame.contains("Mulling"), "\(size)")
            XCTAssertTrue(frame.contains("enter confirm  •  q cancel"), "\(size)")
        }
    }

    func testControllerShowsAnAnimatedLoaderOnlyWhileRefreshing() {
        let start = Date(timeIntervalSince1970: 0)
        var clock = start
        let gate = DispatchSemaphore(value: 0)
        let config = MenuAutoRefresh(measure: { gate.wait(); return nil }, didRefresh: { _, _ in })
        let controller = MenuRefreshController(snapshot: snapshot([1], busy: 1, at: start), config: config, now: { clock })
        var focused = 0
        var selected: Set<Int> = []

        XCTAssertNil(controller.loaderLine)
        XCTAssertEqual(controller.pollMilliseconds, 200)
        XCTAssertTrue(controller.startRefresh())
        let first = controller.loaderLine
        XCTAssertNotNil(first)
        XCTAssertEqual(controller.pollMilliseconds, 100)

        clock = start.addingTimeInterval(0.2)
        XCTAssertTrue(controller.tick(focused: &focused, selected: &selected))    // redraw to animate
        XCTAssertNotEqual(controller.loaderLine, first)

        gate.signal()
        let deadline = Date().addingTimeInterval(5)
        while controller.isRefreshing && Date() < deadline {
            _ = controller.tick(focused: &focused, selected: &selected)
            Thread.sleep(forTimeInterval: 0.01)
        }
        XCTAssertNil(controller.loaderLine)
    }
}
