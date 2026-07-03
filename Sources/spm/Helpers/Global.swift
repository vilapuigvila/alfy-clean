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

@discardableResult
func shell(_ command: String) -> ShellResult {
    let task = Process()
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = pipe
    task.arguments = ["-c", command]
    task.launchPath = "/bin/zsh"
    task.launch()
    task.waitUntilExit()

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    let output = String(data: data, encoding: .utf8) ?? ""

    return ShellResult(output: output, exitCode: task.terminationStatus)
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
