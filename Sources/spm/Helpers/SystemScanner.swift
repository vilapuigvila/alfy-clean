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

    /// Builds shell command to scan folders, deduplicate parents, and format output.
    /// The awk script filters out parent folders when a child folder > 5GB exists in the result set.
    /// Results are sorted by size descending and limited to top 50.
    private static func buildScanCommand() -> String {
        """
        /usr/bin/du -k /Applications /Library /System "$HOME/Library" /private /opt /usr/local 2>/dev/null | \
        /usr/bin/awk 'BEGIN { FS="\\t"; OFS=" " } $1 >= 5242880 {
          if (NF == 2) {
            paths[NR] = $2
          } else {
            path = $0; sub(/^[0-9]+[[:space:]]+/, "", path)
            paths[NR] = path
          }
          sizes[NR] = $1
        }
        END {
          for (i in paths) {
            is_parent = 0
            for (j in paths) {
              if (i != j) {
                if (substr(paths[j], 1, length(paths[i])+1) == paths[i] "/") {
                  is_parent = 1
                  break
                }
              }
            }
            if (!is_parent) {
              print sizes[i] " " paths[i]
            }
          }
        }' | \
        /usr/bin/sort -rn | \
        /usr/bin/head -50 | \
        /usr/bin/awk '{ size=$1; $1=""; sub(/^ /, ""); printf "  %.1f GB  %s\\n", size / 1048576, $0 }'
        """
    }
}
