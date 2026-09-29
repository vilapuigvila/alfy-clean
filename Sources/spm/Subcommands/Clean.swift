//
//  File.swift
//  
//
//  Created by albert vila on 6/2/22.
//

import Foundation
import ArgumentParser

struct Clean: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: configMessage
    )
    
    private var isDone: Bool = false
    private var option: Int = 0 {
        didSet {
            if !(0..<OptionInput.allCases.count).contains(option) {
                fatalError("🤔 Value `\(option)` is not allowed")
            }
        }
    }
    
    // MARK: property wrappers -
    @Argument(help: "`all` string will delete all cases")
    private var all: String?
    
    @Argument(help: "`ndd` string will delete all cases")
    private var noDerivedData: String?
    
    @Option(name: .shortAndLong, help: "Select directory to delete his data!")
    private var delete: Int?
    
    @Flag(name: .shortAndLong, help: "Show extra logging for debugging purposes.")
    private var verbose: Bool = false
    
    // MARK: Main run -

    mutating func run() throws {
        guard try deleteAll() else {
            isDone = true
            return
        }

        let optionInputs = try pickOptions()

        if optionInputs.isEmpty {
            Print.withColor(.yellow, "Cancelled.")
            return
        }

        if shouldConfirmDelete(for: optionInputs) {
            let confirmDelete = Prompt().yesNo("⚠️  This will delete simulator data, archives, or build cache. Continue?")
            if !confirmDelete {
                Print.withColor(.yellow, "Cancelled.")
                return
            }
        }

        if optionInputs.contains(.noDerivedData) {
            try deleteAllUnlessDerivedData()

            if optionInputs.contains(.derivedData) {
                try runCleanup(.derivedData)
            }
        } else {
            for optionInput in optionInputs {
                try runCleanup(optionInput)
            }
        }

        isDone = true
        try printSystemStorage()
        Print.withColor(.green, "job done! 🍻")
    }
    
    // MARK: helpers -
    
    private func deleteAll() throws -> Bool {
        guard let all = all else {
            return true
        }
        guard all == "all" else {
            throw "Maybe you want to write `all` ?"
        }
        Print.withColor(.yellow, "all data...")

        let confirmDelete = Prompt().yesNo("⚠️  This will erase simulator data, keychains, and caches. Continue?")
        if !confirmDelete {
            Print.withColor(.yellow, "Cancelled.")
            return false
        }

        try deleteSimulatorsData()
        try deleteClonedSimulatorsDataAndUserDefaults()

        try OptionInput.allCases
            .filter { $0.rawValue >= 3 && $0.runsInAllCleanup }
            .forEach {
            do {
                try runCleanup($0)
            } catch {
                throw error
            }
        }
        try printSystemStorage()
        return false
    }
    
    private func deleteAllUnlessDerivedData() throws {
        var result = ShellResult(output: "", exitCode: 0)
        try runWithLoader("Cleaning iOS DeviceSupport") {
            result = shell("rm -Rf ~/Library/Developer/Xcode/iOS' 'DeviceSupport")
        }
        if !result.success {
            Print.withColor(.yellow, "iOS DeviceSupport deletion failed (may not exist)")
        }
        try deleteSimulatorsData()
        try deleteClonedSimulatorsDataAndUserDefaults()

        try OptionInput.allCases
            .filter { $0.rawValue >= 4 && $0.runsInAllCleanup }
            .forEach {
            do {
                try runCleanup($0)
            } catch {
                throw error
            }
        }
    }
    
    private mutating func pickOptions() throws -> [OptionInput] {
        if let shortOption = delete {
            option = shortOption
            return [try OptionInput(value: option)]
        } else {
            return Prompt().checkboxOptions(
                optionDisplays(),
                question: try checkboxMessage(),
                label: { $0.label }
            ).map { $0.input }
        }
    }

    private func shouldConfirmDelete(for optionInputs: [OptionInput]) -> Bool {
        optionInputs.contains(.simultorsData)
            || optionInputs.contains(.clonedSimulatorsData)
            || optionInputs.contains(.noDerivedData)
            || optionInputs.contains(.archives)
            || optionInputs.contains(.derivedData)
    }

    private func runCleanup(_ optionInput: OptionInput) throws {
        switch optionInput {
        case .noDerivedData:
            try deleteAllUnlessDerivedData()
            sendNotification(message: "All cleanup complete")
        case .simultorsData:
            try deleteSimulatorsData()
            sendNotification(message: "Simulators cleaned")
        case .clonedSimulatorsData:
            try deleteClonedSimulatorsDataAndUserDefaults()
            sendNotification(message: "Test devices cleaned")
        case .largeSystemFolders:
            try listLargeSystemFolders()
        case .deviceSupport:
            try deleteDeviceSupportVersions()
        case .simulatorRuntimes:
            try deleteSimulatorRuntimes()
        case .derivedData, .archives, .previews, .messagesAttachments, .microsoftTeamsCache, .documentationCache, .trash, .homebrewCache:
            let command = try optionInput.shellCommand()
            try runWithLoader("Cleaning \(optionInput.title)") {
                let result = shell(command)
                if !result.success {
                    throw "Command failed with exit code \(result.exitCode): \(command)"
                }
            }
            sendNotification(message: "\(optionInput.title) cleaned")
        }
    }

    private func deleteDeviceSupportVersions() throws {
        let root = (OptionInput.deviceSupportPath as NSString).expandingTildeInPath
        let folders = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
            .filter { !$0.hasPrefix(".") }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
            .map { (root as NSString).appendingPathComponent($0) }

        guard !folders.isEmpty else {
            Print.withColor(.yellow, "No iOS DeviceSupport versions found.")
            return
        }

        var usages: [String: DiskUsage] = [:]
        try runWithLoader("Measuring iOS DeviceSupport versions") {
            usages = DiskUsage.measure(paths: folders)
        }

        let selected = Prompt().checkboxOptions(
            folders,
            question: "\n\(Print.Color.boldGreen.rawValue)Select iOS DeviceSupport versions to delete\(Print.Color.reset.rawValue)",
            label: { folder in
                let usage = usages[folder] ?? .zero
                let prefix = usage.isPartial ? "~" : ""
                return "\((folder as NSString).lastPathComponent)  \(Print.Color.dim.rawValue)\(prefix)\(formatStorage(usage.bytes))\(Print.Color.reset.rawValue)"
            }
        )

        guard !selected.isEmpty else {
            Print.withColor(.yellow, "No versions selected.")
            return
        }

        let names = selected.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        let confirmDelete = Prompt().yesNo("⚠️  Delete \(names)? Xcode copies the files again the next time you plug in a device running that version.")
        guard confirmDelete else {
            Print.withColor(.yellow, "Cancelled.")
            return
        }

        for folder in selected {
            let name = (folder as NSString).lastPathComponent
            do {
                try runWithLoader("Deleting \(name)") {
                    try FileManager.default.removeItem(atPath: folder)
                }
                Print.withColor(.green, "Deleted \(name)")
            } catch {
                Print.withColor(.red, "Failed to delete \(name): \(error)")
            }
        }
        sendNotification(message: "iOS DeviceSupport cleaned")
    }

    private func deleteSimulatorRuntimes() throws {
        var runtimes: [SimulatorRuntime] = []
        try runWithLoader("Reading installed simulator runtimes") {
            runtimes = SimulatorRuntimes.list()
        }

        guard !runtimes.isEmpty else {
            Print.withColor(.yellow, "No deletable simulator runtimes found.")
            return
        }

        let selected = Prompt().checkboxOptions(
            runtimes,
            question: "\n\(Print.Color.boldGreen.rawValue)Select simulator runtimes to delete\(Print.Color.reset.rawValue)",
            label: { runtime in
                let lastUsed = runtime.lastUsedDay.map { "  •  last used \($0)" } ?? ""
                return "\(runtime.name)  \(Print.Color.dim.rawValue)\(formatStorage(runtime.sizeBytes))\(lastUsed)\(Print.Color.reset.rawValue)"
            }
        )

        guard !selected.isEmpty else {
            Print.withColor(.yellow, "No runtimes selected.")
            return
        }

        let names = selected.map { $0.name }.joined(separator: ", ")
        let confirmDelete = Prompt().yesNo("⚠️  Delete \(names)? Simulators using them become unavailable until you download the runtime again (Xcode ▸ Settings ▸ Components).")
        guard confirmDelete else {
            Print.withColor(.yellow, "Cancelled.")
            return
        }

        for runtime in selected {
            var result = ShellResult(output: "", exitCode: 0)
            try runWithLoader("Deleting \(runtime.name)") {
                result = SimulatorRuntimes.delete(runtime)
            }
            if result.success {
                Print.withColor(.green, "Deleted \(runtime.name)")
            } else {
                Print.withColor(.red, "Failed to delete \(runtime.name): \(result.output)")
            }
        }
        sendNotification(message: "Simulator runtimes cleaned")
    }

    private func listLargeSystemFolders() throws {
        var output = ""

        try runWithLoader("Scanning system folders larger than 5 GB (this may take a moment)") {
            output = SystemScanner.listLargeFolders()
        }

        Print.withColor(.boldGreen, "Deepest folders larger than 5 GB")
        if output.isEmpty {
            Print.withColor(.yellow, "No folders larger than 5 GB found in scanned locations.")
        } else {
            Print.withColor(.cyan, "Showing largest 50 deepest folders (parent folders excluded):\n")
            customPrint(output)
        }

        sendScanCompletionNotification()

        try deleteSafeLargeFolders(SystemScanner.safeToDelete(from: output))
    }

    private func deleteSafeLargeFolders(_ folders: [SystemScanner.LargeFolder]) throws {
        guard !folders.isEmpty else {
            Print.withColor(.yellow, "\nNone of these folders is on the safe-to-delete list.")
            return
        }

        let selected = Prompt().checkboxOptions(
            folders,
            question: "\n\(Print.Color.boldGreen.rawValue)Safe to delete: select folders\(Print.Color.reset.rawValue)",
            label: { folder in
                "\(String(format: "%.1f GB", folder.gigabytes))  \(folder.path)  \(Print.Color.dim.rawValue)\(folder.note)\(Print.Color.reset.rawValue)"
            }
        )

        guard !selected.isEmpty else {
            Print.withColor(.yellow, "No folders selected.")
            return
        }

        let total = selected.reduce(0) { $0 + $1.gigabytes }
        let list = selected.map { "  \($0.path)" }.joined(separator: "\n")
        let confirmDelete = Prompt().yesNo("⚠️  Delete \(selected.count) folder(s), \(String(format: "%.1f GB", total))?\n\(list)")
        guard confirmDelete else {
            Print.withColor(.yellow, "Cancelled.")
            return
        }

        for folder in selected {
            // Re-check against the allowlist right before deleting.
            guard SystemScanner.safeDeleteNote(for: folder.path) != nil else {
                Print.withColor(.red, "Skipped \(folder.path): not on the safe-to-delete list")
                continue
            }
            do {
                try runWithLoader("Deleting \(folder.path)") {
                    try FileManager.default.removeItem(atPath: folder.path)
                }
                Print.withColor(.green, "Deleted \(folder.path)")
            } catch {
                Print.withColor(.red, "Failed to delete \(folder.path): \(error)")
            }
        }
        sendNotification(message: "Large folders cleaned")
    }
    
    private func deleteSimulatorsData() throws {
        guard #available(macOS 10.12, *) else {
            throw "Your macOS version must be 10.12 or higher"
        }

        var result = ShellResult(output: "", exitCode: 0)
        try runWithLoader("Shutting down all simulators") {
            result = shell("xcrun simctl shutdown all")
        }
        if !result.success {
            Print.withColor(.yellow, "Shutdown had issues (simulators may already be off)")
        }

        try runWithLoader("Erasing all simulators") {
            result = shell("xcrun simctl erase all")
            guard result.success else {
                throw "Failed to erase simulators: \(result.output)"
            }
        }

        try runWithLoader("Clearing CoreSimulator caches") {
            result = shell("rm -Rf ~/Library/Developer/CoreSimulator/Caches")
            if !result.success {
                throw "Failed to clear CoreSimulator caches"
            }
        }
    }
    
    private func deleteClonedSimulatorsDataAndUserDefaults() throws {
        guard #available(macOS 10.12, *) else {
            throw "Your macOS version must be 10.12 or higher"
        }

        let fileManager = FileManager.default
        let testDevicesPath = "~/Library/Developer/XCTestDevices"
        let previewDevicesPath = "~/Library/Developer/XCPGDevices"

        if fileManager.fileExists(atPath: (testDevicesPath as NSString).expandingTildeInPath) {
            var result = ShellResult(output: "", exitCode: 0)
            try runWithLoader("Deleting XCTestDevices") {
                result = shell("xcrun simctl --set \(testDevicesPath) delete all")
            }
            if !result.success {
                Print.withColor(.yellow, "XCTestDevices deletion had issues (may already be empty)")
            }
        } else {
            Print.withColor(.blue, "XCTestDevices not found, skipping")
        }

        if fileManager.fileExists(atPath: (previewDevicesPath as NSString).expandingTildeInPath) {
            var result = ShellResult(output: "", exitCode: 0)
            try runWithLoader("Deleting XCPGDevices previews") {
                result = shell("xcrun simctl --set \(previewDevicesPath) delete all")
            }
            if !result.success {
                Print.withColor(.yellow, "XCPGDevices deletion had issues (may already be empty)")
            }
        } else {
            Print.withColor(.blue, "XCPGDevices not found, skipping")
        }
    }

    private func runWithLoader(_ message: String, _ work: () throws -> Void) throws {
        let loader = TerminalLoader(message)
        loader.start()

        do {
            try work()
            loader.succeed()
        } catch {
            loader.fail()
            throw error
        }
    }

    private func printSystemStorage() throws {
        customPrint("")
        customPrint(try systemStorageMessage())
    }

    /// Homebrew's terminal-notifier, looked up by absolute path so a broken shim earlier on PATH
    /// (e.g. the Intel-only rbenv gem) can't shadow it.
    private static let terminalNotifierPaths = [
        "/opt/homebrew/bin/terminal-notifier",
        "/usr/local/bin/terminal-notifier"
    ]

    /// Sends a macOS system notification with a custom message and sound.
    /// Prefers terminal-notifier so tapping the notification activates the terminal app that ran avp
    /// (its bundle ID comes from `__CFBundleIdentifier`); falls back to osascript, whose notifications
    /// open Script Editor on tap.
    /// Returns immediately without waiting for user interaction.
    /// Silently ignores all errors (notifier unavailable, permission denied, etc.)
    /// since notifications are non-critical to the main task.
    private func sendNotification(message: String) {
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe

        if let notifier = Self.terminalNotifierPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            var arguments = ["-title", "avp", "-message", message, "-sound", "Glass"]
            if let terminalBundleID = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] {
                arguments += ["-activate", terminalBundleID]
            }
            task.arguments = arguments
            task.launchPath = notifier
        } else {
            let script = "display notification \"\(message)\" with title \"avp\" sound name \"Glass\""
            task.arguments = ["-e", script]
            task.launchPath = "/usr/bin/osascript"
        }

        do {
            try task.run()
            task.waitUntilExit()
            // Notification sent; ignore result (success or failure)
        } catch {
            // osascript not available or other error
            // Silently continue; notification failure should not interrupt the user's task
        }
    }

    /// Sends a notification for scan completion (used by listLargeSystemFolders).
    private func sendScanCompletionNotification() {
        sendNotification(message: "Folder scan complete")
    }
}

// MARK: Options -

extension Clean {
    
    enum OptionInput: Int, CaseIterable {
        // Low-risk: auto-regenerate on next use
        case noDerivedData                  // All except DerivedData
        case simultorsData                  // iOS simulator runtimes & device data
        case clonedSimulatorsData           // Cloned devices for tests & Previews
        case derivedData                    // Build artifacts & cache (slow rebuild)
        case archives                       // ⚠️ Old IPA builds (cannot regenerate)
        case previews                       // Xcode Preview cache
        case messagesAttachments            // macOS Messages attachments
        case microsoftTeamsCache            // Microsoft Teams local cache
        case documentationCache             // QuickHelp docs (regenerates on access)
        case trash                          // System trash bin
        case homebrewCache                  // Homebrew downloads & old versions (brew cleanup)
        case deviceSupport                  // Per-version device symbols (re-copied on device plug-in)
        case simulatorRuntimes              // ⚠️ Installed runtimes (re-download to restore)
        case largeSystemFolders             // Scan for large system folders (info only)
        init(value: Int) throws {
            switch value {
            case 0: self = .noDerivedData
            case 1: self = .simultorsData
            case 2: self = .clonedSimulatorsData
            case 3: self = .derivedData
            case 4: self = .archives
            case 5: self = .previews
            case 6: self = .messagesAttachments
            case 7: self = .microsoftTeamsCache
            case 8: self = .documentationCache
            case 9: self = .trash
            case 10: self = .homebrewCache
            case 11: self = .deviceSupport
            case 12: self = .simulatorRuntimes
            case 13: self = .largeSystemFolders
            default: throw "Manage this case \(value)"
            }
        }
        init?(rawValue: Int) { fatalError("use `init(value: Int) throws`") }

        var title: String {
            switch self {
            case .derivedData: return "🔥 🧨 Derived Data"
            case .noDerivedData: return "🥳 All, -> derived data excluded"
            case .simultorsData: return "Simulators Data & ⚠️  Keychain"
            case .clonedSimulatorsData: return "Cloned simulators (tests & Previews)"
            case .archives: return "Archives"
            case .previews: return "Previews"
            case .messagesAttachments: return "📩 Open Messages Attachments folder"
            case .microsoftTeamsCache: return "Teams microsoft Cache"
            case .documentationCache: return "QuickHelp Documentation Cache"
            case .trash: return "🗑️ System Trash"
            case .homebrewCache: return "🍺 Homebrew Cache"
            case .deviceSupport: return "📱 iOS DeviceSupport versions"
            case .simulatorRuntimes: return "📦 Simulator runtimes"
            case .largeSystemFolders: return "🔎 List system folders > 5 GB"
            }
        }

        var runsInAllCleanup: Bool {
            self != .largeSystemFolders && self != .simulatorRuntimes && self != .homebrewCache && self != .deviceSupport
        }

        static let deviceSupportPath = "~/Library/Developer/Xcode/iOS DeviceSupport"

        var estimatedPaths: [String] {
            switch self {
            case .noDerivedData:
                return [
                    "~/Library/Developer/Xcode/iOS DeviceSupport",
                    "~/Library/Developer/CoreSimulator/Devices",
                    "~/Library/Developer/CoreSimulator/Caches",
                    "~/Library/Developer/XCTestDevices",
                    "~/Library/Developer/XCPGDevices",
                    "~/Library/Developer/Xcode/Archives",
                    "~/Library/Developer/Xcode/UserData/Previews",
                    "~/Library/Developer/Xcode/DocumentationCache",
                    "~/Library/Messages/Attachments",
                    "~/Library/Application Support/Microsoft/Teams",
                    "~/.Trash"
                ]
            case .simultorsData:
                return [
                    "~/Library/Developer/CoreSimulator/Devices",
                    "~/Library/Developer/CoreSimulator/Caches"
                ]
            case .clonedSimulatorsData:
                return [
                    "~/Library/Developer/XCTestDevices",
                    "~/Library/Developer/XCPGDevices"
                ]
            case .derivedData:
                return ["~/Library/Developer/Xcode/DerivedData"]
            case .archives:
                return ["~/Library/Developer/Xcode/Archives"]
            case .previews:
                return ["~/Library/Developer/Xcode/UserData/Previews"]
            case .messagesAttachments:
                return ["~/Library/Messages/Attachments"]
            case .microsoftTeamsCache:
                return ["~/Library/Application Support/Microsoft/Teams"]
            case .documentationCache:
                return ["~/Library/Developer/Xcode/DocumentationCache"]
            case .trash:
                return ["~/.Trash"]
            case .homebrewCache:
                return ["~/Library/Caches/Homebrew"]
            case .deviceSupport:
                return [Self.deviceSupportPath]
            case .simulatorRuntimes, .largeSystemFolders:
                return []
            }
        }
        
        func shellCommand() throws -> String {
            switch self {
            case .noDerivedData: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .simultorsData: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .clonedSimulatorsData: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .derivedData: return "rm -rf ~/Library/Developer/Xcode/DerivedData"
            case .archives: return "rm -rf ~/Library/Developer/Xcode/Archives"
            case .previews: return "rm -rf ~/Library/Developer/Xcode/UserData/Previews"
            case .messagesAttachments: return  "open ~/Library/Messages/Attachments"
            case .microsoftTeamsCache: return "rm -rf ~/Library/Application' 'Support/Microsoft/Teams"
            case .documentationCache: return "rm -Rf ~/Library/Developer/Xcode/DocumentationCache"
            case .trash: return "if [ -d ~/.Trash ]; then find ~/.Trash -mindepth 1 -maxdepth 1 -exec rm -rf {} +; fi"
            case .homebrewCache: return "PATH=\"/opt/homebrew/bin:/usr/local/bin:$PATH\" brew cleanup --prune=all"
            case .deviceSupport: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .simulatorRuntimes: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .largeSystemFolders: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            }
        }
    }
}

// MARK: Text descriptions -

private extension Clean {
    struct OptionDisplay {
        let input: OptionInput
        let label: String
    }

    func optionDisplays() -> [OptionDisplay] {
        let estimatesByPath = diskUsageEstimatesByPath()
        let runtimesBytes = SimulatorRuntimes.list().reduce(0) { $0 + $1.sizeBytes }

        return OptionInput.allCases.map { optionInput in
            if optionInput == .largeSystemFolders {
                return OptionDisplay(
                    input: optionInput,
                    label: "\(optionInput.title)  \(Print.Color.dim.rawValue)scan only\(Print.Color.reset.rawValue)"
                )
            }

            if optionInput == .simulatorRuntimes {
                return OptionDisplay(
                    input: optionInput,
                    label: "\(optionInput.title)  \(Print.Color.dim.rawValue)pick which  •  up to \(formatStorage(runtimesBytes))\(Print.Color.reset.rawValue)"
                )
            }

            let estimate = estimatedFreeSpace(for: optionInput, estimatesByPath: estimatesByPath)
            let prefix = estimate.isPartial ? "~" : ""

            if optionInput == .deviceSupport {
                return OptionDisplay(
                    input: optionInput,
                    label: "\(optionInput.title)  \(Print.Color.dim.rawValue)pick which  •  up to \(prefix)\(formatStorage(estimate.bytes))\(Print.Color.reset.rawValue)"
                )
            }
            let estimateText = "\(Print.Color.dim.rawValue)will free \(prefix)\(formatStorage(estimate.bytes))\(Print.Color.reset.rawValue)"
            return OptionDisplay(
                input: optionInput,
                label: "\(optionInput.title)  \(estimateText)"
            )
        }
    }

    func checkboxMessage() throws -> String {
        let systemStorage = try systemStorageMessage()
        return """

\(systemStorage)

\(Print.Color.boldGreen.rawValue)Select folders to clean\(Print.Color.reset.rawValue)
"""
    }

    func systemStorageMessage() throws -> String {
        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            guard let capacity = attributes[.systemSize] as? NSNumber,
                  let free = attributes[.systemFreeSize] as? NSNumber else {
                throw "Missing filesystem size attributes"
            }

            let busy = capacity.uint64Value - free.uint64Value
            return storageFrame(
                capacity: formatGB(capacity.uint64Value),
                busy: formatGB(busy)
            )
        } catch {
            throw "Unable to read system storage info: \(error)"
        }
    }

    typealias DiskUsageEstimate = DiskUsage

    func diskUsageEstimatesByPath() -> [String: DiskUsageEstimate] {
        let uniquePaths = Array(Set(OptionInput.allCases.flatMap { $0.estimatedPaths }))
        let loader = TerminalLoader("Measuring folder sizes (this may take a minute)")
        loader.start()
        let result = DiskUsage.measure(paths: uniquePaths)
        loader.succeed()
        return result
    }

    func estimatedFreeSpace(
        for optionInput: OptionInput,
        estimatesByPath: [String: DiskUsageEstimate]
    ) -> DiskUsageEstimate {
        optionInput.estimatedPaths.reduce(.zero) { total, path in
            let estimate = estimatesByPath[path] ?? .zero
            return DiskUsageEstimate(
                bytes: total.bytes + estimate.bytes,
                isPartial: total.isPartial || estimate.isPartial
            )
        }
    }

    func storageFrame(capacity: String, busy: String) -> String {
        let content = "System storage  capacity: \(capacity)  •  busy: \(busy)"
        let horizontal = String(repeating: "─", count: content.count + 2)
        let coloredContent = """
\(Print.Color.boldGreen.rawValue)System storage\(Print.Color.reset.rawValue)  \(Print.Color.cyan.rawValue)capacity:\(Print.Color.reset.rawValue) \(Print.Color.white.rawValue)\(capacity)\(Print.Color.reset.rawValue)  \(Print.Color.dim.rawValue)•\(Print.Color.reset.rawValue)  \(Print.Color.yellow.rawValue)busy:\(Print.Color.reset.rawValue) \(Print.Color.magenta.rawValue)\(busy)\(Print.Color.reset.rawValue)
"""

        return """
╭\(horizontal)╮
│ \(coloredContent) │
╰\(horizontal)╯
"""
    }

    func formatGB(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_000_000_000
        return String(format: "%.1f GB", gb)
    }

    func formatStorage(_ bytes: UInt64) -> String {
        DiskUsage.format(bytes)
    }

    static var foldersName: String {
        return Cache.CacheFolder
            .allCases
            .map { $0.rawValue }.joined(separator: " or ")
    }

    static var configMessage: String {
"""
Delete shit data of your developer folder 🚮,
folders list:
\(foldersName) 🥳
"""
    }
    
}
