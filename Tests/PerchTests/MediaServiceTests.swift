import XCTest
@testable import Perch

final class MediaServiceTests: XCTestCase {
    func testParsesPlayingTrack() {
        let np = MediaService.parse("playing\nSong Title\nThe Artist\nThe Album", source: "Spotify")
        XCTAssertEqual(np?.title, "Song Title")
        XCTAssertEqual(np?.artist, "The Artist")
        XCTAssertEqual(np?.album, "The Album")
        XCTAssertEqual(np?.source, "Spotify")
        XCTAssertEqual(np?.isPlaying, true)
    }

    func testParsesPausedTrack() {
        let np = MediaService.parse("paused\nSong\nArtist\nAlbum", source: "Music")
        XCTAssertEqual(np?.isPlaying, false)
        XCTAssertEqual(np?.hasContent, true)
    }

    func testReturnsNilForInsufficientFields() {
        XCTAssertNil(MediaService.parse("stopped", source: "Music"))
        XCTAssertNil(MediaService.parse("playing\nSong\nArtist", source: "Spotify"))
        XCTAssertNil(MediaService.parse("", source: "Music"))
    }
}
