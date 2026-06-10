import XCTest
@testable import Perch

/// Covers the security-sensitive input validation that guards AppleScript interpolation and the
/// filenames written for the agent command back-channel. These reject anything outside a strict
/// allowlist, so injection-y inputs must come back nil / neutralized.
final class InputValidationTests: XCTestCase {
    private let focus = AgentFocusService()

    // MARK: - validatedTTY

    func testValidTTYPasses() {
        XCTAssertEqual(focus.validatedTTY("/dev/ttys001"), "/dev/ttys001")
    }

    func testTTYRejectsInjectionAndBadShape() {
        XCTAssertNil(focus.validatedTTY("/dev/ttys001; rm -rf /"))     // space + `;`
        XCTAssertNil(focus.validatedTTY("/dev/ttys\" do shell script")) // quote + space
        XCTAssertNil(focus.validatedTTY("ttys001"))                     // missing /dev/ prefix
        XCTAssertNil(focus.validatedTTY(""))
        XCTAssertNil(focus.validatedTTY(nil))
    }

    // MARK: - validatedSessionID

    func testValidSessionIDPasses() {
        XCTAssertEqual(focus.validatedSessionID("w0t1p0:ABCD-1234_x"), "w0t1p0:ABCD-1234_x")
    }

    func testSessionIDRejectsInjection() {
        XCTAssertNil(focus.validatedSessionID("abc\" tell application"))
        XCTAssertNil(focus.validatedSessionID("abc def"))   // space
        XCTAssertNil(focus.validatedSessionID(""))
        XCTAssertNil(focus.validatedSessionID(nil))
    }

    // MARK: - command filename sanitizer

    func testSanitizedFileNameKeepsAllowedChars() {
        XCTAssertEqual(AgentCommandService.sanitizedFileName("valid_id-1.2"), "valid_id-1.2")
    }

    func testSanitizedFileNameNeutralizesPathTraversal() {
        let result = AgentCommandService.sanitizedFileName("../../etc/passwd")
        XCTAssertNotNil(result)
        XCTAssertFalse(result!.contains("/"), "slashes must never survive into a path component")
        XCTAssertEqual(result, "etc_passwd")
    }

    func testSanitizedFileNameReturnsNilWhenNothingUsable() {
        XCTAssertNil(AgentCommandService.sanitizedFileName("...."))
        XCTAssertNil(AgentCommandService.sanitizedFileName("____"))
        XCTAssertNil(AgentCommandService.sanitizedFileName(""))
    }
}
