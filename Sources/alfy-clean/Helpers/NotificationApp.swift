//
//  NotificationApp.swift
//
//  macOS takes the icon on the left of a notification from the app that sends it, and nothing can override it per
//  notification. So alfy-clean keeps its own copy of terminal-notifier.app, with the alfy-clean logo as its icon,
//  in ~/.local/share/alfy-clean/. It is built once, the first time a notification is sent, and used from then on.
//  macOS asks once to allow notifications from this copy, because it has a bundle ID of its own.
//

import Foundation

enum NotificationApp {
    /// Kept apart from terminal-notifier's own ID: that is what gives the copy its own icon and permission.
    static let bundleIdentifier = "fr.julienxx.oss.terminal-notifier.alfy-clean-logo"
    static let appName = "alfy-clean"
    /// Where Homebrew puts terminal-notifier.
    static let homebrewNotifierPaths = ["/opt/homebrew/bin/terminal-notifier", "/usr/local/bin/terminal-notifier"]

    static var defaultAppPath: String {
        expandTilde("~/.local/share/alfy-clean/alfy-clean-notifier.app")
    }

    /// Set once building has failed, so a missing terminal-notifier or a failing tool isn't retried on every notification.
    private static var buildFailed = false

    /// The program inside the logo app, building the app first when it doesn't exist. An app that is already there with
    /// our bundle ID is used as it is: rebuilding re-signs it, and macOS can then forget that its notifications were
    /// allowed. Nil when terminal-notifier isn't installed or the app can't be built; callers fall back to the plain notifier.
    static func executablePath(appPath: String = defaultAppPath) -> String? {
        let executable = (appPath as NSString).appendingPathComponent("Contents/MacOS/terminal-notifier")
        if bundleID(ofApp: appPath) == bundleIdentifier, FileManager.default.isExecutableFile(atPath: executable) {
            return executable
        }
        guard !buildFailed else { return nil }
        guard let notifier = homebrewNotifierPaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }),
              let source = sourceApp(forNotifier: notifier),
              build(at: appPath, from: source),
              FileManager.default.isExecutableFile(atPath: executable) else {
            buildFailed = true
            return nil
        }
        return executable
    }

    /// terminal-notifier.app sits next to the real `bin/` folder of the formula (Homebrew's `bin/terminal-notifier`
    /// is a symlink into it). Nil when it isn't there.
    static func sourceApp(forNotifier binary: String) -> String? {
        let real = URL(fileURLWithPath: binary).resolvingSymlinksInPath()
        let app = real.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("terminal-notifier.app")
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: app.path, isDirectory: &isFolder), isFolder.boolValue else { return nil }
        return app.path
    }

    /// The app's Info.plist with alfy-clean's identity: its own bundle ID, and its name in Notification Center settings.
    static func brandedInfo(_ info: [String: Any]) -> [String: Any] {
        var branded = info
        branded["CFBundleIdentifier"] = bundleIdentifier
        branded["CFBundleName"] = appName
        branded["CFBundleDisplayName"] = appName
        return branded
    }

    private static func bundleID(ofApp appPath: String) -> String? {
        let plist = (appPath as NSString).appendingPathComponent("Contents/Info.plist")
        guard let data = FileManager.default.contents(atPath: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleIdentifier"] as? String
    }

    /// Copies `source` to `appPath`, swaps its icon for the logo, gives it alfy-clean's identity and signs it ad hoc.
    /// Built in a temporary folder and moved into place at the end, so a failure leaves nothing half-made.
    /// False if any step fails.
    @discardableResult
    static func build(at appPath: String, from source: String) -> Bool {
        let manager = FileManager.default
        let work = manager.temporaryDirectory.appendingPathComponent("alfy-clean-notifier-\(UUID().uuidString)")
        defer { try? manager.removeItem(at: work) }
        let app = work.appendingPathComponent("alfy-clean-notifier.app")
        let infoURL = app.appendingPathComponent("Contents/Info.plist")

        do {
            try manager.createDirectory(at: work, withIntermediateDirectories: true)
            try manager.copyItem(atPath: source, toPath: app.path)

            let data = try Data(contentsOf: infoURL)
            guard let info = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
            else { return false }
            let iconName = (info["CFBundleIconFile"] as? String).map { ($0 as NSString).deletingPathExtension } ?? "Terminal"
            let branded = try PropertyListSerialization.data(fromPropertyList: brandedInfo(info), format: .xml, options: 0)
            try branded.write(to: infoURL)

            guard let icns = makeIcns(in: work) else { return false }
            let iconURL = app.appendingPathComponent("Contents/Resources/\(iconName).icns")
            try? manager.removeItem(at: iconURL)
            try manager.copyItem(at: icns, to: iconURL)

            guard runProcess("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path]).success else { return false }

            try manager.createDirectory(atPath: (appPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
            if manager.fileExists(atPath: appPath) { try manager.removeItem(atPath: appPath) }
            try manager.moveItem(at: app, to: URL(fileURLWithPath: appPath))
            return true
        } catch {
            return false
        }
    }

    /// The logo as an .icns, made with sips and iconutil (both ship with macOS). Nil on failure.
    private static func makeIcns(in work: URL) -> URL? {
        let manager = FileManager.default
        let png = work.appendingPathComponent("icon.png")
        let iconset = work.appendingPathComponent("logo.iconset")
        let icns = work.appendingPathComponent("logo.icns")
        let data = iconPNG
        guard !data.isEmpty, (try? data.write(to: png)) != nil,
              (try? manager.createDirectory(at: iconset, withIntermediateDirectories: true)) != nil else { return nil }

        for size in [16, 32, 128, 256, 512] {
            for (suffix, pixels) in [("", size), ("@2x", size * 2)] {
                let target = iconset.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
                let resized = runProcess("/usr/bin/sips", ["-z", "\(pixels)", "\(pixels)", png.path, "--out", target.path])
                guard resized.success else { return nil }
            }
        }
        guard runProcess("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", icns.path]).success else { return nil }
        return icns
    }
}
