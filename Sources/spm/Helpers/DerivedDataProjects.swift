import Foundation

/// One project folder inside a DerivedData folder (`<Name>-<hash>`), as shown in the `avp clean` picker.
struct DerivedDataProject: Equatable {
    let path: String
    /// The project or workspace Xcode built, from `info.plist`; nil when the plist is missing or unreadable.
    let workspacePath: String?
    var bytes: UInt64 = 0
    var isPartial = false

    var name: String { (path as NSString).lastPathComponent }

    /// True only when `info.plist` named a workspace and that path no longer exists.
    /// A missing or unreadable plist is "unknown", never an orphan: a false orphan would be deleted unthinkingly.
    var isOrphan: Bool {
        guard let workspacePath else { return false }
        return !FileManager.default.fileExists(atPath: workspacePath)
    }
}

enum DerivedDataProjects {
    /// The only shared (not per-project) folders the "shared caches" row may delete.
    static let sharedCacheNames = ["ModuleCache.noindex", "CompilationCache.noindex", "SDKExplicitPrecompiledModules"]

    /// `WorkspacePath` from a DerivedData project's `info.plist`; nil when missing, unreadable or not a string.
    static func workspacePath(infoPlist: String) -> String? {
        guard let data = FileManager.default.contents(atPath: infoPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let dictionary = plist as? [String: Any],
              let path = dictionary["WorkspacePath"] as? String,
              path.hasPrefix("/") else { return nil }
        return path
    }

    /// Project folders directly inside `folder`: real directories (never symlinks) that hold an `info.plist`
    /// or are named `<Name>-<28 letters>`; shared caches and other tool folders are left out.
    /// Sizes are not measured here.
    static func projects(in folder: String) -> [DerivedDataProject] {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [] }
        return entries.sorted().compactMap { entry in
            guard !sharedCacheNames.contains(entry), !entry.hasSuffix(".noindex") else { return nil }
            let path = folder + "/" + entry
            guard isRealDirectory(path) else { return nil }
            let plist = path + "/info.plist"
            guard FileManager.default.fileExists(atPath: plist) || entry.range(of: "-[a-z]{28}$", options: .regularExpression) != nil
            else { return nil }
            return DerivedDataProject(path: path, workspacePath: workspacePath(infoPlist: plist))
        }
    }

    /// Existing shared-cache folders inside `folder`, in the order of `sharedCacheNames`.
    static func sharedCaches(in folder: String) -> [String] {
        sharedCacheNames.map { folder + "/" + $0 }.filter(isRealDirectory)
    }

    /// Fills in sizes and returns the projects biggest first.
    static func measured(_ projects: [DerivedDataProject]) -> [DerivedDataProject] {
        let usages = DiskUsage.measure(paths: projects.map { $0.path })
        return projects.map { project in
            var copy = project
            let usage = usages[project.path] ?? .zero
            copy.bytes = usage.bytes
            copy.isPartial = usage.isPartial
            return copy
        }.sorted { $0.bytes > $1.bytes }
    }

    /// True when `path` is `root` or sits inside it. Compares whole path components, so `/a/wt-other`
    /// is not inside `/a/wt`.
    static func isInside(_ path: String, root: String) -> Bool {
        let path = (path as NSString).standardizingPath
        let root = (root as NSString).standardizingPath
        guard root != "/", !root.isEmpty else { return false }
        return path == root || path.hasPrefix(root + "/")
    }

    /// Projects whose `WorkspacePath` is inside `root` (also tried with `root` resolved through symlinks).
    static func projects(_ projects: [DerivedDataProject], inside root: String) -> [DerivedDataProject] {
        let resolved = URL(fileURLWithPath: root).resolvingSymlinksInPath().path
        return projects.filter { project in
            guard let workspace = project.workspacePath else { return false }
            return isInside(workspace, root: root) || isInside(workspace, root: resolved)
        }
    }

    /// Keeps only paths that are safe to delete: a direct child of one of `allowedFolders` (never a symlink)
    /// or one of those folders themselves.
    static func deletable(_ paths: [String], allowedFolders: [String]) -> [String] {
        let folders = allowedFolders.map { ($0 as NSString).standardizingPath }
        return paths.filter { raw in
            let path = (raw as NSString).standardizingPath
            if folders.contains(path) { return true }
            let parent = (path as NSString).deletingLastPathComponent
            return folders.contains(parent) && isRealDirectory(path)
        }
    }

    /// Free-space change in bytes: positive when space was freed, zero or negative when nothing was
    /// (other activity can use the space while a cleanup runs).
    static func freedBytes(before: UInt64, after: UInt64) -> Int64 {
        let (b, a) = (Int64(clamping: before), Int64(clamping: after))
        return a - b
    }

    static func freedSpaceMessage(before: UInt64, after: UInt64) -> String {
        let freed = freedBytes(before: before, after: after)
        if freed > 0 { return "Freed \(DiskUsage.format(UInt64(freed))) of disk space (free space went \(DiskUsage.format(before)) → \(DiskUsage.format(after)))" }
        if freed == 0 { return "No change in free disk space (\(DiskUsage.format(after)) free)" }
        return "No space freed: free disk space went down by \(DiskUsage.format(UInt64(-freed))) (something else used it meanwhile)"
    }

    /// Free bytes on the volume holding the home folder; nil when it can't be read.
    static func freeSpace() -> UInt64? {
        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        return (attributes?[.systemFreeSize] as? NSNumber)?.uint64Value
    }

    private static func isRealDirectory(_ path: String) -> Bool {
        guard let type = try? FileManager.default.attributesOfItem(atPath: path)[.type] as? FileAttributeType else { return false }
        return type == .typeDirectory
    }
}
