//
//  SystemScanner.swift
//
//  Scans system folders for large items and provides formatted output.
//

import Foundation

struct SystemScanner {
    /// Scans system folders for directories larger than 5GB, removes parent folders, and returns formatted output.
    /// Returns empty string if scan fails.
    static func listLargeFolders() -> String {
        let command = buildScanCommand()
        let task = Process()
        let pipe = Pipe()

        task.standardOutput = pipe
        task.standardError = pipe
        task.arguments = ["-c", command]
        task.launchPath = "/bin/zsh"

        do {
            try task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            return output.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return ""
        }
    }

    /// Folders left out of the scan. Their size is subtracted from every parent that contains them,
    /// so a parent like /Library/Developer/CoreSimulator doesn't keep showing the excluded bytes.
    static let excludedPaths = [
        "/Library/Developer/CoreSimulator/Volumes",
        "/Library/Developer/CoreSimulator/Cryptex",
        "/Library/Developer/CoreSimulator/Caches/dyld",
        "/private/var",
        "/Applications/Xcode.app/Contents",
    ]

    /// Builds shell command to scan folders, deduplicate parents, and format output.
    /// The awk script drops excluded folders, subtracts their size from parents, and filters out parent folders
    /// when a child folder > 5GB exists in the result set.
    /// Results are sorted by size descending and limited to top 50.
    private static func buildScanCommand() -> String {
        """
        /usr/bin/du -k /Applications /Library "$HOME/Library" /private /opt /usr/local 2>/dev/null | \
        /usr/bin/awk -v excluded="\(excludedPaths.joined(separator: "|"))" 'BEGIN { FS="\\t"; OFS=" "; n = split(excluded, ex, "|") } {
          if (NF == 2) {
            path = $2
          } else {
            path = $0; sub(/^[0-9]+[[:space:]]+/, "", path)
          }
          # /System/Volumes/Data/X is the same data as /X (firmlinks): report it once, as /X.
          # The volume root itself is the whole data disk, never a useful result.
          if (path == "/System/Volumes/Data") next
          if (index(path, "/System/Volumes/Data/") == 1) {
            path = substr(path, 21)
          }
          if (path in seen) next
          seen[path] = 1
          # Excluded folders (and everything inside them) are dropped; their own size is kept for the parents.
          skip = 0
          for (i = 1; i <= n; i++) {
            if (path == ex[i]) excludedSize[path] = $1
            if (path == ex[i] || index(path, ex[i] "/") == 1) { skip = 1; break }
          }
          if (skip) next
          count++
          paths[count] = path
          sizes[count] = $1
        }
        END {
          for (k = 1; k <= count; k++) {
            size = sizes[k] + 0
            for (e in excludedSize) {
              if (index(e, paths[k] "/") == 1) size -= excludedSize[e]
            }
            if (size < 4882813) continue
            kept++
            keptPath[kept] = paths[k]
            keptSize[kept] = size
          }
          for (i = 1; i <= kept; i++) {
            is_parent = 0
            for (j = 1; j <= kept; j++) {
              if (i != j && substr(keptPath[j], 1, length(keptPath[i])+1) == keptPath[i] "/") {
                is_parent = 1
                break
              }
            }
            if (!is_parent) print keptSize[i] " " keptPath[i]
          }
        }' | \
        /usr/bin/sort -rn | \
        /usr/bin/head -50 | \
        /usr/bin/awk '{ size=$1; $1=""; sub(/^ /, ""); printf "  %.1f GB  %s\\n", size * 1024 / 1000000000, $0 }'
        """
    }
}

// MARK: Safe-to-delete candidates -

extension SystemScanner {
    struct LargeFolder {
        let path: String
        let gigabytes: Double
        /// Shown next to the folder in the delete checklist.
        let note: String
    }

    /// Parses `listLargeFolders()` output ("  12.2 GB  /path") and keeps only folders that are safe to
    /// delete without sudo: their contents are rebuilt or re-downloaded on demand.
    static func safeToDelete(from output: String) -> [LargeFolder] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " GB  ")
            guard parts.count == 2, let gigabytes = Double(parts[0]) else { return nil }
            let path = parts[1]
            guard let note = safeDeleteNote(for: path) else { return nil }
            return LargeFolder(path: path, gigabytes: gigabytes, note: note)
        }
    }

    /// Returns why `path` is safe to delete, or `nil` when it isn't on the allowlist.
    /// Also used to re-check each path right before deleting it.
    static func safeDeleteNote(for path: String) -> String? {
        let home = NSHomeDirectory()
        // Match the scan's real paths as-is (standardizingPath would turn /private/tmp into /tmp),
        // and refuse anything that could climb out of an allowed folder.
        let standardized = path
        let components = (standardized as NSString).pathComponents
        guard standardized.hasPrefix("/"), !components.contains("..") else { return nil }

        if standardized.hasPrefix(home + "/"), components.contains("DerivedData") {
            return "build output, rebuilt on next build"
        }

        let deviceDeltas = home + "/Library/Containers/com.apple.CoreDevice.CoreDeviceService/Data/Library/Caches/AppInstallationBinaryDeltas/"
        if standardized.hasPrefix(deviceDeltas) {
            return "device install cache, next device install is a full one"
        }

        let claudeTemp = "/private/tmp/claude-\(getuid())/"
        if standardized.hasPrefix(claudeTemp), standardized.count > claudeTemp.count {
            return "⚠️ Claude Code temp files, only if no Claude session is running there"
        }

        return nil
    }
}
