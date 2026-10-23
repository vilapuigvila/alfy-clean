import XCTest
@testable import alfy_clean

final class TerminalFocusTests: XCTestCase {
    func testAcceptsGhosttyTerminalIDs() {
        XCTAssertTrue(TerminalFocus.isValidID("753D1523-DD8B-4248-AF43-5DBB48DEE20F"))
    }

    func testRejectsAnythingThatCouldBecomeShellOrScriptSyntax() {
        for bad in ["", "short", "753D1523\"; rm -rf ~; \"", "a b c d e f g h", "id'quote'000000", "$(whoami)000000", "id\n0000000000"] {
            XCTAssertFalse(TerminalFocus.isValidID(bad), bad)
        }
    }

    func testClickCommandActivatesGhosttyThenFocusesTheTerminal() {
        let command = TerminalFocus.clickCommand(forTerminalID: "753D1523-DD8B-4248-AF43-5DBB48DEE20F")
        XCTAssertTrue(command.hasPrefix("/usr/bin/osascript "))
        XCTAssertTrue(command.contains("to activate"))
        XCTAssertTrue(command.contains("focus (terminal id \"753D1523-DD8B-4248-AF43-5DBB48DEE20F\")"))
    }

    func testNoClickCommandUntilATerminalWasCaptured() {
        // Nothing has captured a terminal in the test process (and outside Ghostty it never does).
        if ProcessInfo.processInfo.environment["__CFBundleIdentifier"] != "com.mitchellh.ghostty" {
            XCTAssertNil(TerminalFocus.clickCommand)
        }
    }
}
