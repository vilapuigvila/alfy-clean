//
//  TerminalLoader.swift
//
//
//  Created by GitHub Copilot on 7/3/26.
//

import Darwin
import Foundation

final class TerminalLoader {
    static let thinkingWords = [
        "Cerebrating", "Cogitating", "Considering", "Contemplating", "Deliberating", "Ideating", "Mulling",
        "Musing", "Noodling", "Pondering", "Pontificating", "Philosophising", "Ruminating", "Puzzling"
    ]

    private static let orange = "\u{001B}[38;5;208m"

    private let fixedMessage: String?
    private let wordInterval: TimeInterval = 3
    private var word = TerminalLoader.thinkingWords.randomElement() ?? "Thinking"
    private var wordChangedAt = ProcessInfo.processInfo.systemUptime

    /// "<word> Nope 🤣 - I'm processing my friend", with a new word every few seconds, or the fixed message.
    private var message: String {
        fixedMessage ?? "\(word) Nope 🤣 - I'm processing my friend"
    }

    private var styledMessage: String {
        guard fixedMessage == nil else { return message }
        let reset = Print.Color.reset.rawValue
        let white = Print.Color.white.rawValue
        return "\(Self.orange)\(word)\(reset) \(white)Nope 🤣 - I'm\(reset) "
            + "\(Print.Color.green.rawValue)processing\(reset) \(white)my friend\(reset)"
    }

    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private let queue = DispatchQueue(label: "avp.terminal-loader")
    private let isInteractive = isatty(STDOUT_FILENO) != 0
    private let displayDelay: TimeInterval = 1
    private let minimumVisibleDuration: TimeInterval = 1.5
    private var timer: DispatchSourceTimer?
    private var frameIndex = 0
    private var didRender = false
    private var didStop = false
    private var visibleStartedAt: TimeInterval?

    init(_ message: String) {
        self.fixedMessage = message
    }

    /// A loader that cycles through playful words instead of showing a fixed message.
    init() {
        self.fixedMessage = nil
    }

    func start() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + displayDelay, repeating: 0.1)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard !self.didStop else { return }

            if !self.didRender {
                self.didRender = true
                self.visibleStartedAt = ProcessInfo.processInfo.systemUptime

                guard self.isInteractive else {
                    customPrint("• \(self.message)...")
                    return
                }

                self.write("\u{001B}[?25l")
            }

            guard self.isInteractive else { return }

            self.rotateWordIfNeeded()
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
        var shouldRenderFinalState = false
        var remainingVisibleTime: TimeInterval = 0

        queue.sync {
            didStop = true
            timer?.cancel()
            timer = nil

            guard didRender else { return }

            shouldRenderFinalState = true
            if let visibleStartedAt = visibleStartedAt {
                let visibleDuration = ProcessInfo.processInfo.systemUptime - visibleStartedAt
                remainingVisibleTime = max(0, minimumVisibleDuration - visibleDuration)
            }
        }

        guard shouldRenderFinalState else { return }

        if remainingVisibleTime > 0 {
            Thread.sleep(forTimeInterval: remainingVisibleTime)
        }

        guard isInteractive else {
            customPrint("\(symbol) \(message)")
            return
        }

        render(frame: symbol, color: color)
        write("\n\u{001B}[?25h")
    }

    private func rotateWordIfNeeded() {
        guard fixedMessage == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - wordChangedAt >= wordInterval else { return }
        wordChangedAt = now
        word = Self.thinkingWords.filter { $0 != word }.randomElement() ?? word
    }

    private func render(frame: String, color: Print.Color) {
        write("\r\u{001B}[K\(color.rawValue)\(frame)\(Print.Color.reset.rawValue) \(styledMessage)")
    }

    private func write(_ output: String) {
        guard let data = output.data(using: .utf8) else { return }
        FileHandle.standardOutput.write(data)
    }
}
