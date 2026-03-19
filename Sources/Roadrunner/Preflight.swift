import Foundation

enum Preflight {
    static func check() throws {
        try checkContainerCLI()
        try ensureContainerSystem()
        try ensureKernelConfigured()
    }

    private static func checkContainerCLI() throws {
        let path = ContainerRunner.containerCLI
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw PreflightError.containerCLINotFound
        }
    }

    private static func ensureContainerSystem() throws {
        if isContainerSystemRunning() { return }

        print("[roadrunner] Container system is not running, starting it...")
        let start = Process()
        start.executableURL = URL(filePath: ContainerRunner.containerCLI)
        start.arguments = ["system", "start"]
        start.standardOutput = FileHandle.standardOutput
        start.standardError = FileHandle.standardError

        do {
            try start.run()
            start.waitUntilExit()
        } catch {
            throw PreflightError.containerSystemStartFailed
        }

        guard start.terminationStatus == 0 else {
            throw PreflightError.containerSystemStartFailed
        }

        // Give the system a moment to become ready
        Thread.sleep(forTimeInterval: 2)

        guard isContainerSystemRunning() else {
            throw PreflightError.containerSystemStartFailed
        }

        print("[roadrunner] Container system started.")
    }

    private static func isContainerSystemRunning() -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: ContainerRunner.containerCLI)
        process.arguments = ["system", "status"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Path to the default kernel symlink created by `container system kernel set`
    static let kernelSymlink = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/com.apple.container/kernels/default.kernel-arm64")

    private static func ensureKernelConfigured() throws {
        let kernelLink = kernelSymlink

        if FileManager.default.fileExists(atPath: kernelLink.path) { return }

        print("[roadrunner] No Linux kernel configured, installing recommended kernel...")
        let process = Process()
        process.executableURL = URL(filePath: ContainerRunner.containerCLI)
        process.arguments = ["system", "kernel", "set", "--recommended"]
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            throw PreflightError.kernelInstallFailed
        }

        guard process.terminationStatus == 0 else {
            throw PreflightError.kernelInstallFailed
        }

        print("[roadrunner] Kernel installed.")
    }
}

enum PreflightError: Error, CustomStringConvertible {
    case containerCLINotFound
    case containerSystemStartFailed
    case kernelInstallFailed

    var description: String {
        switch self {
        case .containerCLINotFound:
            """
            container CLI not found.

            Install it with Homebrew:
                brew install container
                brew services start container

            Or download from:
                https://github.com/apple/container/releases
            """
        case .containerSystemStartFailed:
            """
            Failed to start container system.

            Try starting it manually:
                container system start
            """
        case .kernelInstallFailed:
            """
            Failed to install Linux kernel.

            Try installing it manually:
                container system kernel set --recommended
            """
        }
    }
}
