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
    case bold = "\u{001B}[1m"
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
    static func withColor(_ color: Color, _ output: String) {
        print("\(color.rawValue)\(output)\(Color.reset.rawValue)")
    }
    static func keepingLine(_ output: String, _ color: Color) {
        print("\(color.rawValue)\u{1B}[1A\u{1B}[K\(output)")
    }
}

extension String {
    /// Control characters (C0, DEL, C1) replaced with "?", so a crafted file or simulator name can't move
    /// the cursor, recolor or rewrite what the terminal shows. Use on any name that didn't come from alfy-clean.
    var terminalSafe: String {
        var result = String.UnicodeScalarView()
        for scalar in unicodeScalars {
            let isControl = scalar.value < 0x20 || (0x7F...0x9F).contains(scalar.value)
            result.append(isControl ? "?" : scalar)
        }
        return String(result)
    }
}
