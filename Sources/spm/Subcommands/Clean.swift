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
        static var foldersName: String {
            return Cache.CacheFolder.allCases.map { $0.rawValue }.joined(separator: " or ")
        }
        public static let configuration = CommandConfiguration(
            abstract:
"""
Delete shit data of your developer folder,
folders list:
\(foldersName) 🥳
"""
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
            Print.h3(options)
            
            if let shortOption = delete {
                option = shortOption
            } else {
                let name = try keyboardInput()
                option = (name as NSString).integerValue
            }
//            let ttt = TimerWrapper()
            
            func shellCommand() throws -> String {
                switch option {
                case 1: return "rm -rf ~/Library/Developer/Xcode/DerivedData"
                case 2: return "rm -rf ~/Library/Developer/Xcode/Archives"
                case 5: return "rm -rf ~/Library/Developer/CoreSimulator/Caches/dyld"
                default: throw "NOT ALLOWED AT THIS MOMENT 🔥"
                }
            }
            Print.withColor(.cyan, "Wait... 🙏")
            let command = try shellCommand()
            shell(command)
            Print.withColor(.green, "job done! 🍻")
            isDone = true
            
            while(!isDone) {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            }
        }
        private var options: String {
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
    }
}
