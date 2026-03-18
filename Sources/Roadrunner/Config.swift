import Foundation

struct RoadrunnerConfig: Codable {
    var appId: Int?
    var installationId: Int?
    var privateKey: String?
    var url: String?
    var image: String?
    var labels: String?
    var cpus: Int?
    var memory: Int?

    static let configDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".roadrunner")
    }()

    static let configPath: URL = {
        configDir.appending(path: "config.yaml")
    }()

    static func load() -> RoadrunnerConfig {
        loadFrom(path: configPath.path())
    }

    static func loadFrom(path: String) -> RoadrunnerConfig {
        guard FileManager.default.fileExists(atPath: path),
              let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            return RoadrunnerConfig()
        }
        return parse(yaml: contents)
    }

    /// Minimal YAML parser for flat key-value config
    private static func parse(yaml: String) -> RoadrunnerConfig {
        var config = RoadrunnerConfig()
        for line in yaml.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            guard let colonIndex = trimmed.firstIndex(of: ":") else { continue }
            let key = trimmed[..<colonIndex].trimmingCharacters(in: .whitespaces)
            let afterColon = trimmed.index(after: colonIndex)
            let value = String(trimmed[afterColon...]).trimmingCharacters(in: .whitespaces)

            switch key {
            case "app-id":
                config.appId = Int(value)
            case "installation-id":
                config.installationId = Int(value)
            case "private-key":
                config.privateKey = (value as NSString).expandingTildeInPath
            case "url":
                config.url = value
            case "image":
                config.image = value
            case "labels":
                config.labels = value
            case "cpus":
                config.cpus = Int(value)
            case "memory":
                config.memory = Int(value)
            default:
                break
            }
        }
        return config
    }
}
