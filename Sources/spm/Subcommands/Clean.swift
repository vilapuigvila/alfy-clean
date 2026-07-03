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
            let confirmDelete = Prompt().yesNo("⚠️  This will erase simulator data and keychains. Continue?")
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

        try (3..<OptionInput.allCases.count).forEach {
            do {
                let optionInput = try OptionInput(value: $0)
                try runCleanup(optionInput)
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

        try (4..<OptionInput.allCases.count).forEach {
            do {
                let optionInput = try OptionInput(value: $0)
                try runCleanup(optionInput)
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
    }

    private func runCleanup(_ optionInput: OptionInput) throws {
        switch optionInput {
        case .noDerivedData:
            try deleteAllUnlessDerivedData()
        case .simultorsData:
            try deleteSimulatorsData()
        case .clonedSimulatorsData:
            try deleteClonedSimulatorsDataAndUserDefaults()
        case .derivedData, .archives, .previews, .messagesAttachments, .microsoftTeamsCache, .trash:
            let command = try optionInput.shellCommand()
            try runWithLoader("Cleaning \(optionInput.title)") {
                let result = shell(command)
                if !result.success {
                    throw "Command failed with exit code \(result.exitCode): \(command)"
                }
            }
        }
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
}

// MARK: Options -

extension Clean {
    
    enum OptionInput: Int, CaseIterable {
        case noDerivedData, simultorsData, clonedSimulatorsData, derivedData, archives, previews, messagesAttachments, microsoftTeamsCache, trash
        // XCPGDevices && Xcode/iOS DeviceSupport
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
            case 8: self = .trash
            default: throw "Manage this case \(value)"
            }
        }
        init?(rawValue: Int) { fatalError("use `init(value: Int) throws`") }

        var title: String {
            switch self {
            case .noDerivedData: return "🥳 All, but not derived data"
            case .simultorsData: return "Simulators Data & ⚠️  Keychain"
            case .clonedSimulatorsData: return "Cloned simulators Data & UserDefaults"
            case .derivedData: return "🔥 🧨 Derived Data"
            case .archives: return "Archives"
            case .previews: return "Previews"
            case .messagesAttachments: return "📩 Open Messages Attachments folder"
            case .microsoftTeamsCache: return "Teams microsoft Cache"
            case .trash: return "🗑️ System Trash"
            }
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
            case .trash:
                return ["~/.Trash"]
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
            case .trash: return "if [ -d ~/.Trash ]; then find ~/.Trash -mindepth 1 -maxdepth 1 -exec rm -rf {} +; fi"
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

        return OptionInput.allCases.map { optionInput in
            let estimate = estimatedFreeSpace(for: optionInput, estimatesByPath: estimatesByPath)
            let prefix = estimate.isPartial ? "~" : ""
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

    struct DiskUsageEstimate {
        let bytes: UInt64
        let isPartial: Bool

        static let zero = DiskUsageEstimate(bytes: 0, isPartial: false)
    }

    func diskUsageEstimatesByPath() -> [String: DiskUsageEstimate] {
        let uniquePaths = Set(OptionInput.allCases.flatMap { $0.estimatedPaths })
        return uniquePaths.reduce(into: [:]) { result, path in
            result[path] = diskUsageEstimate(for: path)
        }
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

    func diskUsageEstimate(for path: String) -> DiskUsageEstimate {
        let expandedPath = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expandedPath)
        var isDirectory = ObjCBool(false)

        guard FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDirectory) else {
            return .zero
        }

        guard isDirectory.boolValue else {
            return DiskUsageEstimate(bytes: allocatedSize(of: url), isPartial: false)
        }

        let keys: [URLResourceKey] = [
            .fileAllocatedSizeKey,
            .totalFileAllocatedSizeKey
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { _, _ in true }
        ) else {
            return .zero
        }

        let startedAt = ProcessInfo.processInfo.systemUptime
        let timeLimit = 0.35
        let entryLimit = 3_000
        var bytes = allocatedSize(of: url)
        var entryCount = 0

        for case let fileURL as URL in enumerator {
            bytes += allocatedSize(of: fileURL)
            entryCount += 1

            if entryCount >= entryLimit || ProcessInfo.processInfo.systemUptime - startedAt >= timeLimit {
                return DiskUsageEstimate(bytes: bytes, isPartial: true)
            }
        }

        return DiskUsageEstimate(bytes: bytes, isPartial: false)
    }

    func allocatedSize(of url: URL) -> UInt64 {
        guard let values = try? url.resourceValues(forKeys: [
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey
        ]) else {
            return 0
        }

        if let totalFileAllocatedSize = values.totalFileAllocatedSize {
            return UInt64(totalFileAllocatedSize)
        }

        if let fileAllocatedSize = values.fileAllocatedSize {
            return UInt64(fileAllocatedSize)
        }

        return 0
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
        let megabyte = 1_000_000.0
        let gigabyte = 1_000_000_000.0
        let value = Double(bytes)

        if value >= gigabyte {
            return String(format: "%.1f GB", value / gigabyte)
        }

        return String(format: "%.0f MB", value / megabyte)
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
