//
//  XcodeBuild.swift
//  
//
//  Created by albert vila puigvila on 18/5/22.
//

import Foundation
import ArgumentParser

struct XcodeBuild: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: configMessage
    )
    
    func run() throws {
        
    }
    
    static var configMessage: String {
"""
Some helper commands to check diffents things of your xcode projects like:,
- buildWithTimingSummary:
"""
    }
}

