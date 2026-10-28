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

struct AlfyClean: ParsableCommand {
  public static let configuration = CommandConfiguration(
    abstract: "alfy-clean helper",
    version: "alfy-clean version \(Constant.App.version)",
    subcommands: [Clean.self],
    defaultSubcommand: Clean.self
  )
}

// MARK: Run Main program -

AlfyClean.main()
