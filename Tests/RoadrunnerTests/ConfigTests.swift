import Testing
import Foundation
@testable import roadrunner

@Suite("Config Parsing")
struct ConfigTests {
    @Test("Parses all fields from YAML")
    func parsesAllFields() throws {
        let yaml = """
        app-id: 12345
        installation-id: 67890
        private-key: ~/.roadrunner/private-key.pem
        url: https://github.com/myorg
        image: roadrunner:latest
        labels: self-hosted,linux
        cpus: 4
        memory: 8192
        """

        let tmpFile = FileManager.default.temporaryDirectory.appending(path: "roadrunner-test-config.yaml")
        try yaml.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = RoadrunnerConfig.loadFrom(path: tmpFile.path())

        #expect(config.appId == 12345)
        #expect(config.installationId == 67890)
        #expect(config.privateKey != nil)
        #expect(config.privateKey?.hasSuffix("private-key.pem") == true)
        #expect(config.url == "https://github.com/myorg")
        #expect(config.image == "roadrunner:latest")
        #expect(config.labels == "self-hosted,linux")
        #expect(config.cpus == 4)
        #expect(config.memory == 8192)
    }

    @Test("Expands tilde in private-key path")
    func expandsTilde() throws {
        let yaml = "private-key: ~/some/path.pem"
        let tmpFile = FileManager.default.temporaryDirectory.appending(path: "roadrunner-test-tilde.yaml")
        try yaml.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = RoadrunnerConfig.loadFrom(path: tmpFile.path())

        #expect(config.privateKey?.hasPrefix("/") == true)
        #expect(config.privateKey?.contains("~") == false)
    }

    @Test("Skips comments and empty lines")
    func skipsComments() throws {
        let yaml = """
        # This is a comment
        app-id: 99

        # Another comment
        cpus: 8
        """
        let tmpFile = FileManager.default.temporaryDirectory.appending(path: "roadrunner-test-comments.yaml")
        try yaml.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = RoadrunnerConfig.loadFrom(path: tmpFile.path())

        #expect(config.appId == 99)
        #expect(config.cpus == 8)
        #expect(config.url == nil)
    }

    @Test("Handles colons in URL values")
    func colonsInValues() throws {
        let yaml = "url: https://github.com/myorg"
        let tmpFile = FileManager.default.temporaryDirectory.appending(path: "roadrunner-test-colons.yaml")
        try yaml.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = RoadrunnerConfig.loadFrom(path: tmpFile.path())

        #expect(config.url == "https://github.com/myorg")
    }

    @Test("Returns empty config for missing file")
    func missingFile() {
        let config = RoadrunnerConfig.loadFrom(path: "/nonexistent/config.yaml")

        #expect(config.appId == nil)
        #expect(config.url == nil)
    }

    @Test("privateKeyPath is inside configDir")
    func privateKeyPathLocation() {
        let keyPath = RoadrunnerConfig.privateKeyPath.path
        let dirPath = RoadrunnerConfig.configDir.path
        #expect(keyPath.hasPrefix(dirPath))
        #expect(keyPath.hasSuffix("private-key.pem"))
    }
}
