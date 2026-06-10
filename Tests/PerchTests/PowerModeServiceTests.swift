import XCTest
@testable import Perch

final class PowerModeServiceTests: XCTestCase {
    func testParsesTrailingDigit() {
        XCTAssertEqual(PowerModeService.parsePowerMode(from: " powermode            0\n"), .automatic)
        XCTAssertEqual(PowerModeService.parsePowerMode(from: " powermode            1\n"), .lowPower)
        XCTAssertEqual(PowerModeService.parsePowerMode(from: " powermode            2\n"), .highPower)
    }

    func testParsesAmongOtherPmsetLines() {
        let output = """
        Active Profiles:
        Battery Power\t-1
         standbydelaylow      10800
         powermode            1
         hibernatemode        3
        """
        XCTAssertEqual(PowerModeService.parsePowerMode(from: output), .lowPower)
    }

    func testDefaultsToAutomaticWhenAbsentOrInvalid() {
        XCTAssertEqual(PowerModeService.parsePowerMode(from: "no power mode here"), .automatic)
        XCTAssertEqual(PowerModeService.parsePowerMode(from: " powermode            9\n"), .automatic)
        XCTAssertEqual(PowerModeService.parsePowerMode(from: " powermode            x\n"), .automatic)
        XCTAssertEqual(PowerModeService.parsePowerMode(from: ""), .automatic)
    }
}
