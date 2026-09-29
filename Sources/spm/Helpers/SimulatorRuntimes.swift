//
//  SimulatorRuntimes.swift
//
//  Lists and deletes installed simulator runtimes via `xcrun simctl runtime`.
//

import Foundation

struct SimulatorRuntime: Decodable {
    let identifier: String
    let version: String
    let build: String
    let platformIdentifier: String
    let sizeBytes: UInt64
    let deletable: Bool
    let lastUsedAt: String?

    /// e.g. "iOS 18.4 (22E238)"
    var name: String {
        let platform = platformIdentifier
            .replacingOccurrences(of: "com.apple.platform.", with: "")
            .replacingOccurrences(of: "simulator", with: "")
        let displayPlatform: String
        switch platform {
        case "iphone": displayPlatform = "iOS"
        case "appletv": displayPlatform = "tvOS"
        case "watch": displayPlatform = "watchOS"
        case "xr": displayPlatform = "visionOS"
        default: displayPlatform = platform
        }
        return "\(displayPlatform) \(version) (\(build))"
    }

    /// e.g. "2026-09-28"
    var lastUsedDay: String? {
        lastUsedAt.map { String($0.prefix(10)) }
    }
}

struct SimulatorRuntimes {
    /// Deletable runtimes, sorted by version (oldest first). Empty if `simctl` fails.
    static func list() -> [SimulatorRuntime] {
        let result = shell("xcrun simctl runtime list -j 2>/dev/null")
        guard result.success,
              let data = result.output.data(using: .utf8),
              let runtimes = try? JSONDecoder().decode([String: SimulatorRuntime].self, from: data) else {
            return []
        }

        return runtimes.values
            .filter { $0.deletable }
            .sorted { $0.version.compare($1.version, options: .numeric) == .orderedAscending }
    }

    static func delete(_ runtime: SimulatorRuntime) -> ShellResult {
        shell("xcrun simctl runtime delete \(runtime.identifier)")
    }
}
