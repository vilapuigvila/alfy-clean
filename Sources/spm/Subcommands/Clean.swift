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
        abstract: "Clean folders",
        subcommands: [
            Delete.self
        ]
    )
}

extension Clean {
    struct Delete: ParsableCommand {
        enum OptionInput: Int, CaseIterable {
            case derivedData, archives, simultorsData, simulatorsCache
            init?(rawValue: Int) { fatalError("use `init(value: Int) throws`") }
            
            init(value: Int) throws {
                switch value {
                case 1: self = .derivedData
                case 2: self = .archives
                case 3: self = .simultorsData
                case 4: self = .simulatorsCache
                default: throw "Manage this case \(value)"
                }
            }
            func shellCommand() throws -> String {
                switch self {
                case .derivedData: return "rm -rf ~/Library/Developer/Xcode/DerivedData"
                case .archives: return "rm -rf ~/Library/Developer/Xcode/Archives"
                case .simulatorsCache: return "rm -rf ~/Library/Developer/CoreSimulator/Caches/dyld"
                case .simultorsData: throw "🔥 `\(self.rawValue)` Doesn't have a shell command"
                }
            }
        }
        static var foldersName: String {
            return Cache.CacheFolder.allCases.map { $0.rawValue }.joined(separator: " or ")
        }
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
        
        @Option(name: .shortAndLong, help: "Select folder to delete his data!")
        private var delete: Int?
        
        @Flag(name: .shortAndLong, help: "Show extra logging for debugging purposes.")
        private var verbose: Bool = false
        
        // MARK: Main run -
        mutating func run() throws {
            Print.h3(optionsMessage)
            let optionInput = try pickOption()
            
            Print.withColor(.cyan, "Wait... 🙏")
            switch optionInput {
            case .simultorsData:
                try deleteSimulatorsData()
            case .derivedData, .archives, .simulatorsCache:
                let command = try optionInput.shellCommand()
                shell(command)
            }
            isDone = true
            Print.withColor(.green, "job done! 🍻")
            
            while(!isDone) {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            }
        }
        
        // MARK: helpers -
        
        private mutating func pickOption() throws -> OptionInput {
            if let shortOption = delete {
                option = shortOption
            } else {
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
                }
            } catch {
                throw "Can't delete simulators data \(#function)"
            }
        }
        
        private var optionsMessage: String {
"""
            Enter input to clean desired folder:
            1 -> Derived Data
            2 -> Archives
            3 -> Simulators
            4 -> Simulators caches
            5 -> Previews
            6 -> Devices
"""
        }
        
        private static var configMessage: String {
"""
            Delete shit data of your developer folder,
            folders list:
            \(foldersName) 🥳
"""
        }
    }
}

//                Print.withColor(.green, "run: `sudo killall -9 com.apple.CoreSimulator.CoreSimulatorService`")
