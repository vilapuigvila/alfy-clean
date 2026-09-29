//
//  DiskUsage.swift
//
//  Accurate folder sizes measured with `du -sk` (1024-byte blocks), reported in bytes.
//

import Foundation

struct DiskUsage {
    let bytes: UInt64
    /// `true` when `du` could not read part of the folder, so `bytes` is a lower bound.
    let isPartial: Bool

    static let zero = DiskUsage(bytes: 0, isPartial: false)

    /// Runs `du -sk` once on every existing path and returns the usage keyed by the original path string.
    /// Missing paths are reported as `.zero`. Paths are passed as arguments, so spaces need no quoting.
    static func measure(paths: [String]) -> [String: DiskUsage] {
        var result: [String: DiskUsage] = [:]
        var expandedToOriginal: [String: [String]] = [:]

        for path in paths {
            let expanded = (path as NSString).expandingTildeInPath
            if FileManager.default.fileExists(atPath: expanded) {
                expandedToOriginal[expanded, default: []].append(path)
            } else {
                result[path] = .zero
            }
        }

        let expandedPaths = expandedToOriginal.keys.sorted()
        guard !expandedPaths.isEmpty else { return result }

        let errorFile = NSTemporaryDirectory() + "avp-du-\(UUID().uuidString).err"
        FileManager.default.createFile(atPath: errorFile, contents: nil)
        defer { try? FileManager.default.removeItem(atPath: errorFile) }

        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/du")
        task.arguments = ["-sk"] + expandedPaths
        task.standardOutput = pipe
        task.standardError = FileHandle(forWritingAtPath: errorFile) ?? FileHandle.nullDevice

        var output = ""
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            output = String(data: data, encoding: .utf8) ?? ""
        } catch {
            for (_, originals) in expandedToOriginal {
                for original in originals { result[original] = .zero }
            }
            return result
        }

        var kilobytesByPath: [String: UInt64] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2, let kb = UInt64(parts[0].trimmingCharacters(in: .whitespaces)) else { continue }
            kilobytesByPath[String(parts[1])] = kb
        }

        let errors = ((try? String(contentsOfFile: errorFile, encoding: .utf8)) ?? "")
            .split(separator: "\n").map(String.init)

        for (expanded, originals) in expandedToOriginal {
            let usage = DiskUsage(
                bytes: (kilobytesByPath[expanded] ?? 0) * 1024,
                isPartial: errors.contains { $0.hasPrefix("du: \(expanded)/") || $0.hasPrefix("du: \(expanded):") }
            )
            for original in originals { result[original] = usage }
        }
        return result
    }

    /// Finder-style decimal units: 1 GB = 1,000,000,000 bytes.
    static func format(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if value >= 1_000_000_000 {
            return String(format: "%.1f GB", value / 1_000_000_000)
        }
        return String(format: "%.0f MB", value / 1_000_000)
    }
}
