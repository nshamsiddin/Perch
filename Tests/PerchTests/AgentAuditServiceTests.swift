import XCTest
@testable import Perch

final class AgentAuditServiceTests: XCTestCase {
    func testRecordAndReadRecentEntries() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let logURL = tmp.appendingPathComponent("agent-audit.jsonl")
        defer { try? fm.removeItem(at: tmp) }

        let audit = AgentAuditService(logURL: logURL)
        let session = AgentSession(
            id: "claudeCode:abc-123",
            tool: .claudeCode,
            project: "MyProject",
            cwd: "/tmp",
            state: .waiting,
            updatedAt: Date(),
            activity: "Run npm",
            branch: "main",
            pendingApproval: ApprovalRequest(
                requestID: "req1",
                toolName: "Bash",
                target: "npm",
                summary: "Run npm"
            )
        )

        audit.record(.allow, session: session, note: "looks good")
        // Async append — brief wait for queue.
        let exp = expectation(description: "audit write")
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { exp.fulfill() }
        wait(for: [exp], timeout: 1)

        let entries = audit.recentEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].decision, .allow)
        XCTAssertEqual(entries[0].project, "MyProject")
        XCTAssertEqual(entries[0].target, "npm")
        XCTAssertEqual(entries[0].note, "looks good")
        XCTAssertEqual(entries[0].branch, "main")
        XCTAssertFalse(entries[0].sessionID.contains(":"))
    }
}
