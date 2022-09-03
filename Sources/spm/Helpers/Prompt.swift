//
//  Prompt.swift
//  
//
//  Created by albert vila on 6/4/22.
//

// https://github.com/marcoconti83/Corazza

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
