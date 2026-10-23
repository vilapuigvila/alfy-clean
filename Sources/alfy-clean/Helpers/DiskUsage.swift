//
//  DiskUsage.swift
//
//  Accurate folder sizes measured with `du -sk` (1024-byte blocks), reported in bytes.
//  `du` counts a block once per APFS clone, so for clone-heavy folders `measureReclaimable` is used instead.
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

        let errorFile = NSTemporaryDirectory() + "alfy-clean-du-\(UUID().uuidString).err"
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

    /// Folders made of APFS clones (Xcode clones the simulator for parallel tests and previews). `du` counts the
    /// blocks they share with the source device once per clone, so their `du` size is far above what deleting frees.
    static let cloneFolders = [
        "~/Library/Developer/XCTestDevices",
        "~/Library/Developer/XCPGDevices"
    ]

    /// Like `measure`, but counts only the bytes that deleting the path really frees: the part of each file
    /// that no other file (clone) shares. Missing paths are `.zero`. Falls back to the allocated size on
    /// volumes without clone support.
    static func measureReclaimable(paths: [String]) -> [String: DiskUsage] {
        var result: [String: DiskUsage] = [:]
        for path in paths {
            let expanded = (path as NSString).expandingTildeInPath
            result[path] = FileManager.default.fileExists(atPath: expanded) ? privateUsage(at: expanded) : .zero
        }
        return result
    }

    private static func privateUsage(at root: String) -> DiskUsage {
        var total: UInt64 = 0
        var isPartial = false

        guard let rootPath = strdup(root) else { return DiskUsage(bytes: 0, isPartial: true) }
        defer { free(rootPath) }
        var argv: [UnsafeMutablePointer<CChar>?] = [rootPath, nil]
        guard let tree = fts_open(&argv, FTS_PHYSICAL | FTS_NOCHDIR, nil) else {
            return DiskUsage(bytes: 0, isPartial: true)
        }
        defer { fts_close(tree) }

        while let entry = fts_read(tree) {
            switch Int32(entry.pointee.fts_info) {
            case FTS_F:
                total += privateBytes(ofFile: entry.pointee.fts_path, allocated: entry.pointee.fts_statp.pointee.st_blocks)
            case FTS_DNR, FTS_ERR, FTS_NS:
                isPartial = true
            default:
                break
            }
        }
        return DiskUsage(bytes: total, isPartial: isPartial)
    }

    /// `ATTR_CMNEXT_PRIVATESIZE`: bytes of the file not shared with any clone.
    private static func privateBytes(ofFile path: UnsafeMutablePointer<CChar>!, allocated blocks: Int64) -> UInt64 {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        // Reply: a UInt32 length, then the packed off_t value.
        var reply = [UInt8](repeating: 0, count: MemoryLayout<UInt32>.size + MemoryLayout<Int64>.size)
        let status = reply.withUnsafeMutableBytes {
            getattrlist(path, &request, $0.baseAddress, $0.count, UInt32(FSOPT_NOFOLLOW | FSOPT_ATTR_CMN_EXTENDED))
        }
        guard status == 0 else { return UInt64(max(blocks, 0)) * 512 }
        var value: Int64 = 0
        memcpy(&value, Array(reply[MemoryLayout<UInt32>.size...]), MemoryLayout<Int64>.size)
        return UInt64(max(value, 0))
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
