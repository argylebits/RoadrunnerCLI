import Foundation

actor TokenManager {
    let jwtGenerator: JWTGenerator
    let installationID: String

    private var cachedToken: InstallationToken?

    init(jwtGenerator: JWTGenerator, installationID: String) {
        self.jwtGenerator = jwtGenerator
        self.installationID = installationID
    }

    func getInstallationToken() async throws -> String {
        if let cached = cachedToken, !cached.isExpiringSoon {
            return cached.token
        }

        let jwt = try jwtGenerator.generateJWT()

        let url = URL(string: "https://api.github.com/app/installations/\(installationID)/access_tokens")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RoadrunnerError.gitHubAPIError("Invalid response")
        }
        guard httpResponse.statusCode == 201 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RoadrunnerError.gitHubAPIError("Failed to get installation token (HTTP \(httpResponse.statusCode)): \(body)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["token"] as? String,
              let expiresAtString = json?["expires_at"] as? String else {
            throw RoadrunnerError.gitHubAPIError("Unexpected response format")
        }

        let formatter = ISO8601DateFormatter()
        let expiresAt = formatter.date(from: expiresAtString) ?? Date().addingTimeInterval(3600)

        cachedToken = InstallationToken(token: token, expiresAt: expiresAt)
        return token
    }
}

struct InstallationToken {
    let token: String
    let expiresAt: Date

    var isExpiringSoon: Bool {
        expiresAt.timeIntervalSinceNow < 300
    }
}
