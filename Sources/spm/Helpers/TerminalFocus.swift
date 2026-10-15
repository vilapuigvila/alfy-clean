//
//  TerminalFocus.swift
//
//  Remembers which terminal tab ran avp, so tapping a notification can bring that exact tab back.
//  Only Ghostty is supported (through its AppleScript dictionary); other terminals just get their app activated.
//

import Foundation

enum TerminalFocus {
    private static let ghosttyBundleID = "com.mitchellh.ghostty"
    private static var ghosttyTerminalID: String?

    /// Records the focused Ghostty terminal. Call at startup: the user has just typed the command,
    /// so the terminal that ran avp is still the focused one. Does nothing outside Ghostty, or if
    /// scripting is refused (macOS asks for Automation permission the first time).
    static func captureCurrentTerminal() {
        guard ProcessInfo.processInfo.environment["__CFBundleIdentifier"] == ghosttyBundleID else { return }

        let result = runProcess(
            "/usr/bin/osascript",
            ["-e", "tell application id \"\(ghosttyBundleID)\" to return id of focused terminal of selected tab of front window"],
            errorOutput: .discarded
        )
        let id = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        // The id ends up in a shell command below, so only accept a plain identifier.
        guard result.success, isValidID(id) else { return }
        ghosttyTerminalID = id
    }

    /// Shell command for a notification's click action, or nil when the terminal wasn't recorded.
    static var clickCommand: String? {
        guard let id = ghosttyTerminalID else { return nil }
        return clickCommand(forTerminalID: id)
    }

    static func isValidID(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9-]{8,64}$", options: .regularExpression) != nil
    }

    static func clickCommand(forTerminalID id: String) -> String {
        "/usr/bin/osascript"
            + " -e 'tell application id \"\(ghosttyBundleID)\" to activate'"
            + " -e 'tell application id \"\(ghosttyBundleID)\" to focus (terminal id \"\(id)\")'"
    }
}
