//
//  String+Error.swift
//

import Foundation

// Lets string literals be thrown directly, e.g. `throw "message"`.
#if compiler(>=5.10)
extension String: @retroactive Error { }
#else
extension String: Error { }
#endif
