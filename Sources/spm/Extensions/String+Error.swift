//
//  String+Error.swift
//

import Foundation

// Lets string literals be thrown directly, e.g. `throw "message"`.
extension String: Error { }
