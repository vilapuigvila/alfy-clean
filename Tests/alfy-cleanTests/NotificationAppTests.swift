import XCTest
@testable import alfy_clean

final class NotificationAppTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("alfy-clean-app-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temp)
    }

    func testEmbeddedLogoIsA512PixelPNG() {
        let bytes = Array(NotificationApp.iconPNG)
        XCTAssertEqual(Array(bytes.prefix(8)), [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        // PNG: the IHDR chunk holds width and height as big-endian 32-bit numbers at bytes 16...23.
        XCTAssertGreaterThan(bytes.count, 24)
        XCTAssertEqual(bytes[16...19].reduce(0) { $0 << 8 | Int($1) }, 512)
        XCTAssertEqual(bytes[20...23].reduce(0) { $0 << 8 | Int($1) }, 512)
    }

    func testBrandedInfoSetsAlfyCleanIdentityAndKeepsTheRest() {
        let original: [String: Any] = [
            "CFBundleIdentifier": "fr.julienxx.oss.terminal-notifier",
            "CFBundleName": "terminal-notifier",
            "CFBundleExecutable": "terminal-notifier",
            "CFBundleIconFile": "Terminal"
        ]
        let branded = NotificationApp.brandedInfo(original)
        XCTAssertEqual(branded["CFBundleIdentifier"] as? String, NotificationApp.bundleIdentifier)
        XCTAssertEqual(branded["CFBundleName"] as? String, "alfy-clean")
        XCTAssertEqual(branded["CFBundleDisplayName"] as? String, "alfy-clean")
        XCTAssertEqual(branded["CFBundleExecutable"] as? String, "terminal-notifier")
        XCTAssertEqual(branded["CFBundleIconFile"] as? String, "Terminal")
        XCTAssertNotEqual(NotificationApp.bundleIdentifier, "fr.julienxx.oss.terminal-notifier")
    }

    func testSourceAppIsFoundNextToTheRealBinFolderThroughASymlink() throws {
        let manager = FileManager.default
        let formula = temp.appendingPathComponent("Cellar/terminal-notifier/3.1.0")
        try manager.createDirectory(at: formula.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try manager.createDirectory(at: formula.appendingPathComponent("terminal-notifier.app"), withIntermediateDirectories: true)
        manager.createFile(atPath: formula.appendingPathComponent("bin/terminal-notifier").path, contents: Data())
        try manager.createDirectory(at: temp.appendingPathComponent("bin"), withIntermediateDirectories: true)
        let link = temp.appendingPathComponent("bin/terminal-notifier")
        try manager.createSymbolicLink(atPath: link.path, withDestinationPath: "../Cellar/terminal-notifier/3.1.0/bin/terminal-notifier")

        let found = NotificationApp.sourceApp(forNotifier: link.path)
        XCTAssertEqual(found.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                       formula.appendingPathComponent("terminal-notifier.app").resolvingSymlinksInPath().path)
    }

    func testSourceAppIsNilWhenTheAppIsMissing() throws {
        let bin = temp.appendingPathComponent("bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: bin.appendingPathComponent("terminal-notifier").path, contents: Data())
        XCTAssertNil(NotificationApp.sourceApp(forNotifier: bin.appendingPathComponent("terminal-notifier").path))
    }

    func testAnExistingAppWithOurBundleIDIsUsedAsItIs() throws {
        let manager = FileManager.default
        let app = temp.appendingPathComponent("alfy-clean-notifier.app")
        try manager.createDirectory(at: app.appendingPathComponent("Contents/MacOS"), withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleIdentifier": NotificationApp.bundleIdentifier], format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        let executable = app.appendingPathComponent("Contents/MacOS/terminal-notifier")
        manager.createFile(atPath: executable.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        let before = try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist"))

        XCTAssertEqual(NotificationApp.executablePath(appPath: app.path), executable.path)
        // Untouched: rebuilding would re-sign it, and macOS could forget that its notifications were allowed.
        XCTAssertEqual(try Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")), before)
    }
}
