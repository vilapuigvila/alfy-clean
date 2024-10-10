//
//  File.swift
//  
//
//  Created by albert vila on 10/10/24.
//

import Foundation
import ArgumentParser
import CryptoKit
import SwiftJWT
import Crypto
import JWTKit

final class Pusher: ParsableCommand {
    public static let configuration = CommandConfiguration(
        abstract: "Send Push to Mango App"
    )
    private static let maxRetries: Int = 3
    private var retries: Int = 0
    
//    @Option(name: .shortAndLong, help: "The APNS device token.")
//    var deviceToken: String = "48a970d868ae2104f704fca65f6832a18542492d997f053a1106032d8fb9d465"

    @Option(name: .shortAndLong, help: "The APNS device token.")
    var deviceTokens: [String] = [
        "48a970d868ae2104f704fca65f6832a18542492d997f053a1106032d8fb9d465"
    ]
    // "5f1383c02e26fb3c7c334839a405576e4b71350263c18ebd86688de69fb99238" filip
    
    @Option(name: .shortAndLong, help: "The APNS bearer token for authorization.")
    var bearerToken: String = "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IjVLVFBLSEQzUFIifQ.eyJpc3MiOiI0Vjc1Vjg3U0g5IiwiaWF0IjoxNzI4NTc1MDI2LjI1MDcyLCJleHAiOjE3Mjg2NjE0MjYuMjUwNzJ9.LSeTvOrwous3dTb84xZ_aiQ1IjCn3UXwiytQtBP0sXYqAttVRknHBJoLlp6cT5N3E8I0uacbrn4m8e7NCnq4QA"

    var bearerTokenExp: String { "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IjVLVFBLSEQzUFIifQ.eyJpc3MiOiI0Vjc1Vjg3U0g5IiwiaWF0IjoxNzI4NDgzMTQ4LCJleHAiOjE3Mjg0ODY3NDh9.etIDEKS656E7z7dc6764kazvW1tSQGYpPTe82-bfxVT-IpA9QECL0xGducGZm5DtC8NW9kRhZKmjv_wfOTt7Ig"
    }
    var expirationTimeInterval: Double {
        3600*24
    }
}

extension Pusher {
    
    func run() throws {
        Print.withColor(.cyan, "Wait... sending push 🙏")
        
        guard !deviceTokens.isEmpty else {
            Print.withColor(.red, "no deviceTokens found")
            return
        }
        let semaphore = DispatchSemaphore(value: 0)
        
        let authToken: String = {
            do {
                return try isTokenExpired(token: bearerTokenExp)
            } catch {
                precondition(false, "missing expiration date in jwt.")
                return ""
            }
        }()
        bearerToken = authToken
        Task {
            do {
//                let authToken = try isTokenExpired(token: bearerToken)
//                bearerToken = try await checkAuthToken()
                
                for deviceToken in deviceTokens {
                    try await sendPushNotification(to: deviceToken)
                }
            } catch {
                Print.withColor(.red, "Error sending push notification: \(error)")
            }
            semaphore.signal()
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 1.0))
        
        // Wait for the semaphore to signal completion
        semaphore.wait()
    }
    /*
    func checkAuthToken() async throws -> String {
        guard let jsonData = try? JSONEncoder().encode(NotificationPayload.default) else {
            fatalError("No json encode data from payload")
        }
        let url = URL(string: "https://api.sandbox.push.apple.com/3/device/48a970d868ae2104f704fca65f6832a18542492d997f053a1106032d8fb9d465")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("com.mango.2010", forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.setValue("bearer \(bearerToken)", forHTTPHeaderField: "authorization")
        let task = Task { [request] in
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    fatalError("No HTTPURLResponse...")
                }
                switch httpResponse.statusCode {
                case 200: return false
                default: return true
                }
            } catch {
                return true
            }
        }
        let isExpired = await task.value
        guard isExpired else {
            Print.withColor(.cyan, "Current auth token: \(bearerTokenExp)")
            return bearerTokenExp
        }
        let refreshedToken = try refreshAuth()
        Print.withColor(.cyan, "Refresed auth token: \(refreshedToken)")
        return refreshedToken
    }*/
    
    func sendPushNotification(to deviceToken: String/*, authToken: String*/) async throws {
        guard let jsonData = try? JSONEncoder().encode(NotificationPayload.default) else {
            fatalError("Failed to encode payload")
        }
        let url = URL(string: "https://api.sandbox.push.apple.com/3/device/\(deviceToken)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("com.mango.2010", forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.setValue("bearer \(bearerToken)", forHTTPHeaderField: "authorization")
        Print.withColor(.red, "request with \(bearerToken)")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                Print.withColor(.red, "\(response.debugDescription)")
                return
            }
            switch httpResponse.statusCode {
            case 200...299:
                guard let responseData = String(data: data, encoding: .utf8) else {
                    Print.withColor(.red, "Response: missing data")
                    return
                }
                if !deviceTokens.isEmpty {
                    deviceTokens.removeFirst()
                }
                Print.withColor(.green, "Success push: \(responseData)")
            case (400...499):
                Print.withColor(.red, "UnAuthorized: status code: \(httpResponse.statusCode). Refresh your bearer token")
                /*
                guard retries < Self.maxRetries else {
                    return
                }
                do {
                    let token = try refreshAuth()
                    Print.withColor(.cyan, "Refreshed auth token: \(token)")
                    try await sendPushNotification(to: deviceToken, authToken: token)
                } catch {
                    Print.withColor(.red, "Error refreshing auth token: \(error.localizedDescription)")
                }
                retries += 1
                */
            default:
                Print.withColor(.red, "Response: missing..")
            }
        } catch {
            Print.withColor(.red, "Error: \(error.localizedDescription)")
        }
    }
    
    private func refreshAuth() throws -> String {
        let teamID = "4V75V87SH9"
        let keyID = "5KTPKHD3PR"
        let apnsKeyPath = "/Users/albert/Desktop/AuthKey_5KTPKHD3PR.p8"

        let header = Header(typ: "JWT", kid: keyID)
        #warning("avp check it out ⚠️ -> maybe 24 hours is too much")
        let claims = PusherClaims(iss: teamID, iat: Date(), exp: Date().addingTimeInterval(expirationTimeInterval))
        var jwt = JWT(header: header, claims: claims)
        let privateKeyString = try readPrivateKey(from: apnsKeyPath)
        let jwtSigner = JWTSigner.es256(privateKey: privateKeyString.data(using: .utf8)!)
        let token = try jwt.sign(using: jwtSigner)
        return token
    }
    
    func readPrivateKey(from path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }
    
    func isTokenExpired(token: String) throws -> String {
        guard let expDate = token.jwtExpirationDate else {
            throw PusherError.missingExpDateJWT
        }
        Print.withColor(.cyan, "expiration date: \(expDate.description)")
        if Date().timeIntervalSince(expDate) > TimeInterval(expirationTimeInterval) {
            let refreshedToken = try refreshAuth()
            Print.withColor(.yellow, "Auth has been refreshed: \(refreshedToken)")
            return refreshedToken
        } else {
            Print.withColor(.green, "Current token is valid: \(token)")
            return token
        }
    }
    
    struct NotificationPayload: Codable {
        struct APS: Codable {
            struct Alert: Codable {
                let title: String
                let subtitle: String
                let body: String
            }
            let alert: Alert
        }
        let aps: APS
        let destination_url: String
        
        static var `default`: Self {
            NotificationPayload(
                aps: NotificationPayload.APS(
                    alert: NotificationPayload.APS.Alert(
                        title: "hello Filipe",
                        subtitle: "",
                        body: "🍻"
                    )
                ),
                destination_url: "mangoapp://section/she.sections_she_imssm_rtls_LiveShopp_destRenting_Capsule_Godo.nuevo?utm_source=c-producto-newnow&utm_campaign=PS_MCNNO24412&utm_medium=push"
            )
        }
    }
    
    fileprivate struct PusherClaims: Claims {
        let iss: String
        var iat: Date?
        var exp: Date?
    }
    
    enum PusherError: Error {
        case missingExpDateJWT
    }
}

extension String {
    func decodesJWT() throws -> [String: Any] {
        enum DecodeErrors: Error {
            case badToken
            case other
        }
        func base64Decode(_ base64: String) throws -> Data {
            let base64 = base64
                .replacingOccurrences(of: "-", with: "+")
            let padded = base64.padding(toLength: ((base64.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
            guard let decoded = Data(base64Encoded: padded) else {
                throw DecodeErrors.badToken
            }
            return decoded
        }
        func decodeJWTPart(_ value: String) throws -> [String: Any] {
            let bodyData = try base64Decode(value)
            let json = try JSONSerialization.jsonObject(with: bodyData, options: [])
            guard let payload = json as? [String: Any] else {
                throw DecodeErrors.other
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
