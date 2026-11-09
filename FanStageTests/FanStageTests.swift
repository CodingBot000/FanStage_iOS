import XCTest
@testable import FanStage

@MainActor final class FanStageTests: XCTestCase {
    func testCommunityAndMessages() {
        let store = FanStore()
        let post = store.posts[0]
        store.toggleLike(post.id)
        XCTAssertTrue(store.posts[0].liked)
        store.comment(post.id, text: "  Hello  ")
        XCTAssertEqual(store.posts[0].comments, ["Hello"])
        store.send(post.artist, text: " Hi ")
        XCTAssertEqual(store.conversations[post.artist.id]?.last?.text, "Hi")
    }
}
