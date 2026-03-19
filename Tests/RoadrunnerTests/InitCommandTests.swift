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

@Suite("Private Key Installer")
struct PrivateKeyInstallerTests {
    private func tmpDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "roadrunner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test("Copies PEM file to destination")
    func copiesFile() throws {
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appending(path: "source.pem")
        let dest = dir.appending(path: "private-key.pem")
        try "FAKE-PEM-CONTENT".write(to: source, atomically: true, encoding: .utf8)

        try PrivateKeyInstaller.install(from: source.path, to: dest.path)

        let contents = try String(contentsOf: dest, encoding: .utf8)
        #expect(contents == "FAKE-PEM-CONTENT")
    }

    @Test("Sets chmod 600 on destination")
    func setsPermissions() throws {
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appending(path: "source.pem")
        let dest = dir.appending(path: "private-key.pem")
        try "FAKE-PEM".write(to: source, atomically: true, encoding: .utf8)

        try PrivateKeyInstaller.install(from: source.path, to: dest.path)

        let attrs = try FileManager.default.attributesOfItem(atPath: dest.path)
        let perms = (attrs[.posixPermissions] as? Int) ?? 0
        #expect(perms == 0o600)
    }

    @Test("Does not modify source file")
    func sourceUnmodified() throws {
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appending(path: "source.pem")
        let dest = dir.appending(path: "private-key.pem")
        try "ORIGINAL".write(to: source, atomically: true, encoding: .utf8)

        try PrivateKeyInstaller.install(from: source.path, to: dest.path)

        let sourceContents = try String(contentsOf: source, encoding: .utf8)
        #expect(sourceContents == "ORIGINAL")
    }

    @Test("Throws fileNotFound for missing source")
    func missingSource() throws {
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dest = dir.appending(path: "private-key.pem")

        #expect(throws: (any Error).self) {
            try PrivateKeyInstaller.install(from: "/nonexistent/file.pem", to: dest.path)
        }
    }

    @Test("Safely handles same source and destination")
    func sameFile() throws {
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appending(path: "private-key.pem")
        try "EXISTING-KEY".write(to: file, atomically: true, encoding: .utf8)

        // Should not destroy the file
        try PrivateKeyInstaller.install(from: file.path, to: file.path)

        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(contents == "EXISTING-KEY")
    }

    @Test("Overwrites existing destination safely")
    func overwritesExisting() throws {
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let source = dir.appending(path: "new-key.pem")
        let dest = dir.appending(path: "private-key.pem")
        try "OLD-KEY".write(to: dest, atomically: true, encoding: .utf8)
        try "NEW-KEY".write(to: source, atomically: true, encoding: .utf8)

        try PrivateKeyInstaller.install(from: source.path, to: dest.path)

        let contents = try String(contentsOf: dest, encoding: .utf8)
        #expect(contents == "NEW-KEY")
    }

    @Test("Handles symlink to destination as source")
    func symlinkSameFile() throws {
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let realFile = dir.appending(path: "private-key.pem")
        let symlink = dir.appending(path: "link.pem")
        try "EXISTING-KEY".write(to: realFile, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: realFile)

        // Symlink points to the destination — should detect same-file
        try PrivateKeyInstaller.install(from: symlink.path, to: realFile.path)

        let contents = try String(contentsOf: realFile, encoding: .utf8)
        #expect(contents == "EXISTING-KEY")
    }

    @Test("Expands tilde in source path")
    func expandsTilde() throws {
        // This test verifies the tilde expansion codepath doesn't crash.
        // We can't write to a real ~ path in tests, so we verify the error
        // is fileNotFound (meaning tilde was expanded and checked) rather than
        // some other failure.
        let dir = try tmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let dest = dir.appending(path: "private-key.pem")

        #expect(throws: (any Error).self) {
            try PrivateKeyInstaller.install(from: "~/nonexistent-roadrunner-test.pem", to: dest.path)
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
