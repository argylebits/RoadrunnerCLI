import ArgumentParser
import Foundation

struct ServiceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "service",
        abstract: "Manage the Roadrunner launchd service",
        subcommands: [InstallService.self, UninstallService.self, StatusService.self]
    )

    static let label = "com.argylebits.roadrunner"

    static var plistPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path()
        return "\(home)/Library/LaunchAgents/\(label).plist"
    }

    static var binaryPath: String {
        // Use the currently running binary's path
        let executableURL = URL(filePath: ProcessInfo.processInfo.arguments[0])
        // Resolve symlinks to get the real path
        let resolved = executableURL.resolvingSymlinksInPath()
        return resolved.path()
    }

    static func plistContents(binaryPath: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(label)</string>

            <key>ProgramArguments</key>
            <array>
                <string>\(binaryPath)</string>
                <string>run</string>
            </array>

            <key>RunAtLoad</key>
            <true/>

            <key>KeepAlive</key>
            <true/>

            <key>StandardOutPath</key>
            <string>/tmp/roadrunner.log</string>

            <key>StandardErrorPath</key>
            <string>/tmp/roadrunner.err</string>
        </dict>
        </plist>
        """
    }
}

struct InstallService: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "install",
        abstract: "Install and start the launchd service"
    )

    @Flag(help: "Overwrite existing service plist")
    var force: Bool = false

    mutating func run() throws {
        let plistPath = ServiceCommand.plistPath
        let binaryPath = ServiceCommand.binaryPath

        // Check config exists
        let configPath = RoadrunnerConfig.configPath.path()
        guard FileManager.default.fileExists(atPath: configPath) else {
            throw ServiceError.noConfig
        }

        // Check if already installed
        if FileManager.default.fileExists(atPath: plistPath) && !force {
            throw ServiceError.alreadyInstalled
        }

        // Unload existing service if present
        if isLoaded() {
            launchctl("unload", plistPath)
        }

        // Write plist
        let plist = ServiceCommand.plistContents(binaryPath: binaryPath)
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)

        // Load the service
        launchctl("load", plistPath)

        print("Service installed and started.")
        print("  Plist: \(plistPath)")
        print("  Binary: \(binaryPath)")
        print("  Logs: /tmp/roadrunner.log")
        print("")
        print("The daemon will start automatically on login.")
        print("Use `roadrunner service status` to check, `roadrunner service uninstall` to remove.")
    }

    private func isLoaded() -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = ["list", ServiceCommand.label]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    private func launchctl(_ args: String...) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = Array(args)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}

struct UninstallService: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "uninstall",
        abstract: "Stop and remove the launchd service"
    )

    mutating func run() throws {
        let plistPath = ServiceCommand.plistPath

        guard FileManager.default.fileExists(atPath: plistPath) else {
            throw ServiceError.notInstalled
        }

        // Unload
        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = ["unload", plistPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()

        // Remove plist
        try FileManager.default.removeItem(atPath: plistPath)

        print("Service stopped and removed.")
    }
}

struct StatusService: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "status",
        abstract: "Check if the launchd service is running"
    )

    mutating func run() throws {
        let plistPath = ServiceCommand.plistPath

        guard FileManager.default.fileExists(atPath: plistPath) else {
            print("Not installed.")
            return
        }

        let process = Process()
        process.executableURL = URL(filePath: "/bin/launchctl")
        process.arguments = ["list", ServiceCommand.label]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        if process.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""

            // Parse PID from launchctl list output
            // Format: { "Label" = "..."; "PID" = 1234; ... }
            if let pidRange = output.range(of: #""PID" = (\d+)"#, options: .regularExpression) {
                let pidStr = output[pidRange]
                    .replacingOccurrences(of: "\"PID\" = ", with: "")
                print("Running (PID \(pidStr)).")
            } else {
                print("Installed but not currently running.")
            }
        } else {
            print("Installed but not loaded.")
        }

        print("  Plist: \(plistPath)")
        print("  Logs: /tmp/roadrunner.log")
    }
}

enum ServiceError: Error, CustomStringConvertible {
    case noConfig
    case alreadyInstalled
    case notInstalled

    var description: String {
        switch self {
        case .noConfig:
            "No config found. Run `roadrunner init` first."
        case .alreadyInstalled:
            "Service already installed at \(ServiceCommand.plistPath) (use --force to overwrite)"
        case .notInstalled:
            "Service is not installed."
        }
    }
}
