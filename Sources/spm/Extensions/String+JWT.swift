//
//  File.swift
//  
//
//  Created by albert vila on 11/10/24.
//

import Foundation

extension String {
    func decodesJWT() throws -> [String: Any] {
        func base64Decode(_ base64: String) throws -> Data {
            let base64 = base64
                .replacingOccurrences(of: "-", with: "+")
            let padded = base64.padding(toLength: ((base64.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
            guard let decoded = Data(base64Encoded: padded) else {
                throw "Bad token"
            }
            return decoded
        }
        func decodeJWTPart(_ value: String) throws -> [String: Any] {
            let bodyData = try base64Decode(value)
            let json = try JSONSerialization.jsonObject(with: bodyData, options: [])
            guard let payload = json as? [String: Any] else {
                throw "JSONSerialization error"
            }
            return payload
        }
        let segments = components(separatedBy: ".")
        return try decodeJWTPart(segments[1])
    }
    var jwtExpirationDate: Date? {
        guard let jwtDictionary = try? decodesJWT(), let expiration = jwtDictionary["exp"] else {
            return nil
        }
        if let timeInterval = expiration as? Double {
            return Date(timeIntervalSince1970: timeInterval)
        } else if let timeIntervalString = expiration as? String, let timeInterval = Double(timeIntervalString) {
            return Date(timeIntervalSince1970: timeInterval)
        } else {
            return nil
        }
    }
}

extension String: Error { }
