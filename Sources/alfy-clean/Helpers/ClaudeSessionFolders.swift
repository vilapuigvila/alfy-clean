import Foundation

/// The `claude-<uid>` folders Claude Code keeps in `/private/tmp` (scratchpads, task output, pasted images of its
/// sessions), offered in the AI section of `alfy-clean clean`. Only direct children of the root are ever listed or
/// deleted, only real folders (never a symlink) owned by the current user, so a swapped-in link or somebody else's
/// folder can't redirect a delete.
enum ClaudeSessionFolders {
    static let defaultRoot = "/private/tmp"
    static let prefix = "claude-"
    /// Shown in the info panel and in the confirmation.
    static let warning = "Close every Claude Code session first. Deleting these while one is running can lose its session data."

    /// The matching folders directly inside `root`, sorted by path.
    static func folders(in root: String = defaultRoot, ownedBy uid: uid_t = getuid()) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return names
            .filter { $0.hasPrefix(prefix) && $0.count > prefix.count }
            .map { (root as NSString).appendingPathComponent($0) }
            .filter { isOwnedRealDirectory($0, uid: uid) }
            .sorted()
    }

    /// Checked again right before deleting: still a direct, real, own folder of `root` with the right name.
    static func isSafeToDeleteNow(_ path: String, root: String = defaultRoot, ownedBy uid: uid_t = getuid()) -> Bool {
        let standardized = (path as NSString).standardizingPath
        let name = (standardized as NSString).lastPathComponent
        guard name.hasPrefix(prefix), name.count > prefix.count else { return false }

        let parent = URL(fileURLWithPath: standardized).deletingLastPathComponent().resolvingSymlinksInPath().path
        let realRoot = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        return parent == realRoot && isOwnedRealDirectory(standardized, uid: uid)
    }

    /// How many Claude Code processes of this user are running now (the process is named `claude`).
    static func runningSessionCount(ownedBy uid: uid_t = getuid()) -> Int {
        let result = runProcess("/usr/bin/pgrep", ["-x", "-u", String(uid), "claude"])
        guard result.success else { return 0 }
        return result.output.split(whereSeparator: \.isNewline).count
    }

    /// Why the folders must not be deleted now, or nil when no Claude Code process is running.
    static func refusal(running: Int) -> String? {
        guard running > 0 else { return nil }
        let processes = running == 1 ? "1 Claude Code process is" : "\(running) Claude Code processes are"
        return "Not deleted: \(processes) running. Close every Claude Code session (also the terminal you may have started it from), then try again."
    }

    private static func isOwnedRealDirectory(_ path: String, uid: uid_t) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeDirectory,
              let owner = attributes[.ownerAccountID] as? NSNumber else { return false }
        return owner.uint32Value == uid
    }
}
