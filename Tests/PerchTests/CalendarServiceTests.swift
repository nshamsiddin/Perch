import XCTest
@testable import Perch

final class CalendarServiceTests: XCTestCase {
    func testMinutesUntilFutureEvent() {
        let start = Date().addingTimeInterval(10 * 60)
        let minutes = CalendarService.minutesUntil(start)
        XCTAssertTrue((9...10).contains(minutes))
    }

    func testMinutesUntilPastIsZero() {
        let start = Date().addingTimeInterval(-60)
        XCTAssertEqual(CalendarService.minutesUntil(start), 0)
    }
}
