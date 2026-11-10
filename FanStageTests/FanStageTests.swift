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
        chat.connect(base: URL(string: "http://127.0.0.1:1")!, token: "test-token")
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
        chat.suspend()
        let delayed = UUID().uuidString
        chat.send(delayed)
        let stableID = try XCTUnwrap(chat.pending.first?.id)
        chat.reconnect()
        for _ in 0..<100 where !chat.pending.isEmpty { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertTrue(chat.pending.isEmpty)
        XCTAssertEqual(chat.messages.filter { $0.clientMessageId == stableID && $0.text == delayed }.count, 1)
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
    func testRoomSessionRetainsPendingAcrossNavigation() {
        let store = FanStore()
        let first = store.chat(for: "studio-session")
        first.connect(base: URL(string: "http://127.0.0.1:1")!, token: "test-token")
        first.send("Waiting")
        let id = first.pending[0].id
        first.suspend()
        XCTAssertTrue(first.pending[0].uncertain)
        XCTAssertTrue(first === store.chat(for: "studio-session"))
        XCTAssertEqual(store.chat(for: "studio-session").pending.first?.id, id)
        XCTAssertTrue(store.chat(for: "other-room").pending.isEmpty)
    }
    func testLostAcknowledgementWhenConfigured() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let address = env["FANSTAGE_TEST_ACK_PROXY"], let token = env["FANSTAGE_TEST_TOKEN"], let url = URL(string: address) else { throw XCTSkip("ACK loss proxy not configured") }
        let chat = ChatSession(room: "ios-ack-loss")
        defer { chat.stop() }
        chat.connect(base: url, token: token)
        for _ in 0..<100 where chat.status != "Connected" { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(chat.status, "Connected")
        let value = UUID().uuidString
        chat.send(value)
        let id = try XCTUnwrap(chat.pending.first?.id)
        for _ in 0..<150 where chat.pending.first?.uncertain != true { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertEqual(chat.pending.first?.id, id)
        XCTAssertEqual(chat.pending.first?.uncertain, true)
        chat.retry(id)
        for _ in 0..<100 where !chat.pending.isEmpty { try await Task.sleep(nanoseconds: 100_000_000) }
        XCTAssertTrue(chat.pending.isEmpty)
        XCTAssertEqual(chat.messages.filter { $0.clientMessageId == id && $0.text == value }.count, 1)
        let directAddress = try XCTUnwrap(env["FANSTAGE_TEST_URL"])
        let historyURL = try XCTUnwrap(URL(string: directAddress + "/rooms/ios-ack-loss/messages?afterSequence=0&upperSequence=1000&limit=1000"))
        var request = URLRequest(url: historyURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        let rows = try JSONDecoder().decode([ServerMessage].self, from: data)
        XCTAssertEqual(rows.filter { $0.clientMessageId == id }.count, 1)
    }
    func testUnboundSessionDoesNotEnqueueMessage() {
        let chat = ChatSession(room: "studio-session")
        chat.send("draft")
        XCTAssertTrue(chat.pending.isEmpty, "Unbound messages cannot be safely assigned to an account")
    }
    func testCancelledGenerationRejectsOldAckAndSubscription() throws {
        let chat = ChatSession(room: "studio-session")
        chat.connect(base: URL(string: "http://127.0.0.1:1")!, token: "test-token")
        XCTAssertTrue(chat.send("pending"))
        let id = try XCTUnwrap(chat.pending.first?.id)
        let old = chat.generation
        chat.suspend()
        let decoder = JSONDecoder()
        let subscribed = try decoder.decode(Envelope.self, from: Data("{\"type\":\"subscribed\",\"headSequence\":0}".utf8))
        XCTAssertFalse(chat.process(subscribed, generation: old))
        XCTAssertEqual(chat.status, "Disconnected")
        let message = ServerMessage(roomId: "studio-session", messageId: "server", clientMessageId: id, serverSequence: 1, text: "pending", isOwn: true, sentAt: "")
        let payload = try JSONSerialization.data(withJSONObject: ["type": "ack", "message": JSONSerialization.jsonObject(with: JSONEncoder().encode(message))])
        let ack = try decoder.decode(Envelope.self, from: payload)
        XCTAssertFalse(chat.process(ack, generation: old))
        XCTAssertEqual(chat.pending.first?.id, id)
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertTrue(chat.process(ack, generation: chat.generation))
        XCTAssertTrue(chat.pending.isEmpty)
    }
    func testRetryPolicyResetsOnSubscriptionAndStopsAtLimit() {
        var policy = ChatReconnectPolicy()
        XCTAssertEqual(policy.failed(), 1)
        XCTAssertEqual(policy.failed(), 2)
        policy.subscribed()
        XCTAssertEqual(policy.failed(), 1)
        for _ in 0..<4 { XCTAssertNotNil(policy.failed()) }
        XCTAssertNil(policy.failed())
        XCTAssertEqual(policy.failures, policy.maximumFailures)
    }
    func testBoundPendingCannotSwitchAccountOrBeClearedByStop() throws {
        let chat = ChatSession(room: "studio-session")
        chat.connect(base: URL(string: "http://127.0.0.1:1")!, token: "first")
        XCTAssertTrue(chat.send("pending"))
        let id = try XCTUnwrap(chat.pending.first?.id)
        chat.connect(base: URL(string: "http://127.0.0.1:2")!, token: "second")
        XCTAssertEqual(chat.pending.first?.id, id)
        chat.stop()
        XCTAssertTrue(chat.hasServerSession)
        XCTAssertEqual(chat.pending.first?.id, id)
    }
    func testDelayedReceiveAfterSuspendIsIgnored() async throws {
        let chat = ChatSession(room: "studio-session")
        chat.connect(base: URL(string: "http://127.0.0.1:1")!, token: "first")
        XCTAssertTrue(chat.send("pending"))
        let id = try XCTUnwrap(chat.pending.first?.id)
        let message = ServerMessage(roomId: "studio-session", messageId: "server", clientMessageId: id, serverSequence: 1, text: "pending", isOwn: true, sentAt: "")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(message))
        let data = try JSONSerialization.data(withJSONObject: ["type": "ack", "message": object])
        let packet = try JSONDecoder().decode(Envelope.self, from: data)
        let old = chat.generation
        var continuation: CheckedContinuation<Envelope, Never>?
        let task = Task { try await chat.receiveCurrent(generation: old) { await withCheckedContinuation { continuation = $0 } } }
        while continuation == nil { await Task.yield() }
        chat.suspend()
        continuation?.resume(returning: packet)
        let result = try await task.value
        XCTAssertNil(result)
        XCTAssertEqual(chat.pending.first?.id, id)
        XCTAssertTrue(chat.messages.isEmpty)
    }
    func testDelayedSendCompletionAfterSuspendDoesNotStartDeadline() async throws {
        let chat = ChatSession(room: "studio-session")
        chat.connect(base: URL(string: "http://127.0.0.1:1")!, token: "first")
        XCTAssertTrue(chat.send("pending"))
        let item = try XCTUnwrap(chat.pending.first)
        let old = chat.generation
        var continuation: CheckedContinuation<Void, Never>?
        let task = Task { try await chat.completeSend(item, generation: old, valid: { true }) { await withCheckedContinuation { continuation = $0 } } }
        while continuation == nil { await Task.yield() }
        chat.suspend()
        continuation?.resume()
        let completed = try await task.value
        XCTAssertFalse(completed)
        XCTAssertEqual(chat.deadlineCount, 0)
        XCTAssertEqual(chat.pending.first?.id, item.id)
    }
    func testPendingDiscardRequiresConfirmation() throws {
        let chat = ChatSession(room: "studio-session")
        chat.connect(base: URL(string: "http://127.0.0.1:1")!, token: "first")
        XCTAssertTrue(chat.send("pending"))
        let id = try XCTUnwrap(chat.pending.first?.id)
        chat.discard(id, confirmed: false)
        XCTAssertEqual(chat.pending.first?.id, id)
        chat.discard(id, confirmed: true)
        XCTAssertTrue(chat.pending.isEmpty)
    }
    func testDelayedSubscriptionAfterSuspendIsIgnored() async throws {
        let chat = ChatSession(room: "studio-session")
        chat.connect(base: URL(string: "http://127.0.0.1:1")!, token: "first")
        let packet = try JSONDecoder().decode(Envelope.self, from: Data("{\"type\":\"subscribed\",\"headSequence\":0}".utf8))
        let old = chat.generation
        var continuation: CheckedContinuation<Envelope, Never>?
        let task = Task { try await chat.receiveCurrent(generation: old) { await withCheckedContinuation { continuation = $0 } } }
        while continuation == nil { await Task.yield() }
        chat.suspend()
        continuation?.resume(returning: packet)
        let result = try await task.value
        XCTAssertNil(result)
        XCTAssertEqual(chat.status, "Disconnected")
    }
    func testSuspendedReconnectDoesNotChangeStatus() async throws {
        let chat = ChatSession(room: "studio-session")
        chat.connect(base: URL(string: "http://127.0.0.1:1")!, token: "first")
        try await Task.sleep(nanoseconds: 200_000_000)
        chat.suspend()
        let generation = chat.generation
        try await Task.sleep(nanoseconds: 1_300_000_000)
        XCTAssertEqual(chat.generation, generation)
        XCTAssertEqual(chat.status, "Disconnected")
    }
    private func fixtureURL() throws -> URL {
        guard let value = ProcessInfo.processInfo.environment["FANSTAGE_PHASE1B_FIXTURE"], let url = URL(string: value) else { throw XCTSkip("Loopback socket fixture not configured") }
        return url
    }
    private func fixtureCount(_ key: String, at base: URL) async throws -> Int {
        let (data, _) = try await URLSession.shared.data(from: base.appendingPathComponent("stats"))
        return (try JSONDecoder().decode([String: Int].self, from: data))[key] ?? 0
    }
    private func waitForCount(_ key: String, _ count: Int, at base: URL) async throws {
        for _ in 0..<200 {
            if try await fixtureCount(key, at: base) >= count { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
        XCTFail("Fixture did not observe expected socket count for \(key)")
    }
    func testRealSocketRetryLimitAndResetWhenConfigured() async throws {
        let base = try fixtureURL()
        let fast: (Int) async throws -> Void = { _ in try await Task.sleep(nanoseconds: 20_000_000) }
        let limit = ChatSession(room: "limit", retrySleep: fast)
        limit.connect(base: base, token: "fixture")
        try await waitForCount("limit", 6, at: base)
        for _ in 0..<100 where limit.status != "Disconnected" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(limit.status, "Disconnected")
        let limitCount = try await fixtureCount("limit", at: base)
        XCTAssertEqual(limitCount, 6)
        limit.stop()
        let reset = ChatSession(room: "reset", retrySleep: fast)
        reset.connect(base: base, token: "fixture")
        try await waitForCount("reset", 6, at: base)
        for _ in 0..<100 where reset.status != "Connected" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(reset.status, "Connected")
        _ = try await URLSession.shared.data(from: base.appendingPathComponent("release/reset"))
        try await waitForCount("reset", 11, at: base)
        for _ in 0..<100 where reset.status != "Connected" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(reset.status, "Connected")
        let resetCount = try await fixtureCount("reset", at: base)
        XCTAssertEqual(resetCount, 11)
        reset.stop()
    }
    func testRealSocketSuspendStopsRetryWhenConfigured() async throws {
        let base = try fixtureURL()
        let chat = ChatSession(room: "cancel", retrySleep: { _ in try await Task.sleep(nanoseconds: 2_000_000_000) })
        chat.connect(base: base, token: "fixture")
        try await waitForCount("cancel", 1, at: base)
        chat.suspend()
        try await Task.sleep(nanoseconds: 2_200_000_000)
        let count = try await fixtureCount("cancel", at: base)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(chat.status, "Disconnected")
        chat.stop()
    }
    func testDelayedRealSocketDoesNotCorruptNewSessionWhenConfigured() async throws {
        let base = try fixtureURL()
        let chat = ChatSession(room: "delayed")
        chat.connect(base: base, token: "fixture")
        try await waitForCount("delayed_held", 1, at: base)
        let old = chat.generation
        chat.suspend()
        chat.reconnect()
        try await waitForCount("delayed", 2, at: base)
        for _ in 0..<100 where chat.status != "Connected" { try await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertEqual(chat.status, "Connected")
        let current = chat.generation
        XCTAssertNotEqual(old, current)
        _ = try await URLSession.shared.data(from: base.appendingPathComponent("release/delayed"))
        try await waitForCount("delayed_release_attempted", 1, at: base)
        XCTAssertEqual(chat.generation, current)
        XCTAssertEqual(chat.status, "Connected")
        XCTAssertTrue(chat.messages.isEmpty)
        XCTAssertTrue(chat.pending.isEmpty)
        XCTAssertEqual(chat.deadlineCount, 0)
        chat.stop()
    }
}
