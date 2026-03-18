import Testing
import Foundation
@testable import roadrunner

@Suite("Shell Alias")
struct ShellAliasTests {
    // MARK: - rcFilePath

    @Test("Detects zsh rc file")
    func zshRcFile() {
        #expect(ShellAlias.rcFilePath(forShell: "/bin/zsh") == "~/.zshrc")
    }

    @Test("Detects bash rc file")
    func bashRcFile() {
        #expect(ShellAlias.rcFilePath(forShell: "/bin/bash") == "~/.bashrc")
    }

    @Test("Detects zsh from non-standard path")
    func nonStandardZsh() {
        #expect(ShellAlias.rcFilePath(forShell: "/opt/homebrew/bin/zsh") == "~/.zshrc")
    }

    @Test("Returns nil for unknown shell")
    func unknownShell() {
        #expect(ShellAlias.rcFilePath(forShell: "/bin/fish") == nil)
        #expect(ShellAlias.rcFilePath(forShell: "/bin/nu") == nil)
    }

    // MARK: - aliasLine

    @Test("Builds correct alias line with default name")
    func defaultAliasLine() {
        #expect(ShellAlias.aliasLine(name: "rr") == "alias rr='roadrunner'")
    }

    @Test("Builds correct alias line with custom name")
    func customAliasLine() {
        #expect(ShellAlias.aliasLine(name: "runner") == "alias runner='roadrunner'")
    }

    // MARK: - add

    @Test("Adds alias to existing file")
    func addsToExistingFile() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appending(path: "roadrunner-test-alias-\(UUID().uuidString).zshrc")
        try "# existing content\n".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = ShellAlias.add(name: "rr", toFile: tmpFile.path())
        #expect(result == .added)

        let contents = try String(contentsOf: tmpFile, encoding: .utf8)
        #expect(contents.contains("alias rr='roadrunner'"))
        #expect(contents.hasPrefix("# existing content"))
    }

    @Test("Creates file if it doesn't exist")
    func createsNewFile() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appending(path: "roadrunner-test-alias-\(UUID().uuidString).zshrc")
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        // File should not exist yet
        #expect(!FileManager.default.fileExists(atPath: tmpFile.path()))

        let result = ShellAlias.add(name: "rr", toFile: tmpFile.path())
        #expect(result == .added)

        let contents = try String(contentsOf: tmpFile, encoding: .utf8)
        #expect(contents.contains("alias rr='roadrunner'"))
    }

    @Test("Detects existing alias")
    func detectsDuplicate() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appending(path: "roadrunner-test-alias-\(UUID().uuidString).zshrc")
        try "alias rr='roadrunner'\n".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = ShellAlias.add(name: "rr", toFile: tmpFile.path())
        #expect(result == .alreadyExists)
    }

    @Test("Does not duplicate alias on repeated calls")
    func noDuplicateOnRepeat() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appending(path: "roadrunner-test-alias-\(UUID().uuidString).zshrc")
        try "# shell config\n".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let first = ShellAlias.add(name: "rr", toFile: tmpFile.path())
        #expect(first == .added)

        let second = ShellAlias.add(name: "rr", toFile: tmpFile.path())
        #expect(second == .alreadyExists)
    }

    @Test("Supports custom alias name")
    func customName() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appending(path: "roadrunner-test-alias-\(UUID().uuidString).zshrc")
        try "".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        let result = ShellAlias.add(name: "runner", toFile: tmpFile.path())
        #expect(result == .added)

        let contents = try String(contentsOf: tmpFile, encoding: .utf8)
        #expect(contents.contains("alias runner='roadrunner'"))
    }

    @Test("Different alias names don't conflict")
    func differentNamesNoConflict() throws {
        let tmpFile = FileManager.default.temporaryDirectory
            .appending(path: "roadrunner-test-alias-\(UUID().uuidString).zshrc")
        try "alias rr='roadrunner'\n".write(to: tmpFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmpFile) }

        // "rr" exists, but "runner" does not
        let result = ShellAlias.add(name: "runner", toFile: tmpFile.path())
        #expect(result == .added)

        let contents = try String(contentsOf: tmpFile, encoding: .utf8)
        #expect(contents.contains("alias rr='roadrunner'"))
        #expect(contents.contains("alias runner='roadrunner'"))
    }

    @Test("Returns failed for unwritable path")
    func failsOnBadPath() {
        let result = ShellAlias.add(name: "rr", toFile: "/nonexistent/dir/file")
        if case .failed = result {
            // expected
        } else {
            Issue.record("Expected .failed, got \(result)")
        }
    }
}

@Suite("Init Config Writing")
struct InitConfigTests {
    @Test("InitError describes config exists")
    func configExistsError() {
        let error = InitError.configExists
        #expect(error.description.contains("~/.roadrunner/config.yaml"))
        #expect(error.description.contains("--force"))
    }

    @Test("InitError describes missing input")
    func missingInputError() {
        let error = InitError.missingInput("app-id")
        #expect(error.description.contains("app-id"))
    }

    @Test("InitError describes invalid input")
    func invalidInputError() {
        let error = InitError.invalidInput("cpus", "abc")
        #expect(error.description.contains("cpus"))
        #expect(error.description.contains("abc"))
    }

    @Test("InitError describes file not found")
    func fileNotFoundError() {
        let error = InitError.fileNotFound("~/missing.pem")
        #expect(error.description.contains("~/missing.pem"))
    }
}
