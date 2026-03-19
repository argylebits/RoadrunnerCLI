import Testing
import Foundation
@testable import roadrunner

@Suite("Preflight Errors")
struct PreflightErrorTests {
    @Test("containerCLINotFound mentions brew install")
    func cliNotFoundMessage() {
        let error = PreflightError.containerCLINotFound
        #expect(error.description.contains("brew install container"))
    }

    @Test("containerCLINotFound mentions GitHub releases")
    func cliNotFoundGitHub() {
        let error = PreflightError.containerCLINotFound
        #expect(error.description.contains("github.com/apple/container"))
    }

    @Test("containerSystemStartFailed mentions manual start command")
    func systemStartFailedMessage() {
        let error = PreflightError.containerSystemStartFailed
        #expect(error.description.contains("container system start"))
    }

    @Test("kernelInstallFailed mentions recommended flag")
    func kernelInstallFailedMessage() {
        let error = PreflightError.kernelInstallFailed
        #expect(error.description.contains("container system kernel set --recommended"))
    }
}

@Suite("Preflight Kernel Path")
struct PreflightKernelPathTests {
    @Test("Kernel symlink path is in Application Support")
    func kernelPathLocation() {
        let path = Preflight.kernelSymlink.path
        #expect(path.contains("Library/Application Support/com.apple.container"))
    }

    @Test("Kernel symlink is for arm64 architecture")
    func kernelPathArm64() {
        let path = Preflight.kernelSymlink.path
        #expect(path.hasSuffix("default.kernel-arm64"))
    }

    @Test("Kernel symlink is in kernels directory")
    func kernelPathDirectory() {
        let path = Preflight.kernelSymlink.path
        #expect(path.contains("/kernels/"))
    }
}
