import Testing
import Foundation
@testable import roadrunner

@Suite("URL Parsing")
struct URLParserTests {
    @Test("Parses org URL")
    func parsesOrgURL() throws {
        let target = try RunnerTarget.parse(url: "https://github.com/myorg")

        if case .org(let name) = target {
            #expect(name == "myorg")
        } else {
            Issue.record("Expected .org, got .repo")
        }
    }

    @Test("Parses repo URL")
    func parsesRepoURL() throws {
        let target = try RunnerTarget.parse(url: "https://github.com/owner/repo")

        if case .repo(let owner, let name) = target {
            #expect(owner == "owner")
            #expect(name == "repo")
        } else {
            Issue.record("Expected .repo, got .org")
        }
    }

    @Test("Strips .git suffix from repo URL")
    func stripsGitSuffix() throws {
        let target = try RunnerTarget.parse(url: "https://github.com/owner/repo.git")

        if case .repo(_, let name) = target {
            #expect(name == "repo")
        } else {
            Issue.record("Expected .repo")
        }
    }

    @Test("Parses URL with trailing slash")
    func trailingSlash() throws {
        let target = try RunnerTarget.parse(url: "https://github.com/myorg/")

        if case .org(let name) = target {
            #expect(name == "myorg")
        } else {
            Issue.record("Expected .org")
        }
    }

    @Test("Rejects non-GitHub URL")
    func rejectsNonGitHub() {
        #expect(throws: RoadrunnerError.self) {
            try RunnerTarget.parse(url: "https://gitlab.com/owner/repo")
        }
    }

    @Test("Rejects invalid URL")
    func rejectsInvalid() {
        #expect(throws: RoadrunnerError.self) {
            try RunnerTarget.parse(url: "not-a-url")
        }
    }
}
