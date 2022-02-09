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
        enum OptionInput: Int {
            case derivedData, simultorsData, archives, simulatorsCache
            init(value: Int) throws {
                switch value {
                case 0: self = .derivedData
                case 1: self = .simultorsData
                case 2: self = .archives
                case 3: self = .simulatorsCache
                default: throw "Manage this case \(value)"
                }
            }
            func shellCommand() throws -> String {
                switch self {
                case .derivedData: return "rm -rf ~/Library/Developer/Xcode/DerivedData"
                case .archives: return "rm -rf ~/Library/Developer/Xcode/Archives"
                case .simulatorsCache: return "rm -rf ~/Library/Developer/CoreSimulator/Caches/dyld"
                case .simultorsData: fatalError("Doesn't have a shell command")
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
                if !(1...6).contains(option) {
                    fatalError("🤔 Value `\(option)` is not allowed")
                }
            }
        }
        
        @Option(name: .shortAndLong, help: "Select folder to delete his data!")
        private var delete: Int?
        
        @Flag(name: .shortAndLong, help: "Show extra logging for debugging purposes.")
        private var verbose: Bool = false
        
        mutating func run() throws {
            Print.h3(optionsMessage)
//                deleteSimulatorsData()
            let optionInput = try pickOption()
            
            switch optionInput {
            case .derivedData:
                break
            case .simultorsData: break
            case .archives: break
            case .simulatorsCache: break
            }
            
            func shellCommand() throws -> String {
                switch option {
                case 1: return "rm -rf ~/Library/Developer/Xcode/DerivedData"
                case 2: return "for i in {1..5}; do; echo 'Welcome $i times'; done"
                case 3: return "rm -rf ~/Library/Developer/Xcode/Archives"
                case 5: return "rm -rf ~/Library/Developer/CoreSimulator/Caches/dyld"
                default: throw "NOT ALLOWED AT THIS MOMENT 🔥"
                }
            }
            Print.withColor(.cyan, "Wait... 🙏")
//            let command = try shellCommand()
//            shell(command)
            Print.withColor(.green, "job done! 🍻")
            isDone = true
            
            while(!isDone) {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            }
        }
        
        private mutating func pickOption() throws -> OptionInput {
            if let shortOption = delete {
                option = shortOption
            } else {
                let name = try keyboardInput()
                option = (name as NSString).integerValue
            }
            guard let optionInput = try? OptionInput(value: option) else {
                throw "error"
            }
            return optionInput
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
                url.subDirectories().forEach {
                    shell("xcrun simctl erase \($0.lastPathComponent)")
                }
            } catch {
                fatalError()
            }
        }
        
        private var optionsMessage: String {
"""
            Enter input to clean desired folder:
            1 -> Derived Data
            2 -> Archives
            3 -> Simulators
            4 -> Previews
            5 -> Simulators caches
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
