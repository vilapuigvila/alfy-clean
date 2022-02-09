//
//  File.swift
//  
//
//  Created by albert vila on 6/2/22.
//

import Foundation

extension String: Error { }

extension URL {
    func subDirectories() -> [URL] {
        if #available(macOS 10.11, *) {
            guard hasDirectoryPath else { return [] }
        } else {
            fatalError()
            return []
        }
        if #available(macOS 10.11, *) {
            guard let items = try? FileManager.default.contentsOfDirectory(at: self, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]).filter(\.hasDirectoryPath) else {
                return []
            }
            return items
        } else {
            fatalError()
            return []
        }
    }
}
