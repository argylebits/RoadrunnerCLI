import Testing
import Foundation
@testable import gump

@Suite("Config Parsing")
struct ConfigTests {
    @Test("Parses all fields from YAML")
    func parsesAllFields() throws {
        let yaml = """
        app-id: 12345
        installation-id: 67890
        private-key: ~/.gump/private-key.pem
        url: https://github.com/myorg
        image: gump-runner:latest
        labels: self-hosted,linux
        cpus: 4
        memory: 8192
        """

        let tmpFile = FileManager.default.temporaryDirectory.appending(path: "gump-test-config.yaml")
        try yaml.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = GumpConfig.loadFrom(path: tmpFile.path())

        #expect(config.appId == 12345)
        #expect(config.installationId == 67890)
        #expect(config.privateKey != nil)
        #expect(config.privateKey?.hasSuffix("private-key.pem") == true)
        #expect(config.url == "https://github.com/myorg")
        #expect(config.image == "gump-runner:latest")
        #expect(config.labels == "self-hosted,linux")
        #expect(config.cpus == 4)
        #expect(config.memory == 8192)
    }

    @Test("Expands tilde in private-key path")
    func expandsTilde() throws {
        let yaml = "private-key: ~/some/path.pem"
        let tmpFile = FileManager.default.temporaryDirectory.appending(path: "gump-test-tilde.yaml")
        try yaml.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = GumpConfig.loadFrom(path: tmpFile.path())

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
        let tmpFile = FileManager.default.temporaryDirectory.appending(path: "gump-test-comments.yaml")
        try yaml.write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let config = GumpConfig.loadFrom(path: tmpFile.path())

        #expect(config.appId == 99)
        #expect(config.cpus == 8)
        #expect(config.url == nil)
    }

    @Test("Returns empty config for missing file")
    func missingFile() {
        let config = GumpConfig.loadFrom(path: "/nonexistent/config.yaml")

        #expect(config.appId == nil)
        #expect(config.url == nil)
    }
}
