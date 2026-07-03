//
//  TerminalLoader.swift
//
//
//  Created by GitHub Copilot on 7/3/26.
//

import Darwin
import Foundation

final class TerminalLoader {
    private let message: String
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private let queue = DispatchQueue(label: "avp.terminal-loader")
    private let isInteractive = isatty(STDOUT_FILENO) != 0
    private var timer: DispatchSourceTimer?
    private var frameIndex = 0

    init(_ message: String) {
        self.message = message
    }

    func start() {
        guard isInteractive else {
            customPrint("• \(message)...")
            return
        }

        write("\u{001B}[?25l")
        render(frame: frames[frameIndex], color: .cyan)

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.frameIndex = (self.frameIndex + 1) % self.frames.count
            self.render(frame: self.frames[self.frameIndex], color: .cyan)
        }
        self.timer = timer
        timer.resume()
    }

    func succeed() {
        stop(symbol: "✓", color: .green)
    }

    func fail() {
        stop(symbol: "✗", color: .red)
    }

    private func stop(symbol: String, color: Print.Color) {
        timer?.cancel()
        timer = nil

        guard isInteractive else {
            customPrint("\(symbol) \(message)")
            return
        }

        render(frame: symbol, color: color)
        write("\n\u{001B}[?25h")
    }

    private func render(frame: String, color: Print.Color) {
        write("\r\u{001B}[K\(color.rawValue)\(frame)\(Print.Color.reset.rawValue) \(message)")
    }

    private func write(_ output: String) {
        guard let data = output.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }
}
