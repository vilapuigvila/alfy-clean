import XCTest
@testable import alfy_clean

/// Regression tests for SECURITY_AUDIT.md L1 (no shell, fixed PATH) and L7 (large output, launch failure).
final class ProcessRunnerTests: XCTestCase {
    func testOutputLargerThanThePipeBufferDoesNotHang() {
        // 300 KB, several times the 64 KB pipe buffer: the old shell() waited for exit before reading and hung.
        let result = runProcess("/usr/bin/head", ["-c", "300000", "/dev/zero"])
        XCTAssertTrue(result.success)
        XCTAssertEqual(result.output.utf8.count, 300_000)
    }

    func testLaunchFailureIsAResultNotACrash() {
        let result = runProcess("/nonexistent/tool", ["x"])
        XCTAssertEqual(result.exitCode, 127)
        XCTAssertFalse(result.success)
        XCTAssertTrue(result.output.contains("/nonexistent/tool"))
    }

    func testArgumentsAreNeverParsedByAShell() {
        let text = "a; echo pwned $(whoami) `id` \"q\" 'q' ~ *"
        let result = runProcess("/bin/echo", [text])
        XCTAssertEqual(result.output, text + "\n")
    }

    func testChildSeesOnlySystemFoldersOnPath() {
        let result = runProcess("/usr/bin/env")
        XCTAssertTrue(result.output.split(separator: "\n").contains("PATH=\(systemSearchPath)"))
    }

    func testLargeInputAndOutputTogetherDoNotDeadlock() {
        let input = Data(String(repeating: "x", count: 500_000).utf8)
        let result = runProcess("/usr/bin/wc", ["-c"], input: input)
        XCTAssertEqual(result.output.trimmingCharacters(in: .whitespacesAndNewlines), "500000")
    }

    func testDiscardedErrorOutputIsNotMixedIn() {
        let result = runProcess("/bin/ls", ["/nonexistent-folder"], errorOutput: .discarded)
        XCTAssertFalse(result.success)
        XCTAssertEqual(result.output, "")
    }

    func testTildeIsExpandedInSwiftNotByAShell() {
        XCTAssertEqual(expandTilde("~/x"), NSHomeDirectory() + "/x")
        XCTAssertEqual(runProcess("/bin/echo", ["~"]).output, "~\n")
    }

    func testBuiltInCommandsUseAbsoluteExecutablesAndExpandedPaths() throws {
        for option in Clean.OptionInput.allCases {
            guard let command = try? option.command() else { continue }
            XCTAssertTrue(command.executable.hasPrefix("/"), "\(option) runs \(command.executable)")
            XCTAssertFalse(command.arguments.contains { $0.hasPrefix("~") }, "\(option) has an unexpanded ~")
        }
    }

    func testScanOutputIsSortedAndFormatted() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["ALFY_CLEAN_SLOW_TESTS"] == nil, "full disk scan; set ALFY_CLEAN_SLOW_TESTS=1")
        let lines = SystemScanner.listLargeFolders().split(separator: "\n").map(String.init)
        XCTAssertLessThanOrEqual(lines.count, 50)
        let sizes = lines.compactMap { line -> Double? in
            let parts = line.trimmingCharacters(in: .whitespaces).components(separatedBy: " GB  ")
            return parts.count == 2 ? Double(parts[0]) : nil
        }
        XCTAssertEqual(sizes.count, lines.count)
        XCTAssertEqual(sizes, sizes.sorted(by: >))
    }

    /// Runs the real delete commands against a scratch folder (the built-in ones always target `~`).
    func testEmptyFolderAndJobTmpCommandsDeleteOnlyWhatTheyShould() throws {
        let fm = FileManager.default
        let root = NSHomeDirectory() + "/Library/Caches/alfy-clean-tests-\(UUID().uuidString)"
        defer { try? fm.removeItem(atPath: root) }

        // A "Trash" with a file, a folder with a space in its name, and a hidden file.
        let trash = root + "/Trash"
        try fm.createDirectory(atPath: trash + "/folder with spaces/inner", withIntermediateDirectories: true)
        fm.createFile(atPath: trash + "/a.txt", contents: Data("a".utf8))
        fm.createFile(atPath: trash + "/.hidden", contents: Data("h".utf8))

        let emptyTrash = Clean.OptionInput.emptyFolder(trash)
        XCTAssertTrue(runProcess(emptyTrash.executable, emptyTrash.arguments).success)
        XCTAssertTrue(fm.fileExists(atPath: trash), "the folder itself stays")
        XCTAssertEqual(try fm.contentsOfDirectory(atPath: trash), [])

        // Jobs: tmp folders go, everything else in a job stays.
        let jobs = root + "/jobs"
        for job in ["j1", "j2"] {
            try fm.createDirectory(atPath: "\(jobs)/\(job)/tmp/deep", withIntermediateDirectories: true)
            fm.createFile(atPath: "\(jobs)/\(job)/history.json", contents: Data("{}".utf8))
        }
        try fm.createDirectory(atPath: jobs + "/j1/keep/tmp", withIntermediateDirectories: true)

        let removeTmp = Clean.OptionInput.removeJobTmpFolders(in: jobs)
        XCTAssertTrue(runProcess(removeTmp.executable, removeTmp.arguments).success)
        for job in ["j1", "j2"] {
            XCTAssertFalse(fm.fileExists(atPath: "\(jobs)/\(job)/tmp"))
            XCTAssertTrue(fm.fileExists(atPath: "\(jobs)/\(job)/history.json"))
        }
        XCTAssertTrue(fm.fileExists(atPath: jobs + "/j1/keep/tmp"), "only <job>/tmp, not deeper")
    }
}
