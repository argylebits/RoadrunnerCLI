import Testing
import Foundation
@testable import roadrunner

@Suite("Launchd Plist Generation")
struct LaunchdPlistTests {
    @Test("Generates valid plist with correct label")
    func plistContainsLabel() {
        let plist = LaunchdPlist.generate(binaryPath: "/usr/local/bin/roadrunner")
        #expect(plist.contains("com.argylebits.roadrunner"))
    }

    @Test("Generates plist with correct binary path")
    func plistContainsBinaryPath() {
        let plist = LaunchdPlist.generate(binaryPath: "/usr/local/bin/roadrunner")
        #expect(plist.contains("<string>/usr/local/bin/roadrunner</string>"))
    }

    @Test("Generates plist with run subcommand")
    func plistContainsRunCommand() {
        let plist = LaunchdPlist.generate(binaryPath: "/usr/local/bin/roadrunner")
        #expect(plist.contains("<string>run</string>"))
    }

    @Test("Generates plist with RunAtLoad")
    func plistRunAtLoad() {
        let plist = LaunchdPlist.generate(binaryPath: "/usr/local/bin/roadrunner")
        #expect(plist.contains("<key>RunAtLoad</key>"))
        #expect(plist.contains("<true/>"))
    }

    @Test("Generates plist with KeepAlive")
    func plistKeepAlive() {
        let plist = LaunchdPlist.generate(binaryPath: "/usr/local/bin/roadrunner")
        #expect(plist.contains("<key>KeepAlive</key>"))
    }

    @Test("Generates plist with log paths")
    func plistLogPaths() {
        let plist = LaunchdPlist.generate(binaryPath: "/usr/local/bin/roadrunner")
        #expect(plist.contains("/tmp/roadrunner.log"))
        #expect(plist.contains("/tmp/roadrunner.err"))
    }

    @Test("Generates plist with custom binary path")
    func plistCustomBinaryPath() {
        let plist = LaunchdPlist.generate(binaryPath: "/opt/homebrew/bin/roadrunner")
        #expect(plist.contains("<string>/opt/homebrew/bin/roadrunner</string>"))
        #expect(!plist.contains("/usr/local/bin"))
    }

    @Test("Plist is valid XML")
    func plistIsValidXML() {
        let plist = LaunchdPlist.generate(binaryPath: "/usr/local/bin/roadrunner")
        #expect(plist.hasPrefix("<?xml version=\"1.0\""))
        #expect(plist.contains("</plist>"))
    }

    @Test("Plist path is in LaunchAgents")
    func plistPathLocation() {
        let path = LaunchdPlist.plistPath
        #expect(path.contains("Library/LaunchAgents"))
        #expect(path.hasSuffix("com.argylebits.roadrunner.plist"))
    }
}

@Suite("PID Parsing")
struct PIDParsingTests {
    @Test("Parses PID from running service output")
    func parsesRunningPID() {
        let output = """
        {
        \t"LimitLoadToSessionType" = "Aqua";
        \t"Label" = "com.argylebits.roadrunner";
        \t"OnDemand" = true;
        \t"LastExitStatus" = 0;
        \t"PID" = 12345;
        \t"Program" = "/usr/local/bin/roadrunner";
        };
        """
        #expect(LaunchdPlist.parsePID(from: output) == 12345)
    }

    @Test("Returns nil when no PID in output")
    func noPIDWhenNotRunning() {
        let output = """
        {
        \t"LimitLoadToSessionType" = "Aqua";
        \t"Label" = "com.argylebits.roadrunner";
        \t"OnDemand" = true;
        \t"LastExitStatus" = 0;
        \t"Program" = "/usr/local/bin/roadrunner";
        };
        """
        #expect(LaunchdPlist.parsePID(from: output) == nil)
    }

    @Test("Returns nil for empty output")
    func emptyOutput() {
        #expect(LaunchdPlist.parsePID(from: "") == nil)
    }

    @Test("Parses large PID")
    func largePID() {
        let output = """
        {
        \t"PID" = 99999;
        };
        """
        #expect(LaunchdPlist.parsePID(from: output) == 99999)
    }

    @Test("Parses single-digit PID")
    func singleDigitPID() {
        let output = """
        {
        \t"PID" = 1;
        };
        """
        #expect(LaunchdPlist.parsePID(from: output) == 1)
    }
}

@Suite("Service Errors")
struct ServiceErrorTests {
    @Test("noConfig error message mentions init")
    func noConfigMessage() {
        let error = ServiceError.noConfig
        #expect(error.description.contains("roadrunner init"))
    }

    @Test("alreadyInstalled error message mentions force")
    func alreadyInstalledMessage() {
        let error = ServiceError.alreadyInstalled
        #expect(error.description.contains("--force"))
    }

    @Test("notInstalled error message")
    func notInstalledMessage() {
        let error = ServiceError.notInstalled
        #expect(error.description.contains("not installed"))
    }
}
