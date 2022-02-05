//print("Hello, world!")

import Foundation
import ArgumentParser

struct Constant {
  struct App {
    static let version = "0.0.1"
  }
}

struct Avp: ParsableCommand {
  public static let configuration = CommandConfiguration(
    abstract: "avp helper",
    version: "avp version \(Constant.App.version)",
    subcommands: [
        Cache.self, Clean.self
    ]
  )
}

extension Avp {
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

fileprivate extension Avp.CacheFolder {
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
  
  static var suggestion: String {
    let suggestion = Self.allCases
          .map { $0.rawValue }
          .joined(separator: " | ")
    return "[ \(suggestion) ]"
  }
}

extension Avp.Cache {
  struct List: ParsableCommand {
    public static let configuration = CommandConfiguration(
      abstract: "Show Xcode cache files"
    )
    
    @Option(name: .shortAndLong, help: "The cache folder")
    private var cacheFolder: Avp.CacheFolder = .all
    
    @Flag(name: .shortAndLong, help: "Show extra logging for debugging purposes.")
    private var verbose: Bool = false
    
    func run() throws {
      Print.h3("list cache files:")
      Print.h3("------------------------")
      
      if cacheFolder == .all {
        var allCases = Avp.CacheFolder.allCases
        allCases.remove(at: allCases.firstIndex(of: .all)!)
        handleList(allCases)
      } else {
        handleList([cacheFolder])
      }
    }
    
    private func handleList(_ folders: [Avp.CacheFolder]) {
      for folder in folders {
        Print.h3(folder.rawValue)
        for path in folder.paths {
          let cmd = "du -hs \(path)"
          Print.h6(verbose, cmd)
          let output =  shell(cmd)
          print(output)
        }
      }
    }
  }
}

extension Avp {
    struct Cache: ParsableCommand {
      public static let configuration = CommandConfiguration(
        abstract: "Xcode cache helper",
        subcommands: [
            List.self
        ]
      )
    }
}

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
            return Avp.CacheFolder.allCases.map { $0.rawValue }.joined(separator: " or ")
        }
        public static let configuration = CommandConfiguration(
            abstract:
"""
Delete shit data of your developer Folder like:
\(foldersName) 🥳
"""
        )
        private var isDone: Bool = false
        
        @Option(name: .shortAndLong, help: "Select folder to delete his data!")
        private var delete: Int
        
        @Flag(name: .shortAndLong, help: "Show extra logging for debugging purposes.")
        private var verbose: Bool = false
        
        mutating func run() throws {
            Print.h3(
"""
Select one input to clean folder:
1 - Derived Data
2 - Archives
3 - Simulators
4 - Previews
5 - Simulators caches
6 - Devices
""")
            while(!isDone) {
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            }
            switch delete {
            case 1:
                shell("rm -rf ~/Library/Developer/Xcode/DerivedData")
                isDone = true
            default: break
            }
            
        }
    }
}

Avp.main()
