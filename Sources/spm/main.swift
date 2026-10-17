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
    static let version = "0.0.2"
  }
}

struct Avp: ParsableCommand {
  public static let configuration = CommandConfiguration(
    abstract: "avp helper",
    version: "avp version \(Constant.App.version)",
    subcommands: [
        Cache.self, Clean.self, WorktreeClean.self
    ]
  )
}

// MARK: Run Main program -

Avp.main()
