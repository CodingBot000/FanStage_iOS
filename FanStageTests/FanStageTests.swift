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
    func testChatOrdersAndDeduplicatesAndIgnoresOtherRooms() {
        let chat = ChatSession(room: "studio-session")
        func row(_ n: Int, room: String = "studio-session") -> ServerMessage {
            ServerMessage(roomId: room, messageId: "\(n)", clientMessageId: nil, serverSequence: n, text: "\(n)", isOwn: false, sentAt: "")
        }
        chat.merge(row(2))
        XCTAssertTrue(chat.gapUnresolved)
        chat.merge(row(1, room: "other-room"))
        XCTAssertTrue(chat.gapUnresolved)
        chat.merge(row(1))
        chat.merge(row(2))
        XCTAssertEqual(chat.messages.map(\.serverSequence), [1, 2])
        XCTAssertFalse(chat.gapUnresolved)
    }
    func testAckResolvesPendingByClientID() {
        let chat = ChatSession(room: "studio-session")
        chat.send("hello")
        let id = chat.pending[0].id
        chat.merge(ServerMessage(roomId: "studio-session", messageId: "server", clientMessageId: id, serverSequence: 1, text: "hello", isOwn: true, sentAt: ""))
        XCTAssertTrue(chat.pending.isEmpty)
        XCTAssertEqual(chat.messages.count, 1)
    }
}
