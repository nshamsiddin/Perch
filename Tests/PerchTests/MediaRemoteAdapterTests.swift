import XCTest
@testable import Perch

final class MediaRemoteAdapterTests: XCTestCase {
    func testParsesAdapterJSONLine() {
        let line = #"{"title":"Song","artist":"Artist","album":"Album","playing":true,"bundleIdentifier":"com.spotify.client"}"#
        let np = MediaService.parseAdapterJSON(line)
        XCTAssertEqual(np?.title, "Song")
        XCTAssertEqual(np?.artist, "Artist")
        XCTAssertEqual(np?.isPlaying, true)
        XCTAssertEqual(np?.bundleIdentifier, "com.spotify.client")
    }

    func testRejectsEmptyTitle() {
        let line = #"{"title":"","artist":"A","album":"B","playing":false}"#
        XCTAssertNil(MediaService.parseAdapterJSON(line))
    }
}
