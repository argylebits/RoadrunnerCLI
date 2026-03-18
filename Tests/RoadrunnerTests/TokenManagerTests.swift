import Testing
import Foundation
@testable import roadrunner

@Suite("Token Manager")
struct TokenManagerTests {
    @Test("InstallationToken detects expiring soon")
    func expiringToken() {
        let expiringSoon = InstallationToken(
            token: "test-token",
            expiresAt: Date().addingTimeInterval(60)  // 1 minute left
        )
        #expect(expiringSoon.isExpiringSoon == true)

        let stillValid = InstallationToken(
            token: "test-token",
            expiresAt: Date().addingTimeInterval(600)  // 10 minutes left
        )
        #expect(stillValid.isExpiringSoon == false)
    }

    @Test("InstallationToken near 5-minute boundary")
    func boundaryToken() {
        let safelyAbove = InstallationToken(
            token: "test-token",
            expiresAt: Date().addingTimeInterval(310)  // 10 seconds of margin
        )
        #expect(safelyAbove.isExpiringSoon == false)

        let justUnder = InstallationToken(
            token: "test-token",
            expiresAt: Date().addingTimeInterval(290)
        )
        #expect(justUnder.isExpiringSoon == true)
    }

    @Test("Expired token is expiring soon")
    func expiredToken() {
        let expired = InstallationToken(
            token: "test-token",
            expiresAt: Date().addingTimeInterval(-60)  // expired 1 minute ago
        )
        #expect(expired.isExpiringSoon == true)
    }
}
