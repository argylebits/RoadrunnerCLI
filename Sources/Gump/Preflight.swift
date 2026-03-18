import Foundation

enum Preflight {
    static func check() throws {
        try checkContainerCLI()
        try checkContainerSystem()
    }

    private static func checkContainerCLI() throws {
        let path = ContainerRunner.containerCLI
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw PreflightError.containerCLINotFound
        }
    }

    private static func checkContainerSystem() throws {
        let process = Process()
        process.executableURL = URL(filePath: ContainerRunner.containerCLI)
        process.arguments = ["system", "status"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw PreflightError.containerSystemNotRunning
            }
        } catch is PreflightError {
            throw PreflightError.containerSystemNotRunning
        } catch {
            throw PreflightError.containerSystemNotRunning
        }
    }
}

enum PreflightError: Error, CustomStringConvertible {
    case containerCLINotFound
    case containerSystemNotRunning

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
        case .containerSystemNotRunning:
            """
            Container system is not running.

            Start it with:
                brew services start container

            Or manually:
                container system start
            """
        }
    }
}
