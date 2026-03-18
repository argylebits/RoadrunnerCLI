import Testing
@preconcurrency import Foundation
@preconcurrency import Security
@testable import roadrunner

@Suite("JWT Generation")
struct JWTTests {
    // Generate a test RSA key pair for testing
    nonisolated(unsafe) static let testKey: SecKey = {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048,
        ]
        var error: Unmanaged<CFError>?
        return SecKeyCreateRandomKey(attributes as CFDictionary, &error)!
    }()

    @Test("JWT has three dot-separated parts")
    func threePartStructure() throws {
        let generator = JWTGenerator(privateKey: Self.testKey, appID: "12345")
        let jwt = try generator.generateJWT()

        let parts = jwt.split(separator: ".")
        #expect(parts.count == 3)
    }

    @Test("JWT header contains RS256 algorithm")
    func headerContainsRS256() throws {
        let generator = JWTGenerator(privateKey: Self.testKey, appID: "12345")
        let jwt = try generator.generateJWT()

        let headerPart = String(jwt.split(separator: ".")[0])
        let headerData = base64urlDecode(headerPart)!
        let header = String(data: headerData, encoding: .utf8)!

        #expect(header.contains("RS256"))
        #expect(header.contains("JWT"))
    }

    @Test("JWT payload contains correct app ID")
    func payloadContainsAppID() throws {
        let generator = JWTGenerator(privateKey: Self.testKey, appID: "99999")
        let jwt = try generator.generateJWT()

        let payloadPart = String(jwt.split(separator: ".")[1])
        let payloadData = base64urlDecode(payloadPart)!
        let payload = String(data: payloadData, encoding: .utf8)!

        #expect(payload.contains("99999"))
    }

    @Test("JWT payload has iat and exp fields")
    func payloadHasTimestamps() throws {
        let generator = JWTGenerator(privateKey: Self.testKey, appID: "12345")
        let jwt = try generator.generateJWT()

        let payloadPart = String(jwt.split(separator: ".")[1])
        let payloadData = base64urlDecode(payloadPart)!
        let payload = String(data: payloadData, encoding: .utf8)!

        #expect(payload.contains("iat"))
        #expect(payload.contains("exp"))
    }

    @Test("JWT uses base64url encoding (no +, /, or = characters)")
    func base64urlEncoding() throws {
        let generator = JWTGenerator(privateKey: Self.testKey, appID: "12345")
        let jwt = try generator.generateJWT()

        #expect(!jwt.contains("+"))
        #expect(!jwt.contains("/"))
        #expect(!jwt.contains("="))
    }

    private func base64urlDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        return Data(base64Encoded: base64)
    }
}
