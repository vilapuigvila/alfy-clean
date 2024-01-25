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
            if !(0...OptionInput.allCases.count).contains(option) {
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
        
        let optionInput = try pickOption()
        Print.withColor(.cyan, "Wait... 🙏")
        
        switch optionInput {
        case .noDerivedData:
            try deleteAllUnlessDerivedData()
        case .simultorsData:
            try deleteSimulatorsData()
        case .clonedSimulatorsData:
            try deleteClonedSimulatorsDataAndUserDefaults()
        case .derivedData, .archives, .previews, .messagesAttachments, .microsoftTeamsCache:
            Print.withColor(.yellow, "deleting \(optionInput)")
            let command = try optionInput.shellCommand()
            Print.withColor(.red, command)
            shell(command)
        }
        isDone = true
        
        while(!isDone) {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
        }
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
        
        try deleteSimulatorsData()
        try deleteClonedSimulatorsDataAndUserDefaults()

        try (3...7).forEach {
            do {
                let option = try OptionInput(value: $0).shellCommand()
                Print.withColor(.yellow, "deleting \(option)...")
                shell(option)
            } catch {
                throw error.localizedDescription
            }
        }
        return false
    }
    
    private func deleteAllUnlessDerivedData() throws {
        Print.withColor(.yellow, "deleting iOS DeviceSupport")
        shell("rm -R ~/Library/Developer/Xcode/iOS' 'DeviceSupport")
        Print.withColor(.yellow, "deleting simulators data & keychain")
        try deleteSimulatorsData()
        Print.withColor(.yellow, "deleting cloned simulators data")
        try deleteClonedSimulatorsDataAndUserDefaults()
        
        try (4...7).forEach {
            do {
                let option = try OptionInput(value: $0).shellCommand()
                Print.withColor(.yellow, "deleting \(option)...")
                shell(option)
            } catch {
                throw error.localizedDescription
            }
        }
    }
    
    private mutating func pickOption() throws -> OptionInput {
        if let shortOption = delete {
            option = shortOption
        } else {
            Print.h3(optionsMessage)
            let name = try keyboardInput()
            option = (name as NSString).integerValue
        }
        return try OptionInput(value: option)
    }
    
    private func deleteSimulatorsData() throws {
        let fileManager = FileManager.default
        guard #available(macOS 10.12, *) else {
            throw "Your macOS version must be 10.12 or higher"
        }
        do {
            let documentsDirectory =  try fileManager.url(
                for: .libraryDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            Print.withColor(.yellow, "deleting `Caches` simulators data")
            shell("rm -R ~/Library/Developer/CoreSimulator/Caches")
            
            let url = documentsDirectory.appendingPathComponent(
                "Developer/CoreSimulator/Devices",
                isDirectory: true
            )
            
            let subDirectories = try url.subDirectories()
            subDirectories.forEach {
                shell("xcrun simctl erase \($0.lastPathComponent)")
                shell("rm ~/Library/Developer/CoreSimulator/Devices/\($0.lastPathComponent)/data/Documents")                
                shell("rm -R ~/Library/Developer/CoreSimulator/Devices/\($0.lastPathComponent)/data/Library/Keychains")
                shell("rm -R ~/Library/Developer/CoreSimulator/Devices/\($0.lastPathComponent)/data/tmp")
            }
        } catch {
            throw "Can't delete simulators data \(#function)"
        }
    }
    
    private func deleteClonedSimulatorsDataAndUserDefaults() throws {
        let fileManager = FileManager.default
        guard #available(macOS 10.12, *) else {
            throw "Your macOS version must be 10.12 or higher"
        }
        do {
            let documentsDirectory =  try fileManager.url(
                for: .libraryDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            
            // XCTestDevices
            let urlTestDevices = documentsDirectory.appendingPathComponent(
                "Developer/XCTestDevices",
                isDirectory: true
            )
            let subDirectoriesTestDevices = try urlTestDevices.subDirectories()
            subDirectoriesTestDevices.forEach {
                shell("rm -R ~/Library/Developer/XCTestDevices/\($0.lastPathComponent)/data/Documents")
                shell("rm -R ~/Library/Developer/XCTestDevices/\($0.lastPathComponent)/data/Library/Preferences")
                shell("rm -R ~/Library/Developer/XCTestDevices/\($0.lastPathComponent)/data/Library/Caches")
            }
            
            // XCPGDevices
            let urlDevices = documentsDirectory.appendingPathComponent(
                "Developer/XCPGDevices",
                isDirectory: true
            )
            let subDirectoriesDevices = try urlDevices.subDirectories()
            subDirectoriesDevices.forEach {
                shell("rm -R ~/Library/Developer/XCPGDevices/\($0.lastPathComponent)/data/Documents")
                shell("rm -R ~/Library/Developer/XCPGDevices/\($0.lastPathComponent)/data/Library/Preferences")
                shell("rm -R ~/Library/Developer/XCPGDevices/\($0.lastPathComponent)/data/Library/Caches")
                shell("rm -R ~/Library/Developer/XCPGDevices/\($0.lastPathComponent)/data/Library/Keychains")
            }
        } catch {
            throw "Can't delete cloned simulators data \(#function)"
        }
    }
}

// MARK: Options -

extension Clean {
    
    enum OptionInput: Int, CaseIterable {
        case noDerivedData, simultorsData, clonedSimulatorsData, derivedData, archives, previews, messagesAttachments, microsoftTeamsCache
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
            default: throw "Manage this case \(value)"
            }
        }
        init?(rawValue: Int) { fatalError("use `init(value: Int) throws`") }
        
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
            }
        }
    }
}

// MARK: Text descriptions -

private extension Clean {
    var optionsMessage: String {
"""
Enter input `number` to clean desired folder:
0 -> 🥳 All, but not derived data
1 -> Simulators Data & ⚠️  Keychain
2 -> Cloned simulators Data & UserDefaults
3 -> 🔥 🧨 Derived Data
4 -> Archives
5 -> Previews
6 -> 📩 Open Messages Attachments folder
7 -> Teams microsoft Cache
"""
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
