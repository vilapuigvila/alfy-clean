import Foundation

/// The big folders directly inside `~/Library/Caches`, offered one by one in `avp clean`.
/// Only direct children are ever listed or deleted, and never a symlink, so a swapped-in link
/// can't redirect a delete somewhere else.
enum UserCaches {
    static let defaultRoot = "~/Library/Caches"
    /// Finder-style decimal units, like the sizes shown in the menu: 1 GB.
    static let minimumBytes: UInt64 = 1_000_000_000
    /// Folders that have a row of their own, so they aren't offered twice (the footer total would count them twice).
    static let foldersWithOwnRow: Set<String> = ["org.swift.swiftpm", "Homebrew"]

    /// Real (non-symlink) folders directly inside `root`, without the ones that have their own row.
    static func rootFolders(in root: String = expandTilde(defaultRoot)) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return names
            .filter { !foldersWithOwnRow.contains($0) }
            .map { (root as NSString).appendingPathComponent($0) }
            .filter { isRealDirectory($0) }
            .sorted()
    }

    /// The folders at or over the minimum size, biggest first. `usages` is keyed by the same paths `rootFolders` returns.
    static func largeFolders(_ folders: [String], usages: [String: DiskUsage], minimumBytes: UInt64 = minimumBytes) -> [(path: String, usage: DiskUsage)] {
        folders
            .map { (path: $0, usage: usages[$0] ?? .zero) }
            .filter { $0.usage.bytes >= minimumBytes }
            .sorted { $0.usage.bytes > $1.usage.bytes }
    }

    /// Checked again right before deleting: still a direct, real folder of `root`, not one with its own row.
    static func isSafeToDeleteNow(_ path: String, root: String = expandTilde(defaultRoot)) -> Bool {
        let standardized = (path as NSString).standardizingPath
        let name = (standardized as NSString).lastPathComponent
        guard !name.isEmpty, name != ".", name != "..", !foldersWithOwnRow.contains(name) else { return false }

        let parent = URL(fileURLWithPath: standardized).deletingLastPathComponent().resolvingSymlinksInPath().path
        let realRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        return parent == realRoot && isRealDirectory(standardized)
    }

    private static func isRealDirectory(_ path: String) -> Bool {
        let type = (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType
        return type == .typeDirectory
    }
}
