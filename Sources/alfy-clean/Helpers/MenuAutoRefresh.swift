//
//  MenuAutoRefresh.swift
//  alfy-clean
//
//  Keeps the open main menu up to date: it re-measures in the background every hour, or on `r`, and swaps
//  the rows in without disturbing ticks or focus. The pieces here are pure so they can be unit-tested; the
//  key loop in `Prompt` drives them.
//

import Foundation

/// One measured state of the main menu.
struct MenuSnapshot {
    /// `OptionInput.rawValue` per row, in the same order as `rows`.
    let ids: [Int]
    let rows: [CheckboxTableRow]
    /// The storage banner and title shown above the table.
    let question: String
    /// Capacity minus free space of the disk, in bytes.
    let busyBytes: UInt64
    /// When the measurement finished.
    let measuredAt: Date
}

struct MenuAutoRefresh {
    /// Seconds between the end of one measurement and the start of the next.
    var interval: TimeInterval = 3600
    /// Runs on a background thread: it must not write to the terminal. Nil when the measurement failed.
    let measure: () -> MenuSnapshot?
    /// Runs on the key-loop thread after the new snapshot replaced the old one.
    let didRefresh: (_ old: MenuSnapshot, _ new: MenuSnapshot) -> Void
}

/// A refresh starts once `interval` has passed since the last measurement ended, and never while one runs.
func isRefreshDue(lastMeasured: Date, now: Date, interval: TimeInterval, isRunning: Bool) -> Bool {
    !isRunning && now.timeIntervalSince(lastMeasured) >= interval
}

/// Moves ticks and focus from the old row order to the new one by option id, so they stay on the same options
/// when rows re-sort, appear or vanish. If the focused row is gone, focus clamps to a valid index.
func remap(selected: Set<Int>, focused: Int, from old: [Int], to new: [Int]) -> (selected: Set<Int>, focused: Int) {
    let newIndexByID = Dictionary(new.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    let kept = Set(selected.compactMap { old.indices.contains($0) ? newIndexByID[old[$0]] : nil })
    let lastIndex = max(new.count - 1, 0)
    if old.indices.contains(focused), let index = newIndexByID[old[focused]] {
        return (kept, index)
    }
    return (kept, min(max(focused, 0), lastIndex))
}

/// `Sizes refreshed — busy 412.3 GB (+3.2 GB since last)`; the delta is `−1.1 GB` or `±0 GB` when it shrank or
/// did not change. GB values use the same one-decimal format as the storage banner.
func refreshNotificationMessage(busyBefore: UInt64, busyAfter: UInt64) -> String {
    let delta: String
    if busyAfter >= busyBefore {
        let text = gigabytes(busyAfter - busyBefore)
        delta = text == "0.0 GB" ? "±0 GB" : "+\(text)"
    } else {
        let text = gigabytes(busyBefore - busyAfter)
        delta = text == "0.0 GB" ? "±0 GB" : "−\(text)"
    }
    return "Sizes refreshed — busy \(gigabytes(busyAfter)) (\(delta) since last)"
}

private func gigabytes(_ bytes: UInt64) -> String {
    String(format: "%.1f GB", Double(bytes) / 1_000_000_000)
}

/// The status shown at the end of the hint line.
func refreshStatusText(isRefreshing: Bool, updatedAt: Date, calendar: Calendar = .current) -> String {
    if isRefreshing { return "refreshing…" }
    let parts = calendar.dateComponents([.hour, .minute], from: updatedAt)
    return String(format: "updated %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
}

/// Hands one background result to the key-loop thread.
final class RefreshResultBox<Value> {
    private let lock = NSLock()
    private var value: Value?
    private var isFinished = false

    func put(_ newValue: Value?) {
        lock.lock()
        defer { lock.unlock() }
        value = newValue
        isFinished = true
    }

    /// `nil` while measuring; `.some(nil)` when the measurement failed; `.some(value)` when done.
    func take() -> Value?? {
        lock.lock()
        defer { lock.unlock() }
        return isFinished ? .some(value) : nil
    }
}

/// The state of a menu that refreshes itself, driven from the key loop.
final class MenuRefreshController {
    private(set) var snapshot: MenuSnapshot
    private let config: MenuAutoRefresh
    private var lastMeasured: Date
    private var box: RefreshResultBox<MenuSnapshot>?
    private let now: () -> Date

    init(snapshot: MenuSnapshot, config: MenuAutoRefresh, now: @escaping () -> Date = Date.init) {
        self.snapshot = snapshot
        self.config = config
        self.now = now
        self.lastMeasured = snapshot.measuredAt
    }

    var isRefreshing: Bool { box != nil }

    var status: String {
        refreshStatusText(isRefreshing: isRefreshing, updatedAt: snapshot.measuredAt)
    }

    /// Starts a refresh unless one is already running.
    @discardableResult
    func startRefresh() -> Bool {
        guard box == nil else { return false }
        let newBox = RefreshResultBox<MenuSnapshot>()
        box = newBox
        let measure = config.measure
        DispatchQueue.global(qos: .utility).async { newBox.put(measure()) }
        return true
    }

    /// Called on every wake of the key loop. Starts a due refresh and applies a finished one.
    /// Returns true when the frame changed.
    func tick(focused: inout Int, selected: inout Set<Int>) -> Bool {
        if let box, let finished = box.take() {
            self.box = nil
            lastMeasured = now()
            if let new = finished {
                let old = snapshot
                let mapped = remap(selected: selected, focused: focused, from: old.ids, to: new.ids)
                selected = mapped.selected
                focused = mapped.focused
                snapshot = new
                config.didRefresh(old, new)
            }
            return true
        }
        if isRefreshDue(lastMeasured: lastMeasured, now: now(), interval: config.interval, isRunning: isRefreshing) {
            return startRefresh()
        }
        return false
    }
}
