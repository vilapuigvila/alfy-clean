//
//  main.swift
//
//
//  Created by albert vila puigvila on 1/2/22.
//

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

fileprivate class TimerWrapper: NSObject {
    private var runCount: Int = 0
    private var timer: Timer?
    
    func fireTimer() throws {
        if #available(macOS 10.12, *) {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                self.runCount = self.runCount == 4 ? 0 : self.runCount
                var text: String {
                    switch self.runCount {
                    case 0: return "Wait."
                    case 1: return "Wait.."
                    case 2: return "Wait..."
                    case 3: return "🙏 🙏 🙏"
                    default: fatalError("glups..") }
                }
                Print.keepingLine(text, .magenta)
                self.runCount += 1
            }
            RunLoop.current.run(mode: .default, before: .distantFuture)
        } else {
            throw "check macOS version"
        }
    }
    func stopTimer() {
        fflush(__stdoutp)
        timer?.invalidate()
        timer = nil
    }
}

Avp.main()
