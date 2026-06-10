import XCTest
@testable import Perch

final class AgentCommandServiceTests: XCTestCase {
    func testSetGatingWritesPausedUntilISO() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }

        let claudeDir = tmp.appendingPathComponent("claude", isDirectory: true)
        let cursorDir = tmp.appendingPathComponent("cursor", isDirectory: true)
        try fm.createDirectory(at: claudeDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: cursorDir, withIntermediateDirectories: true)

        let service = AgentCommandService()
        // Use reflection-free approach: write via private dirs by subclassing pattern —
        // instead, call setGating on real service and read one dir. For unit isolation, verify
        // the ISO formatter produces parseable output.
        let until = Date().addingTimeInterval(900)
        service.setGating(enabled: true, pausedUntil: until)

        let configURL = fm.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/agent-commands/_config.json")
        let data = try Data(contentsOf: configURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["gating"] as? Bool, true)
        let paused = json?["gating_paused_until"] as? String
        XCTAssertNotNil(paused)
        XCTAssertNotNil(ISO8601DateFormatter().date(from: paused!))
    }

    func testSetGatingClearsPauseWithNull() throws {
        let service = AgentCommandService()
        service.setGating(enabled: true, pausedUntil: Date().addingTimeInterval(60))
        service.setGating(enabled: true, pausedUntil: nil)

        let configURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/agent-commands/_config.json")
        let data = try Data(contentsOf: configURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertTrue(json?["gating_paused_until"] is NSNull)
    }
}
