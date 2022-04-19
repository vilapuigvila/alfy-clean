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
            if !(1...OptionInput.allCases.count).contains(option) {
                fatalError("🤔 Value `\(option)` is not allowed")
            }
        }
    }
    
    // MARK: property wrappers -
    @Argument(help: "`all` string will delete all cases")
    private var all: String?
    
    @Option(name: .shortAndLong, help: "Select directory to delete his data!")
    private var delete: Int?
    
    @Flag(name: .shortAndLong, help: "Show extra logging for debugging purposes.")
    private var verbose: Bool = false
    
    // MARK: Main run -
    
    mutating func run() throws {
        let next = try deleteAll()
        guard next else {
            isDone = true
            return
        }
        
        let optionInput = try pickOption()
        Print.withColor(.cyan, "Wait... 🙏")
        
        switch optionInput {
        case .simultorsData:
            try deleteSimulatorsData()
        case .derivedData, .archives, .simulatorsCache, .previews:
            let command = try optionInput.shellCommand()
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
        try deleteSimulatorsData()
        Print.withColor(.green, "Simulators data deleted...")
        
        try (2...5).forEach {
            do {
                let option = try OptionInput(value: $0).shellCommand()
                Print.withColor(.white, "\(option)")
                shell(option)
                Print.withColor(.green, "Done...")
            } catch {
                Print.withColor(.magenta, "avp error \(error.localizedDescription)")
                throw error.localizedDescription
            }
        }
        return false
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
            let url = documentsDirectory.appendingPathComponent(
                "Developer/CoreSimulator/Devices",
                isDirectory: true
            )
            let subDirectories = try url.subDirectories()
            subDirectories.forEach {
                shell("xcrun simctl erase \($0.lastPathComponent)")
                shell("rm '~/Library/Developer/CoreSimulator/Devices\($0.lastPathComponent)'/data/Documents")
            }
        } catch {
            throw "Can't delete simulators data \(#function)"
        }
    }
}

// MARK: Options -

extension Clean {
    
    enum OptionInput: Int, CaseIterable {
        case simultorsData, derivedData, archives, simulatorsCache, previews
        // XCTestDevices, XCPGDevices && Xcode/iOS DeviceSupport
        init(value: Int) throws {
            switch value {
            case 1: self = .simultorsData
            case 2: self = .derivedData
            case 3: self = .archives
            case 4: self = .simulatorsCache
            case 5: self = .previews
            default: throw "Manage this case \(value)"
            }
        }
        init?(rawValue: Int) { fatalError("use `init(value: Int) throws`") }
        
        func shellCommand() throws -> String {
            switch self {
            case .derivedData: return "rm -rf ~/Library/Developer/Xcode/DerivedData"
            case .archives: return "rm -rf ~/Library/Developer/Xcode/Archives"
            case .simulatorsCache: return "rm -rf ~/Library/Developer/CoreSimulator/Caches/dyld"
            case .previews: return "~/Library/Developer/Xcode/UserData/Previews/Simulator Devices"
            case .simultorsData: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
            }
        }
    }
}

// MARK: Text descriptions -

private extension Clean {
    var optionsMessage: String {
"""
Enter input `number` to clean desired folder:
1 -> Simulators Data
2 -> Derived Data
3 -> Archives
4 -> Simulators Caches
5 -> Previews
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

//                Print.withColor(.green, "run: `sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService`")
