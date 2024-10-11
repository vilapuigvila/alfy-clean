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

    @Option(name: .shortAndLong, help: "The device tokens array. enter like this xxxxx, xxxxxx, xxxxx, ...")
    var deviceTokens: [String] = [
        "48a970d868ae2104f704fca65f6832a18542492d997f053a1106032d8fb9d465"
    ]
    // "5f1383c02e26fb3c7c334839a405576e4b71350263c18ebd86688de69fb99238" filip
    
    private var bearerToken: String = ""

// "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IjVLVFBLSEQzUFIifQ.eyJpc3MiOiI0Vjc1Vjg3U0g5IiwiaWF0IjoxNzI4NDgzMTQ4LCJleHAiOjE3Mjg0ODY3NDh9.etIDEKS656E7z7dc6764kazvW1tSQGYpPTe82-bfxVT-IpA9QECL0xGducGZm5DtC8NW9kRhZKmjv_wfOTt7Ig"
    var expirationTimeInterval: Double {
        3600*24
    }
    
//    let userDefaults = UserDefaults.standard
    private static let authTokenKey: String = "authToken"
}

extension Pusher {
    
    func run() throws {
        Print.withColor(.cyan, "Wait... sending push 🙏")
        
        guard !deviceTokens.isEmpty else {
            Print.withColor(.red, "no deviceTokens found")
            return
        }
        bearerToken = try isTokenExpired(token: fetchAuthTokenInUserPrefs())
        
        storeAuthTokenInUserPrefs(bearerToken)
        
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            do {
                for deviceToken in deviceTokens {
                    try await sendPushNotification(to: deviceToken)
                }
            } catch {
                Print.withColor(.red, "Error sending push notification: \(error)")
            }
            semaphore.signal()
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        semaphore.wait()
    }
    
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
            default:
                fatalError("UnAuthorized: status code: \(httpResponse.statusCode). Refresh your bearer token")
            }
        } catch {
            Print.withColor(.red, "Error: \(error.localizedDescription)")
        }
    }
    
    private func buildNewJWT() throws -> String {
        let teamID = "4V75V87SH9"
        let keyID = "5KTPKHD3PR"
        let apnsKeyPath = "/Users/albert/Desktop/AuthKey_5KTPKHD3PR.p8"

        let header = Header(typ: "JWT", kid: keyID)
        let claims = PusherClaims(iss: teamID, iat: Date(), exp: Date().addingTimeInterval(expirationTimeInterval))
        var jwt = JWT(header: header, claims: claims)
        let privateKeyString = try readPrivateKey(from: apnsKeyPath)
        let jwtSigner = JWTSigner.es256(privateKey: privateKeyString.data(using: .utf8)!)
        let token = try jwt.sign(using: jwtSigner)
        return token
    }
    
    private func readPrivateKey(from path: String) throws -> String {
        try String(contentsOfFile: path, encoding: .utf8)
    }
    
    func isTokenExpired(token: String) throws -> String {
        func buildNewToken() throws -> String {
            let refreshedToken = try buildNewJWT()
            Print.withColor(.yellow, "Auth has been refreshed:\n\(refreshedToken)")
            return refreshedToken
        }
        guard !token.isEmpty else {
            Print.withColor(.magenta, "Empty string token")
            return try buildNewToken()
        }
        guard let expDate = token.jwtExpirationDate else {
            throw "missingExpDateJWT"
        }
        if Date().timeIntervalSince(expDate) > TimeInterval(expirationTimeInterval) {
            return try buildNewToken()
        } else {
            Print.withColor(.green, "Current token is valid:\n\(token)")
            return token
        }
    }
    
    private func fetchAuthTokenInUserPrefs() -> String {
        guard let storedToken: String = UserDefaults.standard.string(forKey: Self.authTokenKey) else {
            Print.withColor(.magenta, "--------------------------\navp - empty token\n-------------------------")
            return ""
        }
        Print.withColor(.magenta, "Value stored token \(storedToken)")
        return storedToken
    }
    private func storeAuthTokenInUserPrefs(_ token: String) {
        UserDefaults.standard.setValue(token, forKey: Self.authTokenKey)
    }
    
    // MARK: - Helpers -
    
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
}
