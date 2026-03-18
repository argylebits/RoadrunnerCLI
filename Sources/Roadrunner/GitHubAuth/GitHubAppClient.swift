import Foundation

struct GitHubAppClient {
    let tokenManager: TokenManager
    let target: RunnerTarget

    func getRegistrationToken() async throws -> String {
        let installationToken = try await tokenManager.getInstallationToken()

        let url: URL
        switch target {
        case .repo(let owner, let name):
            url = URL(string: "https://api.github.com/repos/\(owner)/\(name)/actions/runners/registration-token")!
        case .org(let name):
            url = URL(string: "https://api.github.com/orgs/\(name)/actions/runners/registration-token")!
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(installationToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RoadrunnerError.gitHubAPIError("Invalid response")
        }
        guard httpResponse.statusCode == 201 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RoadrunnerError.gitHubAPIError("Failed to get registration token (HTTP \(httpResponse.statusCode)): \(body)")
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let token = json?["token"] as? String else {
            throw RoadrunnerError.gitHubAPIError("Unexpected response format")
        }

        return token
    }
}

enum RunnerTarget {
    case repo(owner: String, name: String)
    case org(name: String)

    static func parse(url urlString: String) throws -> RunnerTarget {
        guard let url = URL(string: urlString),
              url.host() == "github.com" else {
            throw RoadrunnerError.invalidURL(urlString)
        }

        let components = url.pathComponents.filter { $0 != "/" }

        switch components.count {
        case 1:
            return .org(name: components[0])
        case 2:
            let repo = components[1].hasSuffix(".git")
                ? String(components[1].dropLast(4))
                : components[1]
            return .repo(owner: components[0], name: repo)
        default:
            throw RoadrunnerError.invalidURL(urlString)
        }
    }
}
