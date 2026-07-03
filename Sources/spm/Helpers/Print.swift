//
//  File.swift
//  
//
//  Created by albert vila puigvila on 4/2/22.
//

import Foundation

struct Print {
  enum Color: String {
    case reset = "\u{001B}[0;0m"
    case dim = "\u{001B}[2m"
    case black = "\u{001B}[0;30m"
    case red = "\u{001B}[0;31m"
    case green = "\u{001B}[0;32m"
    case boldGreen = "\u{001B}[1;32m"
    case yellow = "\u{001B}[0;33m"
    case blue = "\u{001B}[0;34m"
    case magenta = "\u{001B}[0;35m"
    case cyan = "\u{001B}[0;36m"
    case white = "\u{001B}[0;37m"
  }
    static func h3(_ items: Any..., separator: String = " ", terminator: String = "\n") {
      // https://stackoverflow.com/questions/39026752/swift-extending-functionality-of-print-function
      let output = items.map { "\($0)" }.joined(separator: separator)
      print("\(Color.green.rawValue)\(output)\(Color.reset.rawValue)")
    }

    static func h6(_ verbose: Bool, _ items: Any..., separator: String = " ", terminator: String = "\n") {
      if verbose {
        let output = items.map { "\($0)" }.joined(separator: separator)
        print("\(output)")
      }
    }
    static func withColor(_ color: Color, _ output: String) {
        print("\(color.rawValue)\(output)\(Color.reset.rawValue)")
    }
    static func keepingLine(_ output: String, _ color: Color) {
        print("\(color.rawValue)\u{1B}[1A\u{1B}[K\(output)")
    }
}
