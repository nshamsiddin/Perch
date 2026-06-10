import XCTest
@testable import Perch

final class AgentStatusServiceTests: XCTestCase {
    // MARK: - Claude lifecycle -> run state

    func testClaudeStateMapping() {
        XCTAssertEqual(AgentStatusService.claudeState(for: "Stop"), .done)
        XCTAssertEqual(AgentStatusService.claudeState(for: "Notification"), .waiting)
        XCTAssertEqual(AgentStatusService.claudeState(for: "PreToolUse"), .working)
        XCTAssertEqual(AgentStatusService.claudeState(for: "UserPromptSubmit"), .working)
        XCTAssertEqual(AgentStatusService.claudeState(for: ""), .working)
    }

    // MARK: - Cursor status -> run state

    func testCursorStateMapping() {
        XCTAssertEqual(AgentStatusService.cursorState(for: "done"), .done)
        XCTAssertEqual(AgentStatusService.cursorState(for: "stop"), .done)
        XCTAssertEqual(AgentStatusService.cursorState(for: "working"), .working)
        XCTAssertEqual(AgentStatusService.cursorState(for: "edit"), .working)
    }

    // MARK: - pid coercion (accepts number / numeric string, rejects <= 1)

    func testPIDCoercion() {
        XCTAssertEqual(AgentStatusService.pid(["pid": 1234]), 1234)
        XCTAssertEqual(AgentStatusService.pid(["pid": 1234.0]), 1234)
        XCTAssertEqual(AgentStatusService.pid(["pid": "1234"]), 1234)
        XCTAssertNil(AgentStatusService.pid(["pid": 1]))   // <= 1 rejected
        XCTAssertNil(AgentStatusService.pid(["pid": 0]))
        XCTAssertNil(AgentStatusService.pid(["pid": -5]))
        XCTAssertNil(AgentStatusService.pid(["pid": "not-a-number"]))
        XCTAssertNil(AgentStatusService.pid([:]))
    }

    // MARK: - token coercion (accepts number / numeric string, rejects <= 0)

    func testTokenCoercion() {
        XCTAssertEqual(AgentStatusService.tokens(["tokens": 500]), 500)
        XCTAssertEqual(AgentStatusService.tokens(["tokens": "500"]), 500)
        XCTAssertNil(AgentStatusService.tokens(["tokens": 0]))
        XCTAssertNil(AgentStatusService.tokens(["tokens": -1]))
        XCTAssertNil(AgentStatusService.tokens([:]))
    }
}
