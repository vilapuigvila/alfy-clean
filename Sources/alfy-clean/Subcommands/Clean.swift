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
    /// The Derived Data folders to delete, once the user has picked from the menu. Nil means all that were found.
    private var derivedDataFolders: [String]?
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
        TerminalFocus.captureCurrentTerminal()
        guard try deleteAll() else {
            isDone = true
            return
        }

        // The interactive menu comes back after each job, until it is left empty (Esc / q).
        // `-d <n>` is a one-shot, so it runs once.
        let isInteractive = delete == nil
        repeat {
            derivedDataFolders = nil
            guard try runMenuJob() else { return }
        } while isInteractive
    }

    /// One pass of menu → confirm → clean. False when nothing ran (nothing picked, or declined).
    private mutating func runMenuJob() throws -> Bool {

        let optionInputs = try pickOptions()

        if optionInputs.isEmpty {
            Print.withColor(.yellow, "Cancelled.")
            return false
        }

        let needConfirmation = optionInputs.filter { $0.needsConfirmation }
        if !needConfirmation.isEmpty {
            let confirmDelete = Prompt().yesNo("⚠️  This permanently deletes:\n\(bulleted(deletionItems(for: needConfirmation)))\nContinue?")
            if !confirmDelete {
                Print.withColor(.yellow, "Cancelled.")
                return false
            }
        }

        let freeBefore = DerivedDataProjects.freeSpace()
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
        printFreedSpace(since: freeBefore)
        try printSystemStorage()
        Print.withColor(.green, "job done! 🍻")
        return true
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

        let confirmDelete = Prompt().yesNo("⚠️  `all` permanently deletes:\n\(bulleted(allCleanupItems(includingDerivedData: true)))\nContinue?")
        if !confirmDelete {
            Print.withColor(.yellow, "Cancelled.")
            return false
        }

        let freeBefore = DerivedDataProjects.freeSpace()
        try deleteSimulatorsData()
        try deleteClonedSimulatorsDataAndUserDefaults()

        try OptionInput.allCleanupOptions(includingDerivedData: true)
            .forEach {
            do {
                try runCleanup($0)
            } catch {
                throw error
            }
        }
        printFreedSpace(since: freeBefore)
        try printSystemStorage()
        return false
    }
    
    private func deleteAllUnlessDerivedData() throws {
        var result = ShellResult(output: "", exitCode: 0)
        try runWithLoader("Cleaning iOS DeviceSupport") {
            result = runProcess("/bin/rm", ["-rf", expandTilde(OptionInput.deviceSupportPath)])
        }
        if !result.success {
            Print.withColor(.yellow, "iOS DeviceSupport deletion failed (may not exist)")
        }
        try deleteSimulatorsData()
        try deleteClonedSimulatorsDataAndUserDefaults()

        try OptionInput.allCleanupOptions(includingDerivedData: false)
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
            let entries = menuEntries()
            // Measuring sizes can take a while: tell the user the menu is ready.
            sendNotification(message: "Choose what to clean")
            let picked = Prompt().checkboxTable(entries.map { $0.row }, question: try checkboxMessage())
            // Run in menu-definition order, not size order.
            let inputs = picked.map { entries[$0].input }.sorted { $0.rawValue < $1.rawValue }
            if inputs.contains(.derivedData) {
                derivedDataFolders = try pickDerivedDataFolders()
            }
            return inputs
        }
    }

    /// What the selected options delete, one line each. The "all except DerivedData" option is expanded
    /// so the prompt names everything it removes.
    private func deletionItems(for optionInputs: [OptionInput]) -> [String] {
        var items: [String] = []
        for optionInput in optionInputs {
            let lines = optionInput == .noDerivedData
                ? allCleanupItems(includingDerivedData: false)
                : titleLines(for: optionInput)
            items += lines.filter { !items.contains($0) }
        }
        return items
    }

    /// Everything an "all" cleanup removes, in the order it runs.
    private func allCleanupItems(includingDerivedData: Bool) -> [String] {
        var items: [String] = []
        if !includingDerivedData {
            items.append("📱 iOS DeviceSupport (all versions)")
        }
        items.append("⚠️  All simulators erased (apps, logins, keychains) + CoreSimulator caches")
        items.append(OptionInput.clonedSimulatorsData.title)
        items += OptionInput.allCleanupOptions(includingDerivedData: includingDerivedData)
            .filter { $0.needsConfirmation }
            .flatMap { titleLines(for: $0) }
        return items
    }

    /// The option's title, followed by the folders it will delete when they are found at runtime.
    private func titleLines(for optionInput: OptionInput) -> [String] {
        guard optionInput == .derivedData else { return [optionInput.title] }
        return [optionInput.title] + (derivedDataFolders ?? DerivedDataDiscovery.found).map { "    \($0.terminalSafe)" }
    }

    private func bulleted(_ items: [String]) -> String {
        items.map { $0.hasPrefix(" ") ? "  \($0)" : "  • \($0)" }.joined(separator: "\n")
    }

    private func runCleanup(_ optionInput: OptionInput) throws {
        switch optionInput {
        case .noDerivedData:
            try deleteAllUnlessDerivedData()
            sendNotification(message: "All cleanup complete")
        case .simultorsData:
            try eraseSelectedSimulators()
        case .clonedSimulatorsData:
            try deleteClonedSimulatorsDataAndUserDefaults()
            sendNotification(message: "Test devices cleaned")
        case .largeSystemFolders:
            try listLargeSystemFolders()
        case .deviceSupport:
            try deleteDeviceSupportVersions()
        case .simulatorRuntimes:
            try deleteSimulatorRuntimes()
        case .userCaches:
            try deleteLargeCacheFolders()
        case .deleteSimulators:
            try deleteSelectedSimulators()
        case .derivedData:
            try deleteDerivedData(derivedDataFolders ?? DerivedDataDiscovery.found)
            sendNotification(message: "\(optionInput.title) cleaned")
        case .archives, .swiftPMCache, .previews, .messagesAttachments, .microsoftTeamsCache, .documentationCache, .trash, .homebrewCache, .maestroTests, .claudeJobsTmp:
            let command = try optionInput.command()
            // Nothing to clean (e.g. no Trash or jobs folder yet) counts as done, like an `rm -rf` of a missing folder.
            if let required = command.requiredFolder,
               !FileManager.default.fileExists(atPath: required) {
                break
            }
            if optionInput == .trash, Self.isTrashUnreadable {
                throw Self.trashAccessMessage
            }
            try runWithLoader("Cleaning \(optionInput.title)") {
                let result = runProcess(command.executable, command.arguments, searchPath: command.searchPath)
                if !result.success {
                    throw "Command failed with exit code \(result.exitCode): \(command.display)"
                }
            }
            sendNotification(message: "\(optionInput.title) cleaned")
        }
    }

    /// What the user can tick in the Derived Data picker.
    private enum DerivedDataChoice {
        case project(DerivedDataProject)
        case sharedCaches(folder: String, paths: [String], bytes: UInt64)
        case wholeFolder(path: String, bytes: UInt64)
    }

    /// Shows how much free disk space the cleanup gained (measured, so APFS clones are not double counted).
    private func printFreedSpace(since before: UInt64?) {
        guard let before, let after = DerivedDataProjects.freeSpace() else { return }
        customPrint("")
        Print.withColor(.green, DerivedDataProjects.freedSpaceMessage(before: before, after: after))
    }

    /// Per-project rows of Xcode's default folder (biggest first, orphans flagged) plus a shared-caches row
    /// and any project-local `DerivedData` folder. Nothing is ticked by default; only ticked rows are deleted.
    private func pickDerivedDataFolders() throws -> [String] {
        let defaultFolder = (expandTilde(DerivedDataDiscovery.defaultLocation) as NSString).standardizingPath
        let found = DerivedDataDiscovery.found

        var choices: [DerivedDataChoice] = []
        try runWithLoader("Measuring Derived Data projects") {
            let projects = DerivedDataProjects.measured(DerivedDataProjects.projects(in: defaultFolder))
            let caches = DerivedDataProjects.sharedCaches(in: defaultFolder)
            let cacheBytes = DiskUsage.measure(paths: caches).values.reduce(UInt64(0)) { $0 + $1.bytes }
            let others = found.filter { $0 != defaultFolder }
            let otherUsage = DiskUsage.measure(paths: others)
            var rows: [(bytes: UInt64, choice: DerivedDataChoice)] = projects.map { ($0.bytes, .project($0)) }
            if !caches.isEmpty { rows.append((cacheBytes, .sharedCaches(folder: defaultFolder, paths: caches, bytes: cacheBytes))) }
            for other in others {
                let bytes = otherUsage[other]?.bytes ?? 0
                rows.append((bytes, .wholeFolder(path: other, bytes: bytes)))
            }
            choices = rows.sorted { $0.bytes > $1.bytes }.map { $0.choice }
        }
        guard !choices.isEmpty else {
            Print.withColor(.yellow, "No Derived Data projects found.")
            return []
        }

        let home = NSHomeDirectory()
        let dim = Print.Color.dim.rawValue
        let reset = Print.Color.reset.rawValue
        let selected = Prompt().checkboxOptions(
            choices,
            question: "\n\(Print.Color.boldGreen.rawValue)Derived Data to delete\(reset)  \(dim)Only ticked rows are deleted; orphan = its project no longer exists\(reset)",
            label: { choice in
                switch choice {
                case .project(let project):
                    let prefix = project.isPartial ? "~" : ""
                    let flag = project.isOrphan ? "  \(Print.Color.yellow.rawValue)orphan\(reset)" : ""
                    return "\(project.name.terminalSafe)  \(dim)\(prefix)\(formatStorage(project.bytes))\(reset)\(flag)"
                case .sharedCaches(_, _, let bytes):
                    return "Shared caches (module, compilation, SDK)  \(dim)\(formatStorage(bytes))\(reset)"
                case .wholeFolder(let path, let bytes):
                    let shown = path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
                    return "\(shown.terminalSafe) (whole folder)  \(dim)\(formatStorage(bytes))\(reset)"
                }
            },
            detail: { choice in
                if case .project(let project) = choice {
                    return project.workspacePath.map { "Project: \($0.terminalSafe)" } ?? "Project path unknown (no readable info.plist)"
                }
                return nil
            }
        )
        let paths = selected.flatMap { choice -> [String] in
            switch choice {
            case .project(let project): return [project.path]
            case .sharedCaches(_, let paths, _): return paths
            case .wholeFolder(let path, _): return [path]
            }
        }
        return DerivedDataProjects.deletable(paths, allowedFolders: found)
    }

    private func deleteDerivedData(_ folders: [String]) throws {
        guard !folders.isEmpty else { return }
        let command = OptionInput.remove(folders)
        try runWithLoader("Cleaning \(OptionInput.derivedData.title)") {
            let result = runProcess(command.executable, command.arguments, searchPath: command.searchPath)
            if !result.success {
                throw "Command failed with exit code \(result.exitCode): \(command.display)"
            }
        }
    }

    private func eraseSelectedSimulators() throws {
        var devices: [SimulatorDevice] = []
        var usages: [String: DiskUsage] = [:]
        try runWithLoader("Measuring simulators") {
            devices = SimulatorDevices.list()
            usages = DiskUsage.measure(paths: devices.map { $0.dataPath })
        }

        guard !devices.isEmpty else {
            Print.withColor(.yellow, "No simulators found.")
            return
        }

        // Heaviest first: those are the ones worth erasing.
        devices.sort { (usages[$0.dataPath]?.bytes ?? 0) > (usages[$1.dataPath]?.bytes ?? 0) }

        let selected = Prompt().checkboxOptions(
            devices,
            question: "\n\(Print.Color.boldGreen.rawValue)Select simulators to erase\(Print.Color.reset.rawValue)  \(Print.Color.dim.rawValue)apps, logins, keychain & settings are wiped; the device stays in Xcode\(Print.Color.reset.rawValue)",
            label: { device in
                let usage = usages[device.dataPath] ?? .zero
                let prefix = usage.isPartial ? "~" : ""
                let running = device.isBooted ? "  •  running" : ""
                return "\(device.name)  \(Print.Color.dim.rawValue)\(device.runtime)  •  \(prefix)\(formatStorage(usage.bytes))\(running)\(Print.Color.reset.rawValue)"
            }
        )

        guard !selected.isEmpty else {
            Print.withColor(.yellow, "No simulators selected.")
            return
        }

        let names = selected.map { "\($0.name) (\($0.runtime))" }.joined(separator: ", ")
        let confirmDelete = Prompt().yesNo("⚠️  Erase \(names)? Their installed apps, logins, keychain and settings are lost. Running ones are shut down first.")
        guard confirmDelete else {
            Print.withColor(.yellow, "Cancelled.")
            return
        }

        for device in selected {
            var result = ShellResult(output: "", exitCode: 0)
            try runWithLoader("Erasing \(device.name)") {
                result = SimulatorDevices.erase(device)
            }
            if result.success {
                Print.withColor(.green, "Erased \(device.name) (\(device.runtime))")
            } else {
                Print.withColor(.red, "Failed to erase \(device.name): \(result.output)")
            }
        }
        sendNotification(message: "Simulators erased")
    }

    private func deleteSelectedSimulators() throws {
        var devices: [SimulatorDevice] = []
        var usages: [String: DiskUsage] = [:]
        try runWithLoader("Measuring simulators") {
            devices = SimulatorDevices.list().filter { $0.runtime.hasPrefix("iOS") }
            usages = DiskUsage.measure(paths: devices.map { $0.dataPath })
        }

        guard !devices.isEmpty else {
            Print.withColor(.yellow, "No simulators found.")
            return
        }

        // Heaviest first, ties by name so the order is stable.
        devices.sort {
            let lhs = usages[$0.dataPath]?.bytes ?? 0
            let rhs = usages[$1.dataPath]?.bytes ?? 0
            return lhs != rhs ? lhs > rhs : $0.name < $1.name
        }

        let selected = Prompt().checkboxOptions(
            devices,
            question: "\n\(Print.Color.boldGreen.rawValue)Select simulators to delete\(Print.Color.reset.rawValue)  \(Print.Color.dim.rawValue)the devices are removed for good and must be created again to be used\(Print.Color.reset.rawValue)",
            label: { device in
                let usage = usages[device.dataPath] ?? .zero
                let prefix = usage.isPartial ? "~" : ""
                let running = device.isBooted ? "  •  running" : ""
                return "\(device.name)  \(Print.Color.dim.rawValue)\(device.runtime)  •  \(prefix)\(formatStorage(usage.bytes))\(running)\(Print.Color.reset.rawValue)"
            }
        )

        guard !selected.isEmpty else {
            Print.withColor(.yellow, "No simulators selected.")
            return
        }

        let names = selected.map { "\($0.name) (\($0.runtime))" }.joined(separator: ", ")
        let confirmDelete = Prompt().yesNo("⚠️  Delete \(names)? This cannot be undone: the simulators are removed with their apps and data, and must be created again to be used. Running ones are shut down first.")
        guard confirmDelete else {
            Print.withColor(.yellow, "Cancelled.")
            return
        }

        for device in selected {
            var result = ShellResult(output: "", exitCode: 0)
            try runWithLoader("Deleting \(device.name)") {
                result = SimulatorDevices.delete(device)
            }
            if result.success {
                Print.withColor(.green, "Deleted \(device.name) (\(device.runtime))")
            } else {
                Print.withColor(.red, "Failed to delete \(device.name): \(result.output)")
            }
        }
        sendNotification(message: "Simulators deleted")
    }

    /// Lets the user pick which folders over 1 GB directly inside ~/Library/Caches to delete.
    private func deleteLargeCacheFolders() throws {
        var large: [(path: String, usage: DiskUsage)] = []
        try runWithLoader("Measuring ~/Library/Caches") {
            let folders = UserCaches.rootFolders()
            large = UserCaches.largeFolders(folders, usages: DiskUsage.measure(paths: folders))
        }

        guard !large.isEmpty else {
            Print.withColor(.yellow, "No folders over \(formatStorage(UserCaches.minimumBytes)) in ~/Library/Caches.")
            return
        }

        let selected = Prompt().checkboxOptions(
            large,
            question: "\n\(Print.Color.boldGreen.rawValue)Select folders in ~/Library/Caches to delete\(Print.Color.reset.rawValue)  \(Print.Color.dim.rawValue)only folders over \(formatStorage(UserCaches.minimumBytes)); apps rebuild them\(Print.Color.reset.rawValue)",
            label: { folder in
                let prefix = folder.usage.isPartial ? "~" : ""
                let name = (folder.path as NSString).lastPathComponent.terminalSafe
                return "\(name)  \(Print.Color.dim.rawValue)\(prefix)\(formatStorage(folder.usage.bytes))\(Print.Color.reset.rawValue)"
            }
        )

        guard !selected.isEmpty else {
            Print.withColor(.yellow, "No folders selected.")
            return
        }

        let names = selected.map { (($0.path as NSString).lastPathComponent).terminalSafe }.joined(separator: ", ")
        let confirmDelete = Prompt().yesNo("⚠️  Delete \(names) from ~/Library/Caches? The apps that own them rebuild the cache; some may sign you out or download data again.")
        guard confirmDelete else {
            Print.withColor(.yellow, "Cancelled.")
            return
        }

        for folder in selected {
            let name = (folder.path as NSString).lastPathComponent.terminalSafe
            // Re-check right before deleting: still a direct, real folder of ~/Library/Caches.
            guard UserCaches.isSafeToDeleteNow(folder.path) else {
                Print.withColor(.red, "Skipped \(name): not a plain folder of ~/Library/Caches any more")
                continue
            }
            do {
                try runWithLoader("Deleting \(name)") {
                    try FileManager.default.removeItem(atPath: folder.path)
                }
                Print.withColor(.green, "Deleted \(name)")
            } catch {
                Print.withColor(.red, "Failed to delete \(name): \(error)")
            }
        }
        sendNotification(message: "Caches cleaned")
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
                return "\((folder as NSString).lastPathComponent.terminalSafe)  \(Print.Color.dim.rawValue)\(prefix)\(formatStorage(usage.bytes))\(Print.Color.reset.rawValue)"
            }
        )

        guard !selected.isEmpty else {
            Print.withColor(.yellow, "No versions selected.")
            return
        }

        let names = selected.map { ($0 as NSString).lastPathComponent.terminalSafe }.joined(separator: ", ")
        let confirmDelete = Prompt().yesNo("⚠️  Delete \(names)? Xcode copies the files again the next time you plug in a device running that version.")
        guard confirmDelete else {
            Print.withColor(.yellow, "Cancelled.")
            return
        }

        for folder in selected {
            let name = (folder as NSString).lastPathComponent.terminalSafe
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
        // The menu asks which size to scan for (5 GB pre-selected). `-d 15` runs without a prompt, so it uses the default.
        let threshold = delete == nil
            ? Prompt().options(
                SystemScanner.SizeThreshold.allCases,
                question: "Show folders bigger than:",
                defaultAnswer: SystemScanner.SizeThreshold.default
            ) ?? SystemScanner.SizeThreshold.default
            : SystemScanner.SizeThreshold.default

        try runWithLoader("Scanning system folders larger than \(threshold) (this may take a moment)") {
            output = SystemScanner.listLargeFolders(threshold: threshold)
        }

        Print.withColor(.boldGreen, "Deepest folders larger than \(threshold)")
        if output.isEmpty {
            Print.withColor(.yellow, "No folders larger than \(threshold) found in scanned locations.")
        } else {
            Print.withColor(.cyan, "Showing largest 50 deepest folders (parent folders excluded):\n")
            customPrint(output.components(separatedBy: "\n").map { $0.terminalSafe }.joined(separator: "\n"))
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
                "\(String(format: "%.1f GB", folder.gigabytes))  \(folder.displayPath)  \(Print.Color.dim.rawValue)\(folder.note)\(Print.Color.reset.rawValue)"
            }
        )

        guard !selected.isEmpty else {
            Print.withColor(.yellow, "No folders selected.")
            return
        }

        let total = selected.reduce(0) { $0 + $1.gigabytes }
        let list = selected.map { "  \($0.displayPath)" }.joined(separator: "\n")
        let confirmDelete = Prompt().yesNo("⚠️  Delete \(selected.count) folder(s), \(String(format: "%.1f GB", total))?\n\(list)")
        guard confirmDelete else {
            Print.withColor(.yellow, "Cancelled.")
            return
        }

        for folder in selected {
            // Re-check right before deleting: still on the allowlist, and no symlink swapped in since the scan.
            guard SystemScanner.isSafeToDeleteNow(folder.path) else {
                Print.withColor(.red, "Skipped \(folder.displayPath): not on the safe-to-delete list, or changed on disk since the scan")
                continue
            }
            do {
                try runWithLoader("Deleting \(folder.displayPath)") {
                    try FileManager.default.removeItem(atPath: folder.path)
                }
                Print.withColor(.green, "Deleted \(folder.displayPath)")
            } catch {
                Print.withColor(.red, "Failed to delete \(folder.displayPath): \(error)")
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
            result = simctl(["shutdown", "all"])
        }
        if !result.success {
            Print.withColor(.yellow, "Shutdown had issues (simulators may already be off)")
        }

        try runWithLoader("Erasing all simulators") {
            result = simctl(["erase", "all"])
            guard result.success else {
                throw "Failed to erase simulators: \(result.output)"
            }
        }

        try runWithLoader("Clearing CoreSimulator caches") {
            result = runProcess("/bin/rm", ["-rf", expandTilde("~/Library/Developer/CoreSimulator/Caches")])
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
                result = simctl(["--set", expandTilde(testDevicesPath), "delete", "all"])
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
                result = simctl(["--set", expandTilde(previewDevicesPath), "delete", "all"])
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
    /// Prefers terminal-notifier so tapping the notification returns to the terminal that ran alfy-clean: the app
    /// (its bundle ID comes from `__CFBundleIdentifier`) and, in Ghostty, the exact tab (see `TerminalFocus`); falls back to osascript, whose notifications
    /// open Script Editor on tap.
    /// Returns immediately without waiting for user interaction.
    /// Silently ignores all errors (notifier unavailable, permission denied, etc.)
    /// since notifications are non-critical to the main task.
    private func sendNotification(message: String) {
        if let notifier = Self.terminalNotifierPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            var arguments = ["-title", "alfy-clean", "-message", message, "-sound", "Glass"]
            if let terminalBundleID = ProcessInfo.processInfo.environment["__CFBundleIdentifier"] {
                arguments += ["-activate", terminalBundleID]
            }
            // Tapping it returns to the exact terminal tab that ran alfy-clean, not just the terminal app.
            if let focusCommand = TerminalFocus.clickCommand {
                arguments += ["-execute", focusCommand]
            }
            runProcess(notifier, arguments)
        } else {
            // The message is passed as an argument to the script, never spliced into its source.
            runProcess("/usr/bin/osascript", [
                "-e", "on run argv",
                "-e", "display notification (item 1 of argv) with title \"alfy-clean\" sound name \"Glass\"",
                "-e", "end run",
                message
            ])
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
        case simultorsData                  // Erase chosen simulators (apps, data, keychains)
        case clonedSimulatorsData           // Cloned devices for parallel tests & Playgrounds
        case derivedData                    // Build artifacts & cache (slow rebuild)
        case archives                       // ⚠️ Old IPA builds (cannot regenerate)
        case previews                       // Xcode Preview cache
        case messagesAttachments            // macOS Messages attachments
        case microsoftTeamsCache            // Microsoft Teams local cache
        case documentationCache             // QuickHelp docs (regenerates on access)
        case trash                          // System trash bin
        case homebrewCache                  // Homebrew downloads & old versions (brew cleanup)
        case maestroTests                   // Maestro test run outputs (screenshots, logs)
        case claudeJobsTmp                  // Claude Code job scratch folders (~/.claude/jobs/*/tmp)
        case deviceSupport                  // Per-version device symbols (re-copied on device plug-in)
        case simulatorRuntimes              // ⚠️ Installed runtimes (re-download to restore)
        case largeSystemFolders             // Scan for large system folders (info only)
        case swiftPMCache                   // SwiftPM package cache (~/Library/Caches/org.swift.swiftpm)
        case userCaches                     // Pick big folders (> 1 GB) directly inside ~/Library/Caches
        case deleteSimulators               // ⚠️ Pick simulators to delete for good (must be recreated)
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
            case 11: self = .maestroTests
            case 12: self = .claudeJobsTmp
            case 13: self = .deviceSupport
            case 14: self = .simulatorRuntimes
            case 15: self = .largeSystemFolders
            case 16: self = .swiftPMCache
            case 17: self = .userCaches
            case 18: self = .deleteSimulators
            default: throw "Manage this case \(value)"
            }
        }
        init?(rawValue: Int) { fatalError("use `init(value: Int) throws`") }

        var title: String {
            switch self {
            case .derivedData: return "🔥 🧨 Derived Data"
            case .noDerivedData: return "🥳 All, -> derived data excluded"
            case .simultorsData: return "⚠️  Erase simulators (apps, logins, keychains)"
            case .clonedSimulatorsData: return "Delete cloned simulators (tests & Playgrounds)"
            case .archives: return "⚠️  Archives (.xcarchive & dSYMs, not recoverable)"
            case .previews: return "Previews"
            case .messagesAttachments: return "📩 Open Messages Attachments folder"
            case .microsoftTeamsCache: return "Teams (classic) app data, signs you out"
            case .documentationCache: return "QuickHelp Documentation Cache"
            case .trash: return "🗑️ System Trash"
            case .homebrewCache: return "🍺 Homebrew Cache"
            case .maestroTests: return "🎭 Maestro tests output"
            case .claudeJobsTmp: return "🤖 Claude Code jobs tmp folders"
            case .deviceSupport: return "📱 iOS DeviceSupport versions"
            case .simulatorRuntimes: return "📦 Simulator runtimes"
            case .largeSystemFolders: return "🔎 Scan for folders over a size you choose"
            case .swiftPMCache: return "📦 SwiftPM cache"
            case .userCaches: return "🗂️ Big folders in ~/Library/Caches"
            case .deleteSimulators: return "⚠️  Delete simulators (gone, must be recreated)"
            }
        }

        /// One plain-words line under each menu row: what choosing it will do.
        var actionDescription: String {
            switch self {
            case .noDerivedData:
                return "Bulk cleanup: simulators, clones, DeviceSupport, archives, previews, Teams, docs, SwiftPM cache, Trash, Maestro. Keeps DerivedData."
            case .simultorsData:
                return "Lets you pick simulators, then shuts them down and erases apps, data and keychains. Devices stay installed."
            case .clonedSimulatorsData:
                return "Deletes the clone devices Xcode makes for parallel tests and Playgrounds. Xcode recreates them when needed."
            case .derivedData:
                return "Deletes Xcode's build products and indexes, in every Xcode project folder it finds. The next build is slow, nothing is lost."
            case .archives:
                return "Permanently deletes every .xcarchive and its dSYMs. You can't re-export or symbolicate old builds afterwards."
            case .previews:
                return "Deletes the SwiftUI Preview cache. Previews rebuild it the next time you open them."
            case .messagesAttachments:
                return "Only opens the Messages Attachments folder in Finder so you can review it. Deletes nothing."
            case .microsoftTeamsCache:
                return "Deletes Teams (classic) local data and signs you out. Log in again next time."
            case .documentationCache:
                return "Deletes Xcode's QuickHelp documentation cache. It downloads again when you open the docs."
            case .trash:
                return "Permanently empties your Trash. Files can't be recovered."
            case .homebrewCache:
                return "Runs `brew cleanup --prune=all`: removes cached downloads and old versions of installed formulae."
            case .maestroTests:
                return "Deletes saved Maestro run output: screenshots, logs and recordings."
            case .claudeJobsTmp:
                return "Deletes the scratch tmp folder inside each Claude Code job. Job history is kept."
            case .deviceSupport:
                return "Lets you pick iOS versions to delete. Xcode copies the symbols again when you plug in a device."
            case .simulatorRuntimes:
                return "Lets you pick runtimes to delete with simctl. Download them again from Xcode to restore."
            case .largeSystemFolders:
                return "Asks for a size (over 2, 5 or 10 GB, 5 GB by default), scans the disk for folders over it, then lets you tick the safe ones to delete."
            case .swiftPMCache:
                return "Deletes SwiftPM's shared cache of package downloads. Packages are fetched again on the next resolve."
            case .userCaches:
                return "Lists the folders over 1 GB in ~/Library/Caches and lets you tick which to delete. Apps rebuild them."
            case .deleteSimulators:
                return "Lets you pick simulators and deletes them with simctl. They are gone and must be created again to be used."
            }
        }

        /// Kept in the code (and reachable with `-d <n>` / `all`) but not offered in the interactive menu.
        var isHiddenInMenu: Bool {
            switch self {
            case .noDerivedData, .microsoftTeamsCache, .messagesAttachments, .trash:
                return true
            case .maestroTests:
                // Only offered when Maestro has left something behind.
                return !FileManager.default.fileExists(atPath: expandTilde("~/.maestro/tests"))
            default:
                return false
            }
        }

        static var menuOptions: [OptionInput] {
            allCases.filter { !$0.isHiddenInMenu }
        }

        /// Plain text (no emoji) so the table columns line up.
        var tableName: String {
            switch self {
            case .noDerivedData: return "All except Derived Data"
            case .simultorsData: return "Erase simulators content"
            case .clonedSimulatorsData: return "Delete cloned sims"
            case .derivedData: return "Derived Data"
            case .archives: return "Archives"
            case .previews: return "Previews"
            case .messagesAttachments: return "Messages attachments"
            case .microsoftTeamsCache: return "Teams (classic) data"
            case .documentationCache: return "Documentation cache"
            case .trash: return "System Trash"
            case .homebrewCache: return "Homebrew cache"
            case .maestroTests: return "Maestro test output"
            case .claudeJobsTmp: return "Claude Code jobs tmp"
            case .deviceSupport: return "iOS DeviceSupport"
            case .simulatorRuntimes: return "Simulator runtimes"
            case .largeSystemFolders: return "Scan for folders over a size you choose"
            case .swiftPMCache: return "SwiftPM cache"
            case .userCaches: return "Caches > 1 GB"
            case .deleteSimulators: return "Delete simulators"
            }
        }

        var risk: CheckboxTableRow.Risk {
            switch self {
            case .noDerivedData: return .bulk
            case .derivedData, .previews, .documentationCache, .clonedSimulatorsData,
                 .homebrewCache, .maestroTests, .claudeJobsTmp, .swiftPMCache:
                return .safe
            case .simultorsData, .deviceSupport, .simulatorRuntimes, .userCaches, .deleteSimulators: return .pick
            case .archives, .trash: return .final
            case .microsoftTeamsCache: return .slow
            case .messagesAttachments, .largeSystemFolders: return .look
            }
        }

        /// Menu section, in display order: Xcode and iOS first.
        enum Category: Int {
            case xcodeIOS, caches, systemAndApps

            var title: String {
                switch self {
                case .xcodeIOS: return "Xcode & iOS"
                case .caches: return "Caches"
                case .systemAndApps: return "System & apps"
                }
            }
        }

        var category: Category {
            switch self {
            case .noDerivedData, .derivedData, .archives, .previews, .documentationCache,
                 .deviceSupport, .simulatorRuntimes, .simultorsData, .clonedSimulatorsData, .maestroTests,
                 .deleteSimulators:
                return .xcodeIOS
            case .homebrewCache, .claudeJobsTmp, .swiftPMCache, .userCaches:
                return .caches
            case .trash, .largeSystemFolders, .messagesAttachments, .microsoftTeamsCache:
                return .systemAndApps
            }
        }

        /// The user chooses items in a follow-up prompt, so the size shown is a ceiling.
        var picksItemsNext: Bool {
            self == .simultorsData || self == .deviceSupport || self == .simulatorRuntimes || self == .userCaches
                || self == .derivedData || self == .deleteSimulators
        }

        /// What it removes, for the "Deletes" line of the detail box.
        var deletesDescription: String {
            switch self {
            case .noDerivedData: return "Everything in the bulk cleanup, except Derived Data"
            case .simultorsData: return "Apps, data and keychains of the simulators you tick"
            case .clonedSimulatorsData: return "~/Library/Developer/XCTestDevices and XCPGDevices"
            case .derivedData: return "The DerivedData projects and shared caches you tick (orphans flagged)"
            case .archives: return "~/Library/Developer/Xcode/Archives"
            case .previews: return "~/Library/Developer/Xcode/UserData/Previews"
            case .messagesAttachments: return "Nothing, it only opens ~/Library/Messages/Attachments"
            case .microsoftTeamsCache: return "~/Library/Application Support/Microsoft/Teams"
            case .documentationCache: return "~/Library/Developer/Xcode/DocumentationCache"
            case .trash: return "Everything in ~/.Trash"
            case .homebrewCache: return "Homebrew's cache and old versions (brew cleanup --prune=all)"
            case .maestroTests: return "~/.maestro/tests"
            case .claudeJobsTmp: return "The tmp folder inside each ~/.claude/jobs/<job>"
            case .deviceSupport: return "The iOS versions you tick in ~/Library/Developer/Xcode/iOS DeviceSupport"
            case .simulatorRuntimes: return "The runtimes you tick, through simctl"
            case .largeSystemFolders: return "Nothing until you tick folders from the scan"
            case .swiftPMCache: return "~/Library/Caches/org.swift.swiftpm"
            case .userCaches: return "The folders over 1 GB in ~/Library/Caches that you tick"
            case .deleteSimulators: return "The simulator devices you tick, through simctl"
            }
        }

        var comesBackDescription: String {
            switch self {
            case .noDerivedData: return "Mostly; archives and the Trash don't"
            case .simultorsData: return "No: apps and data are wiped, devices stay"
            case .clonedSimulatorsData: return "Yes, Xcode recreates them"
            case .derivedData: return "Yes, on the next build"
            case .archives: return "No, gone for good"
            case .previews: return "Yes, when a preview opens"
            case .messagesAttachments: return "Not applicable"
            case .microsoftTeamsCache: return "Cache yes; you sign in again"
            case .documentationCache: return "Yes, downloads when you open the docs"
            case .trash: return "No, gone for good"
            case .homebrewCache: return "Yes, downloaded again when needed"
            case .maestroTests: return "Yes, on the next test run"
            case .claudeJobsTmp: return "Yes, jobs recreate it"
            case .deviceSupport: return "Yes, when you plug a device in"
            case .simulatorRuntimes: return "Yes, from Xcode > Settings > Components"
            case .largeSystemFolders: return "Depends on what you delete"
            case .swiftPMCache: return "Yes, packages download again"
            case .userCaches: return "Yes, apps rebuild their caches; a few may sign you out or re-download data"
            case .deleteSimulators: return "No: create them again in Xcode ▸ Window ▸ Devices and Simulators"
            }
        }

        var asksFirstDescription: String {
            switch self {
            case .messagesAttachments: return "Nothing to ask, it only opens the folder"
            case .largeSystemFolders: return "Per folder, before anything is removed"
            case .simultorsData, .deviceSupport, .simulatorRuntimes, .userCaches, .deleteSimulators: return "Per item, before anything is removed"
            case .derivedData: return "Which projects and shared caches go, then a yes/no listing them"
            default: return "One yes/no before it runs, listing what goes"
            }
        }

        var runsInAllCleanup: Bool {
            self != .largeSystemFolders && self != .simulatorRuntimes && self != .homebrewCache && self != .deviceSupport && self != .claudeJobsTmp
                && self != .userCaches && self != .deleteSimulators
        }

        /// Deletes without a prompt of its own. Simulators, DeviceSupport, runtimes and the large-folder scan
        /// ask per item; Messages only opens a folder.
        var needsConfirmation: Bool {
            switch self {
            case .simultorsData, .deviceSupport, .simulatorRuntimes, .largeSystemFolders, .messagesAttachments, .userCaches, .deleteSimulators:
                return false
            default:
                return true
            }
        }

        /// The options an "all" cleanup runs after erasing simulators and cloned devices.
        static func allCleanupOptions(includingDerivedData: Bool) -> [OptionInput] {
            allCases.filter {
                $0.runsInAllCleanup
                    && ![.noDerivedData, .simultorsData, .clonedSimulatorsData].contains($0)
                    && (includingDerivedData || $0 != .derivedData)
            }
        }

        static let deviceSupportPath = "~/Library/Developer/Xcode/iOS DeviceSupport"
        static let claudeJobsPath = "~/.claude/jobs"

        // One `tmp` folder per job; `du` doesn't expand globs, so list them.
        static var claudeJobsTmpPaths: [String] {
            let root = (claudeJobsPath as NSString).expandingTildeInPath
            let jobs = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
            return jobs.map { "\(claudeJobsPath)/\($0)/tmp" }
        }

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
                    "~/.Trash",
                    "~/.maestro/tests",
                    "~/Library/Caches/org.swift.swiftpm"
                ]
            case .simultorsData, .deleteSimulators:
                return ["~/Library/Developer/CoreSimulator/Devices"]
            case .clonedSimulatorsData:
                return [
                    "~/Library/Developer/XCTestDevices",
                    "~/Library/Developer/XCPGDevices"
                ]
            case .derivedData:
                return DerivedDataDiscovery.found
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
            case .maestroTests:
                return ["~/.maestro/tests"]
            case .claudeJobsTmp:
                return Self.claudeJobsTmpPaths
            case .deviceSupport:
                return [Self.deviceSupportPath]
            case .swiftPMCache:
                return ["~/Library/Caches/org.swift.swiftpm"]
            case .userCaches:
                return UserCaches.rootFolders()
            case .simulatorRuntimes, .largeSystemFolders:
                return []
            }
        }
        
        /// A program and its arguments, run without a shell. Paths are expanded here, not by a shell.
        struct Command {
            let executable: String
            let arguments: [String]
            var searchPath = systemSearchPath
            /// The command is skipped when this folder doesn't exist (nothing to clean).
            var requiredFolder: String?

            var display: String { ([executable] + arguments).joined(separator: " ") }
        }

        private static let homebrewBinFolders = ["/opt/homebrew/bin", "/usr/local/bin"]

        private static func remove(_ paths: String...) -> Command {
            remove(paths)
        }

        static func remove(_ paths: [String]) -> Command {
            Command(executable: "/bin/rm", arguments: ["-rf"] + paths.map(expandTilde))
        }

        /// Deletes everything inside `folder`, keeping the folder itself.
        static func emptyFolder(_ folder: String) -> Command {
            Command(
                executable: "/usr/bin/find",
                arguments: [folder, "-mindepth", "1", "-maxdepth", "1", "-exec", "/bin/rm", "-rf", "{}", "+"],
                requiredFolder: folder
            )
        }

        /// Deletes `<jobs>/<job>/tmp` for every job.
        static func removeJobTmpFolders(in jobs: String) -> Command {
            Command(
                executable: "/usr/bin/find",
                arguments: [jobs, "-mindepth", "2", "-maxdepth", "2", "-name", "tmp", "-type", "d", "-exec", "/bin/rm", "-rf", "{}", "+"],
                requiredFolder: jobs
            )
        }

        func command() throws -> Command {
            switch self {
            case .noDerivedData: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .simultorsData: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .clonedSimulatorsData: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .derivedData: return Self.remove(DerivedDataDiscovery.found)
            case .archives: return Self.remove("~/Library/Developer/Xcode/Archives")
            case .previews: return Self.remove("~/Library/Developer/Xcode/UserData/Previews")
            case .messagesAttachments: return Command(executable: "/usr/bin/open", arguments: [expandTilde("~/Library/Messages/Attachments")])
            case .microsoftTeamsCache: return Self.remove("~/Library/Application Support/Microsoft/Teams")
            case .documentationCache: return Self.remove("~/Library/Developer/Xcode/DocumentationCache")
            case .trash: return Self.emptyFolder(expandTilde("~/.Trash"))
            case .homebrewCache:
                guard let folder = Self.homebrewBinFolders.first(where: {
                    FileManager.default.isExecutableFile(atPath: $0 + "/brew")
                }) else {
                    throw "Homebrew not found in \(Self.homebrewBinFolders.joined(separator: " or "))"
                }
                return Command(
                    executable: folder + "/brew",
                    arguments: ["cleanup", "--prune=all"],
                    searchPath: (Self.homebrewBinFolders + [systemSearchPath]).joined(separator: ":")
                )
            case .maestroTests: return Self.remove("~/.maestro/tests")
            case .claudeJobsTmp: return Self.removeJobTmpFolders(in: expandTilde(Self.claudeJobsPath))
            case .deviceSupport: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .simulatorRuntimes: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .largeSystemFolders: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .swiftPMCache: return Self.remove("~/Library/Caches/org.swift.swiftpm")
            case .userCaches: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            case .deleteSimulators: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            }
        }
    }
}

// MARK: Text descriptions -

private extension Clean {
    static let trashAccessMessage = "Can't read ~/.Trash: give your terminal Full Disk Access (System Settings > Privacy & Security > Full Disk Access) and try again"

    static var isTrashUnreadable: Bool {
        let path = expandTilde("~/.Trash")
        return FileManager.default.fileExists(atPath: path)
            && (try? FileManager.default.contentsOfDirectory(atPath: path)) == nil
    }

    struct MenuEntry {
        let input: OptionInput
        let row: CheckboxTableRow
    }

    /// The visible options as menu rows, grouped by category and biggest first within each.
    func menuEntries() -> [MenuEntry] {
        let estimatesByPath = diskUsageEstimatesByPath()
        let runtimesBytes = SimulatorRuntimes.list().reduce(0) { $0 + $1.sizeBytes }

        let entries = OptionInput.menuOptions.map { optionInput -> MenuEntry in
            var bytes: UInt64 = 0
            var size = "scan"
            var isApproximate = false

            switch optionInput {
            case .largeSystemFolders:
                break
            case .simulatorRuntimes:
                bytes = runtimesBytes
                size = formatStorage(runtimesBytes)
            case .userCaches:
                // Only the folders over the minimum are offered, so only they count.
                bytes = UserCaches.largeFolders(optionInput.estimatedPaths, usages: estimatesByPath).reduce(0) { $0 + $1.usage.bytes }
                size = formatStorage(bytes)
            case .trash where Self.isTrashUnreadable:
                // macOS blocks ~/.Trash without Full Disk Access; "0 MB" would be misleading.
                size = "no access"
            default:
                let estimate = estimatedFreeSpace(for: optionInput, estimatesByPath: estimatesByPath)
                bytes = estimate.bytes
                isApproximate = estimate.isPartial
                size = (estimate.isPartial ? "~" : "") + formatStorage(estimate.bytes)
            }

            return MenuEntry(input: optionInput, row: CheckboxTableRow(
                name: optionInput.tableName,
                group: optionInput.category.title,
                bytes: bytes,
                size: size,
                risk: optionInput.risk,
                isWarning: optionInput == .deleteSimulators,
                isApproximate: isApproximate,
                isUpperBound: optionInput.picksItemsNext,
                summary: optionInput.actionDescription,
                facts: [
                    ("Deletes", optionInput.deletesDescription),
                    ("Comes back", optionInput.comesBackDescription),
                    ("Asks first", optionInput.asksFirstDescription)
                ]
            ))
        }

        // By category (Xcode & iOS first), then biggest first; ties keep menu order.
        return entries.enumerated()
            .sorted { lhs, rhs in
                let (a, b) = (lhs.element, rhs.element)
                if a.input.category != b.input.category { return a.input.category.rawValue < b.input.category.rawValue }
                if a.row.bytes != b.row.bytes { return a.row.bytes > b.row.bytes }
                return lhs.offset < rhs.offset
            }
            .map { $0.element }
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
        let uniquePaths = Array(Set(OptionInput.menuOptions.flatMap { $0.estimatedPaths }))
        let loader = TerminalLoader()
        loader.start()
        // Cloned simulators share blocks with their source device: count only what deleting them frees.
        let cloned = uniquePaths.filter { DiskUsage.cloneFolders.contains($0) }
        var result = DiskUsage.measure(paths: uniquePaths.filter { !cloned.contains($0) })
        result.merge(DiskUsage.measureReclaimable(paths: cloned)) { _, reclaimable in reclaimable }
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

    static var configMessage: String {
        "Delete shit data of your developer folder 🚮"
    }
    
}
