import XCTest
import CoreGraphics
@testable import Perch

final class IslandLayoutTests: XCTestCase {
    private let geometry = NotchGeometry(
        screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 982),
        notchWidth: 200,
        notchHeight: 32,
        hasNotch: true
    )

    func testCompactWidthFlanksTheNotch() {
        let layout = IslandLayout(geometry: geometry)
        XCTAssertEqual(layout.compactWidth, geometry.notchWidth + 2 * layout.earWidth)
    }

    func testContentRowHeightTracksEnabledFeatures() {
        XCTAssertEqual(IslandLayout(geometry: geometry, mediaEnabled: true, batteryEnabled: true).contentRowHeight, 66)
        XCTAssertEqual(IslandLayout(geometry: geometry, mediaEnabled: false, batteryEnabled: true).contentRowHeight, 40)
        XCTAssertEqual(IslandLayout(geometry: geometry, mediaEnabled: false, batteryEnabled: false).contentRowHeight, 0)
    }

    func testNoAgentsMeansNoAgentsSection() {
        let layout = IslandLayout(geometry: geometry)
        XCTAssertEqual(layout.agentsSectionHeight(sessionCount: 0), 0)
    }

    func testVisibleHeightGrowsWithSessions() {
        let layout = IslandLayout(geometry: geometry)
        let none = layout.expandedVisibleHeight(sessionCount: 0)
        let one = layout.expandedVisibleHeight(sessionCount: 1)
        let two = layout.expandedVisibleHeight(sessionCount: 2)
        XCTAssertLessThan(none, one)
        XCTAssertLessThan(one, two)
    }

    func testReservedHeightNeverExceededByVisibleHeight() {
        let layout = IslandLayout(geometry: geometry)
        // The window reserves the worst case; visible height for any realistic count must fit.
        for count in 0...10 {
            XCTAssertLessThanOrEqual(
                layout.expandedVisibleHeight(sessionCount: count, approvalCount: count),
                layout.expandedHeight + 0.0001
            )
        }
    }

    func testExpandedInteractiveRectInsetsWindowMargins() {
        let layout = IslandLayout(geometry: geometry)
        let visible = layout.expandedVisibleRect(sessionCount: 0)
        let interactive = layout.expandedInteractiveRect(sessionCount: 0)

        XCTAssertEqual(interactive.minX, visible.minX + layout.windowMarginX, accuracy: 0.0001)
        XCTAssertEqual(interactive.maxX, visible.maxX - layout.windowMarginX, accuracy: 0.0001)
        XCTAssertEqual(interactive.maxY, visible.maxY - layout.windowMarginBottom, accuracy: 0.0001)
        XCTAssertEqual(interactive.minY, visible.minY, accuracy: 0.0001)
    }
}
