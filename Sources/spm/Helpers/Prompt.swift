//
//  Prompt.swift
//  
//
//  Created by albert vila on 6/4/22.
//

// https://github.com/marcoconti83/Corazza

import Darwin
import Foundation

final class Prompt {

    /// Inputs that represent no/false
    static let noSynonyms = Set(["no", "n"])
    
    /// Inputs that represent yes/trye
    static let yesSynonyms = Set(["yes", "y"])
    
    /// Text to print when it reads an invalid answer
    static let notValidAnswer = "Not a valid answer"
    
    /// Prompt for yes/no
    static let yesOrNoPrompt = "[Y]es or [N]o?"
    
    /// Prompt for choosing an option
    static let choosePrompt = "Choose an option"
    
    /// Separator for options
    static let optionsSeparator = "------------------------------------"
    
    public init() {}
    
    /// Prints a question on standard output, then reads an aswer from standard input.
    /// It will keep asking until it reads a valid answer.
    /// - parameter defaultAnswer: if not nil and no answer is read (empty line), it will return this
    public func ask(_ question: String? = nil, defaultAnswer: String? = nil) -> String {
        func defaultText() -> String {
            guard let defaultAnswer = defaultAnswer else { return "" }
            return " (default: \(defaultAnswer))"
        }

        while true {
            
            // question
            if let question = question {
                customPrint(question)
            }
            
            // print prompt
            customPrint(defaultText, terminator: " > ")
            
            // parse answer
            guard let answer = customReadline(true)?.trim else {
                fatalError("EOF?")
            }
            if answer == "" {
                if let defaultAnswer = defaultAnswer {
                    return defaultAnswer
                }
                continue
            }
            return answer
        }
    }
    
    /// Prints a question on standard output, then reads a Yes/No answer
    /// from standard input. It keeps reading until it reads a valid answer
    /// - returns: true if it read a Yes, false if it read a No
    public func yesNo(_ question: String? = nil, defaultAnswer: Bool? = nil) -> Bool {
        
        // question
        if let question = question {
            customPrint(question)
        }
        func defaultText() -> String {
            guard let defaultAnswer = defaultAnswer else { return "" }
            let mapping = [true: "Y", false: "N"]
            return " (default: \(mapping[defaultAnswer]!))"
        }
        
        while true {
            // print prompt
            customPrint(Prompt.yesOrNoPrompt + defaultText(), terminator: " > ")
            
            // parse answer
            guard let answer = customReadline(true)?.trim.lowercased() else {
                fatalError("EOF?")
            }
            if Prompt.noSynonyms.contains(answer) {
                return false
            }
            if Prompt.yesSynonyms.contains(answer) {
                return true
            }
            if let defaultAnswer = defaultAnswer , answer == "" {
                return defaultAnswer
            }
            customPrint(Prompt.notValidAnswer)
        }
    }
    
    /// Prints a question on standard output, then prints a series of options
    /// and reads one of the option from standard input. It keeps reading until
    /// it reads a valid answer
    /// - returns: the value of the option that was chosen
    public func options<T>(_ options: [T], question: String? = nil, defaultAnswer: T? = nil) -> T? {
        
        guard !options.isEmpty else { return nil}
        guard options.count > 1 else { return options[0] }
        
        // default?
        let defaultText = { () -> String in
            guard let defaultAnswer = defaultAnswer else { return "" }
            return " (default: \(defaultAnswer))"
        }
        
        while true {
            
            // question
            if let question = question {
                customPrint(question)
            }
            
            // print options
            customPrint(Prompt.optionsSeparator)
            for index in 0...options.count-1 {
                customPrint("\(index+1)\t\(options[index])")
            }
            customPrint(Prompt.optionsSeparator)
            customPrint(Prompt.choosePrompt + defaultText(), terminator: " > ")
            
            // parse answer
            guard let answer = customReadline(true)?.trim else {
                fatalError("EOF?")
            }
            if let defaultAnswer = defaultAnswer , answer == "" {
                return defaultAnswer
            }
            if let index = Int(answer) , (index > 0 && index <= options.count) {
                return options[index - 1]
            }
            customPrint(Prompt.notValidAnswer)
            customPrint("")
        }
    }

    /// Shows an interactive checkbox list in the terminal.
    /// Use Up/Down arrows to move, Space to toggle, and Enter to confirm.
    public func checkboxOptions<T>(
        _ options: [T],
        question: String? = nil,
        label: (T) -> String = { "\($0)" },
        detail: ((T) -> String?)? = nil
    ) -> [T] {
        guard !options.isEmpty else { return [] }
        guard isatty(STDIN_FILENO) != 0 else {
            return lineInputCheckboxOptions(options, question: question, label: label, detail: detail)
        }

        var selectedIndexes = Set<Int>()
        var focusedIndex = 0
        var renderedLineCount = 0

        guard let rawMode = TerminalRawMode() else {
            return lineInputCheckboxOptions(options, question: question, label: label, detail: detail)
        }
        defer {
            rawMode.restore()
            writeTerminal("\u{001B}[?25h")
        }

        writeTerminal("\u{001B}[?25l")

        func render() {
            if renderedLineCount > 0 {
                writeTerminal("\u{001B}[\(renderedLineCount)A")
                writeTerminal("\u{001B}[J")
            }

            var lines: [String] = []
            if let question = question {
                lines.append(contentsOf: question.components(separatedBy: .newlines))
            }
            lines.append("\(Print.Color.dim.rawValue)↑/↓ move  •  space select  •  enter confirm  •  q cancel\(Print.Color.reset.rawValue)")
            lines.append("")

            // A description under every row, unless that would scroll the menu off the screen
            // (the redraw moves the cursor up by line count, so it must fit).
            let size = terminalSize()
            let headerLines = lines.count
            let fitsWithDetails = detail != nil && headerLines + options.count * 2 < size.rows
            let detailIndent = "      "

            for index in options.indices {
                let isFocused = index == focusedIndex
                let isSelected = selectedIndexes.contains(index)
                let focus = isFocused ? "❯" : " "
                let checkbox = isSelected ? "☑" : "☐"
                let line = "\(focus) \(checkbox) \(label(options[index]))"

                if isFocused {
                    lines.append("\(Print.Color.boldGreen.rawValue)\(line)\(Print.Color.reset.rawValue)")
                } else if isSelected {
                    lines.append("\(Print.Color.green.rawValue)\(line)\(Print.Color.reset.rawValue)")
                } else {
                    lines.append(line)
                }

                if let text = detail?(options[index]), fitsWithDetails || isFocused {
                    let room = max(size.columns - detailIndent.count - 1, 10)
                    let shown = text.count > room ? String(text.prefix(room - 1)) + "…" : text
                    lines.append("\(Print.Color.dim.rawValue)\(detailIndent)\(shown)\(Print.Color.reset.rawValue)")
                }
            }

            renderedLineCount = lines.count
            writeTerminal(lines.joined(separator: "\n") + "\n")
        }

        render()

        while true {
            switch readTerminalKey() {
            case .up:
                focusedIndex = focusedIndex == 0 ? options.count - 1 : focusedIndex - 1
                render()
            case .down:
                focusedIndex = focusedIndex == options.count - 1 ? 0 : focusedIndex + 1
                render()
            case .space:
                if selectedIndexes.contains(focusedIndex) {
                    selectedIndexes.remove(focusedIndex)
                } else {
                    selectedIndexes.insert(focusedIndex)
                }
                render()
            case .enter:
                writeTerminal("\n")
                return selectedIndexes.sorted().map { options[$0] }
            case .character(let byte) where byte == CharacterKey.q:
                writeTerminal("\n")
                return []
            case .character(let byte) where byte == CharacterKey.k:
                focusedIndex = focusedIndex == 0 ? options.count - 1 : focusedIndex - 1
                render()
            case .character(let byte) where byte == CharacterKey.j:
                focusedIndex = focusedIndex == options.count - 1 ? 0 : focusedIndex + 1
                render()
            case .unknown, .character:
                continue
            }
        }
    }

    private func lineInputCheckboxOptions<T>(
        _ options: [T],
        question: String?,
        label: (T) -> String,
        detail: ((T) -> String?)? = nil
    ) -> [T] {
        while true {
            if let question = question {
                customPrint(question)
            }

            for index in options.indices {
                customPrint("  [\(index)] ☐ \(label(options[index]))")
                if let text = detail?(options[index]) {
                    customPrint("\(Print.Color.dim.rawValue)        \(text)\(Print.Color.reset.rawValue)")
                }
            }
            customPrint("")
            customPrint("Choose one or more options separated by commas", terminator: " › ")

            guard let answer = customReadline(true)?.trim else {
                fatalError("EOF?")
            }

            if answer.isEmpty {
                return []
            }

            let indexes = answer
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

            let parsedIndexes = indexes.compactMap(Int.init)
            let hasOnlyValidIndexes = parsedIndexes.count == indexes.count
                && parsedIndexes.allSatisfy { options.indices.contains($0) }

            if hasOnlyValidIndexes {
                return parsedIndexes.map { options[$0] }
            }

            customPrint(Prompt.notValidAnswer)
            customPrint("")
        }
    }
}

private enum TerminalKey {
    case up
    case down
    case space
    case enter
    case character(UInt8)
    case unknown
}

private enum CharacterKey {
    static let escape: UInt8 = 27
    static let leftBracket: UInt8 = 91
    static let arrowUp: UInt8 = 65
    static let arrowDown: UInt8 = 66
    static let enter: UInt8 = 10
    static let carriageReturn: UInt8 = 13
    static let space: UInt8 = 32
    static let j: UInt8 = 106
    static let k: UInt8 = 107
    static let q: UInt8 = 113
}

private final class TerminalRawMode {
    private var original = termios()
    private var restored = false

    init?() {
        guard tcgetattr(STDIN_FILENO, &original) == 0 else { return nil }

        var raw = original
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON)

        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else { return nil }
    }

    deinit {
        restore()
    }

    func restore() {
        guard !restored else { return }
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
        restored = true
    }
}

private func readTerminalKey() -> TerminalKey {
    let data = FileHandle.standardInput.readData(ofLength: 1)
    guard let byte = data.first else { return .unknown }

    switch byte {
    case CharacterKey.enter, CharacterKey.carriageReturn:
        return .enter
    case CharacterKey.space:
        return .space
    case CharacterKey.escape:
        let sequence = FileHandle.standardInput.readData(ofLength: 2)
        guard sequence.count == 2,
              sequence[sequence.startIndex] == CharacterKey.leftBracket else {
            return .unknown
        }

        switch sequence[sequence.index(after: sequence.startIndex)] {
        case CharacterKey.arrowUp:
            return .up
        case CharacterKey.arrowDown:
            return .down
        default:
            return .unknown
        }
    default:
        return .character(byte)
    }
}

/// Terminal size, with a safe default when it can't be read.
private func terminalSize() -> (rows: Int, columns: Int) {
    var size = winsize()
    guard ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_row > 0, size.ws_col > 0 else {
        return (24, 80)
    }
    return (Int(size.ws_row), Int(size.ws_col))
}

private func writeTerminal(_ string: String) {
    guard let data = string.data(using: .utf8) else { return }
    FileHandle.standardOutput.write(data)
}

typealias PrintFunction = ([Any], _ separator: String, _ terminator: String) -> Void
typealias ReadLineFunction = (_ stripNewLine: Bool) -> String?

/// Overridable print function for test
var TestablePrintFunction : PrintFunction? = nil

/// Overridable read line function for tests
var TestableReadLineFunction : ReadLineFunction? = nil

/// Prints using the standard print function, or the override if set
func customPrint(_ items: Any..., separator: String = " ", terminator: String = "\n") {
    if let override = TestablePrintFunction {
        override(items, separator, terminator)
    } else {
        let itemsString = items.map { String(describing: $0) }.joined(separator: " ")
        print(itemsString, separator: separator, terminator: terminator)
    }
}

/// Prints using the standard print function, or the override if set
func customReadline(_ stripNewLine: Bool = false) -> String? {
    let standard : ReadLineFunction = readLine(strippingNewline:)
    let override = TestableReadLineFunction != nil ? TestableReadLineFunction! : standard
    return override(stripNewLine)
}

extension String {
    /// Returns self trimmed by removing spaces and newlines at the beginning and at the end
    public var trim : String {
        return self.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }
}
