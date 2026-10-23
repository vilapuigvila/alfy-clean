import Foundation

/// Finds the Xcode DerivedData folders that belong to the user's iOS/Xcode projects, at runtime.
/// Only folders named exactly `DerivedData` are returned, and project-local ones only when a
/// `*.xcodeproj` or `*.xcworkspace` sits in their parent or grandparent folder.
enum DerivedDataDiscovery {
    static let defaultLocation = "~/Library/Developer/Xcode/DerivedData"
    static let defaultMaxDepth = 7
    static let prunedFolders = ["Library", ".Trash", ".git", "node_modules", "Pods", "Carthage", ".build"]

    /// Folders found once per run (the menu measures sizes and the cleanup deletes from the same list).
    static let found: [String] = find()

    /// - Parameters:
    ///   - searchRoot: where project-local folders are searched (the home folder by default).
    ///   - maxDepth: how many levels below `searchRoot` a `DerivedData` folder may be.
    ///   - defaultLocation: Xcode's default folder, included when it exists.
    ///   - customLocation: Xcode's `IDECustomDerivedDataLocation`, included when it is a folder inside the home folder.
    static func find(
        searchRoot: String = NSHomeDirectory(),
        maxDepth: Int = defaultMaxDepth,
        defaultLocation: String = DerivedDataDiscovery.defaultLocation,
        customLocation: String? = xcodeCustomLocation()
    ) -> [String] {
        var folders: [String] = []
        func add(_ path: String) {
            let standardized = (path as NSString).standardizingPath
            if !folders.contains(standardized) { folders.append(standardized) }
        }

        let defaultPath = expandTilde(defaultLocation)
        if isDirectory(defaultPath) { add(defaultPath) }
        if let custom = customLocation.map(expandTilde),
           custom.hasPrefix("/"),
           (custom as NSString).standardizingPath.hasPrefix(NSHomeDirectory() + "/"),
           isDirectory(custom) {
            add(custom)
        }

        for path in projectLocalFolders(in: searchRoot, maxDepth: maxDepth) {
            // A folder the default or custom location already covers (or sits inside) is deleted with it.
            if !folders.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { add(path) }
        }
        return folders
    }

    /// The `defaults` value Xcode stores when the user picks a custom DerivedData folder (nil when unset).
    static func xcodeCustomLocation() -> String? {
        let result = runProcess("/usr/bin/defaults", ["read", "com.apple.dt.Xcode", "IDECustomDerivedDataLocation"], errorOutput: .discarded)
        guard result.exitCode == 0 else { return nil }
        let value = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func projectLocalFolders(in root: String, maxDepth: Int) -> [String] {
        guard isDirectory(root) else { return [] }
        var arguments = [root, "-maxdepth", String(maxDepth), "("]
        for (index, name) in prunedFolders.enumerated() {
            if index > 0 { arguments.append("-o") }
            arguments += ["-name", name]
        }
        arguments += [")", "-prune", "-o", "-type", "d", "-name", "DerivedData", "-print", "-prune"]
        let result = runProcess("/usr/bin/find", arguments, errorOutput: .discarded)
        return result.output
            .split(separator: "\n")
            .map(String.init)
            .filter(belongsToXcodeProject)
    }

    /// True when the folder's parent or grandparent holds a `*.xcodeproj` or `*.xcworkspace`.
    private static func belongsToXcodeProject(_ folder: String) -> Bool {
        let parent = (folder as NSString).deletingLastPathComponent
        let grandparent = (parent as NSString).deletingLastPathComponent
        return [parent, grandparent].contains(where: holdsXcodeProject)
    }

    private static func holdsXcodeProject(_ folder: String) -> Bool {
        guard folder.count > 1,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return false }
        return entries.contains { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
