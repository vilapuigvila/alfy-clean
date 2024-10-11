//
//  File.swift
//  
//
//  Created by albert vila on 6/2/22.
//

import Foundation

extension URL {
    func subDirectories() throws -> [URL] {
        if #available(macOS 10.11, *) {
            guard hasDirectoryPath else {
                throw "macOS not available  \(#function)"
            }
        } else {
            throw "macOS not available  \(#function)"
        }
        if #available(macOS 10.11, *) {
            guard let items = try? FileManager
                .default
                .contentsOfDirectory(
                    at: self,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ).filter(\.hasDirectoryPath)
            else {
                throw "macOS not available  \(#function)"
            }
            return items
        } else {
            throw "macOS not available  \(#function)"
        }
    }
//    throw "macOS not available  \(#function)"
}
