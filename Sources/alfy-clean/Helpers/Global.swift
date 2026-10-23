//
//  File.swift
//  
//
//  Created by albert vila puigvila on 4/2/22.
//

import Foundation

struct ShellResult {
    let output: String
    let exitCode: Int32
    var success: Bool { exitCode == 0 }
}

/// `PATH` for child processes: system folders only. Folders a user or a package manager can write to
/// (~/.local/bin, Homebrew, version-manager shims) are left out, so a planted `rm` or `xcrun` never runs.
let systemSearchPath = "/usr/bin:/bin:/usr/sbin:/sbin"

enum ErrorOutput {
    /// stderr is mixed into the returned output.
    case merged
    case discarded
}

/// Runs `executable` (an absolute path) with `arguments` and returns its output and exit code.
/// No shell is involved, so arguments are never parsed, expanded or quoted: `~` must be expanded by the caller.
/// A launch failure comes back as exit code 127 instead of crashing.
@discardableResult
func runProcess(
    _ executable: String,
    _ arguments: [String] = [],
    input: Data? = nil,
    errorOutput: ErrorOutput = .merged,
    searchPath: String = systemSearchPath
) -> ShellResult {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: executable)
    task.arguments = arguments

    var environment = ProcessInfo.processInfo.environment
    environment["PATH"] = searchPath
    task.environment = environment

    let outputPipe = Pipe()
    task.standardOutput = outputPipe
    task.standardError = errorOutput == .merged ? outputPipe : FileHandle.nullDevice

    let inputPipe = input == nil ? nil : Pipe()
    task.standardInput = inputPipe ?? FileHandle.nullDevice

    do {
        try task.run()
    } catch {
        return ShellResult(output: "Could not start \(executable): \(error.localizedDescription)", exitCode: 127)
    }

    if let input = input, let inputPipe = inputPipe {
        // A child that exits early closes the pipe; that must not kill alfy-clean with SIGPIPE.
        signal(SIGPIPE, SIG_IGN)
        // Written off the main thread so a large input can't deadlock against the output we read below.
        DispatchQueue.global().async {
            try? inputPipe.fileHandleForWriting.write(contentsOf: input)
            try? inputPipe.fileHandleForWriting.close()
        }
    }

    // Read before waiting: a child that writes more than the pipe buffer (64 KB) blocks until we read.
    let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
    task.waitUntilExit()

    return ShellResult(output: String(decoding: data, as: UTF8.self), exitCode: task.terminationStatus)
}

/// `xcrun simctl <arguments>`.
@discardableResult
func simctl(_ arguments: [String], errorOutput: ErrorOutput = .merged) -> ShellResult {
    runProcess("/usr/bin/xcrun", ["simctl"] + arguments, errorOutput: errorOutput)
}

func expandTilde(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
}

func keyboardInput(
    file: String = #file,
    line: String = #file
) throws -> String {
    let keyboard = FileHandle.standardInput
    guard let input = String(data: keyboard.availableData, encoding: .utf8) else {
        throw "Unknwon error.... \(file) - \(line)"
    }
    return input
}
