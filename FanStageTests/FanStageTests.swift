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
    func testPlaybackSessionReleasesPlayerItem() {
        let session = PlaybackSession()
        guard let url = Bundle.main.url(forResource: "demo", withExtension: "mp4") else { return XCTFail("Missing demo video") }
        session.load(url)
        XCTAssertNotNil(session.player.currentItem)
        session.setSpeed(1.5)
        XCTAssertEqual(session.speed, 1.5)
        session.stop()
        XCTAssertNil(session.player.currentItem)
    }
    func testLocalServerIntegrationWhenConfigured() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let endpoint = environment["FANSTAGE_TEST_URL"], let token = environment["FANSTAGE_TEST_TOKEN"], let url = URL(string: endpoint) else { throw XCTSkip("Isolated local server not configured") }
        let chat = ChatSession(room: "ios-integration")
        defer { chat.stop() }
        chat.connect(base: url, token: token)
        for _ in 0..<100 where chat.status != "Connected" { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(chat.status, "Connected")
        let value = UUID().uuidString
        chat.send(value)
        for _ in 0..<100 where !chat.pending.isEmpty { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertTrue(chat.pending.isEmpty)
        XCTAssertTrue(chat.messages.contains { $0.text == value && $0.isOwn })
    }
    func testHLSWhenConfigured() async throws {
        guard let address = ProcessInfo.processInfo.environment["FANSTAGE_TEST_HLS"], let url = URL(string: address) else { throw XCTSkip("HLS fixture server not configured") }
        let session = PlaybackSession()
        defer { session.stop() }
        session.load(url)
        for _ in 0..<150 where session.player.currentItem?.status != .readyToPlay { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(session.player.currentItem?.status, .readyToPlay)
        XCTAssertNil(session.error)
        for _ in 0..<100 where session.subtitles.isEmpty { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertFalse(session.subtitles.isEmpty)
        session.selectSubtitle(0)
        XCTAssertEqual(session.selectedSubtitle, 0)
        for _ in 0..<100 where session.player.currentTime().seconds < 0.1 { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertGreaterThan(session.player.currentTime().seconds, 0.1)
    }
}
