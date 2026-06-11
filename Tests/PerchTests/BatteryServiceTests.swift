import IOKit.ps
import XCTest
@testable import Perch

final class BatteryServiceTests: XCTestCase {
    func testParsesValidAdapterWatts() {
        let details = [kIOPSPowerAdapterWattsKey as String: 96]
        XCTAssertEqual(BatteryService.parseAdapterWatts(from: details), 96)
    }

    func testReturnsNilWhenWattsKeyMissing() {
        XCTAssertNil(BatteryService.parseAdapterWatts(from: [:]))
        XCTAssertNil(BatteryService.parseAdapterWatts(from: nil))
    }

    func testReturnsNilForNonPositiveWatts() {
        XCTAssertNil(BatteryService.parseAdapterWatts(from: [kIOPSPowerAdapterWattsKey as String: 0]))
        XCTAssertNil(BatteryService.parseAdapterWatts(from: [kIOPSPowerAdapterWattsKey as String: -30]))
    }

    func testReturnsNilForNonIntegerWatts() {
        XCTAssertNil(BatteryService.parseAdapterWatts(from: [kIOPSPowerAdapterWattsKey as String: "96"]))
        XCTAssertNil(BatteryService.parseAdapterWatts(from: [kIOPSPowerAdapterWattsKey as String: 96.5]))
    }
}
