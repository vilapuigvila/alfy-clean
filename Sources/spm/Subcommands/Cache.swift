//
//  File.swift
//  
//
//  Created by albert vila on 6/2/22.
//

import Foundation
import ArgumentParser

struct Cache: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Xcode cache helper",
        subcommands: [
            List.self
        ]
    )
}

extension Cache {
    enum CacheFolder: String, ExpressibleByArgument, CaseIterable {
        case all
        case archives
        case simulators
        case deviceSupport
        case derivedData
        case previews
        case coreSimulatorCaches
    }
}

extension Cache.CacheFolder {
    var paths: [String] {
        switch self {
        case .archives:
            return ["~/Library/Developer/Xcode/Archives"]
        case .simulators:
            return ["~/Library/Developer/CoreSimulator/Devices"]
        case .deviceSupport:
            return ["~/Library/Developer/Xcode"]
        case .derivedData:
            return ["~/Library/Developer/Xcode/DerivedData"]
        case .previews:
            return ["~/Library/Developer/Xcode/UserData/Previews/Simulator Devices"]
        case .coreSimulatorCaches:
            return ["~/Library/Developer/CoreSimulator/Caches/dyld"]
        case .all:
            var paths: [String] = []
            for caseValue in Self.allCases {
                if caseValue != self {
                    paths.append(contentsOf: caseValue.paths)
                }
            }
            return paths
        }
    }
}
  

extension Cache {
    struct List: ParsableCommand {
        public static let configuration = CommandConfiguration(
            abstract: "Show Xcode cache files"
        )
        
        @Option(name: .shortAndLong, help: "The cache folder")
        private var cacheFolder: Cache.CacheFolder = .all
        
        @Flag(name: .shortAndLong, help: "Show extra logging for debugging purposes.")
        private var verbose: Bool = false
        
        func run() throws {
            Print.h3("list cache files:")
            Print.h3("------------------------")
            
            if cacheFolder == .all {
                var allCases = Cache.CacheFolder.allCases
                allCases.remove(at: allCases.firstIndex(of: .all)!)
                handleList(allCases)
            } else {
                handleList([cacheFolder])
            }
        }
        
        private func handleList(_ folders: [Cache.CacheFolder]) {
            for folder in folders {
                Print.h3(folder.rawValue)
                for path in folder.paths {
                    let cmd = "du -hs \(path)"
                    Print.h6(verbose, cmd)
                    let output = shell(cmd)
                    print(output)
                }
            }
        }
    }
}
    
    //private static var suggestion: String {
    //    let suggestion = Self.allCases
    //          .map { $0.rawValue }
    //          .joined(separator: " | ")
    //        return "[ \(suggestion) ]"
    //    }
    //}
