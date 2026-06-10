import XCTest
@testable import Perch

final class WidgetPreferencesTests: XCTestCase {
    func testDefaultCollapsedOrder() {
        let order = WidgetPreferences.loadCollapsed()
        XCTAssertTrue(order.contains(.agents))
        XCTAssertTrue(order.contains(.media))
    }

    func testEnabledChecksMembership() {
        let collapsed: [IslandWidget] = [.media, .agents]
        let expanded: [IslandWidget] = [.battery]
        XCTAssertTrue(WidgetPreferences.isEnabled(.media, collapsed: collapsed, expanded: expanded))
        XCTAssertTrue(WidgetPreferences.isEnabled(.battery, collapsed: collapsed, expanded: expanded))
        XCTAssertFalse(WidgetPreferences.isEnabled(.calendar, collapsed: collapsed, expanded: expanded))
    }
}
