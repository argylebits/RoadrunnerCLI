import Foundation
import Security

struct JWTGenerator {
    let privateKey: SecKey
    let appID: String

    init(pemPath: String, appID: String) throws {
        let pemData = try String(contentsOfFile: pemPath, encoding: .utf8)
        self.privateKey = try Self.loadPrivateKey(pem: pemData)
        self.appID = appID
    }

    func generateJWT() throws -> String {
        let now = Date()
        let header = #"{"alg":"RS256","typ":"JWT"}"#
        let payload = """
        {"iss":"\(appID)","iat":\(Int(now.timeIntervalSince1970) - 60),"exp":\(Int(now.timeIntervalSince1970) + 600)}
        """

        let encodedHeader = Self.base64urlEncode(Data(header.utf8))
        let encodedPayload = Self.base64urlEncode(Data(payload.utf8))
        let signingInput = "\(encodedHeader).\(encodedPayload)"

        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .rsaSignatureMessagePKCS1v15SHA256,
            Data(signingInput.utf8) as CFData,
            &error
        ) as Data? else {
            throw GumpError.jwtSigningFailed(error?.takeRetainedValue().localizedDescription ?? "Unknown error")
        }

        let encodedSignature = Self.base64urlEncode(signature)
        return "\(signingInput).\(encodedSignature)"
    }

    private static func loadPrivateKey(pem: String) throws -> SecKey {
        let lines = pem.components(separatedBy: "\n")
            .filter { !$0.hasPrefix("-----") && !$0.isEmpty }
        let base64 = lines.joined()

        guard let derData = Data(base64Encoded: base64) else {
            throw GumpError.invalidPrivateKey("Failed to decode PEM base64 data")
        }

        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPrivate,
            kSecAttrKeySizeInBits as String: derData.count * 8,
        ]

        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(derData as CFData, attributes as CFDictionary, &error) else {
            throw GumpError.invalidPrivateKey(error?.takeRetainedValue().localizedDescription ?? "Unknown error")
        }

        return key
    }

    private static func base64urlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
