//
//  SimulatorDevices.swift
//
//  Lists and erases the simulators in Xcode's default device set via `xcrun simctl`.
//

import Foundation

struct SimulatorDevice: Decodable {
    let udid: String
    /// User-editable, so made `terminalSafe` in `list()` before it's ever printed.
    var name: String
    let state: String
    let isAvailable: Bool
    let dataPath: String
    /// Filled in from the runtime key of `simctl list devices -j`, e.g. "iOS 26.4".
    var runtime: String = ""

    var isBooted: Bool { state == "Booted" }

    private enum CodingKeys: String, CodingKey {
        case udid, name, state, isAvailable, dataPath
    }
}

struct SimulatorDevices {
    /// Available devices in the default set. Empty if `simctl` fails.
    static func list() -> [SimulatorDevice] {
        struct DeviceList: Decodable {
            let devices: [String: [SimulatorDevice]]
        }

        let result = simctl(["list", "devices", "-j"], errorOutput: .discarded)
        guard result.success,
              let data = result.output.data(using: .utf8),
              let list = try? JSONDecoder().decode(DeviceList.self, from: data) else {
            return []
        }

        return list.devices.flatMap { runtimeIdentifier, devices in
            devices
                .filter { $0.isAvailable }
                .map { device -> SimulatorDevice in
                    var device = device
                    device.name = device.name.terminalSafe
                    device.runtime = runtimeName(runtimeIdentifier).terminalSafe
                    return device
                }
        }
    }

    /// Shuts the device down if it's running, then erases it (apps, data, keychain, settings).
    static func erase(_ device: SimulatorDevice) -> ShellResult {
        if device.isBooted {
            let shutdown = simctl(["shutdown", device.udid])
            guard shutdown.success else { return shutdown }
        }
        return simctl(["erase", device.udid])
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-26-4" -> "iOS 26.4"
    private static func runtimeName(_ identifier: String) -> String {
        let suffix = identifier.components(separatedBy: ".").last ?? identifier
        var parts = suffix.components(separatedBy: "-")
        guard parts.count > 1 else { return suffix }
        let platform = parts.removeFirst()
        return "\(platform) \(parts.joined(separator: "."))"
    }
}
