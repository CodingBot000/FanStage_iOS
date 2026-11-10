import Foundation
@testable import FanStage

@MainActor final class FakeChatTransport: ChatTransport {
    final class Connection: ChatConnection {
        var waiting: CheckedContinuation<Envelope, Error>?
        var queued: [Envelope] = []
        var failure: Error?
        var sent: [(String, String)] = []
        var closed = false
        var holdSend = false
        var sendWaiting: CheckedContinuation<Void, Error>?
        func receive() async throws -> Envelope {
            if let failure { self.failure = nil; throw failure }
            if !queued.isEmpty { return queued.removeFirst() }
            return try await withCheckedThrowingContinuation { waiting = $0 }
        }
        func deliver(_ event: Envelope) {
            if let waiting { self.waiting = nil; waiting.resume(returning: event) }
            else { queued.append(event) }
        }
        func failReceive(_ error: Error) {
            if let waiting { self.waiting = nil; waiting.resume(throwing: error) }
            else { failure = error }
        }
        func send(clientMessageId: String, text: String) async throws {
            sent.append((clientMessageId, text))
            if holdSend { try await withCheckedThrowingContinuation { sendWaiting = $0 } }
        }
        func completeSend() { let waiting = sendWaiting; sendWaiting = nil; waiting?.resume() }
        func close() { closed = true }
    }
    var connections: [Connection] = []
    var fetchWaiting: CheckedContinuation<[ServerMessage], Error>?
    var fetchedRanges: [(Int, Int)] = []
    func open(base: URL, token: String, room: String) throws -> any ChatConnection {
        let connection = Connection(); connections.append(connection); return connection
    }
    func fetch(base: URL, token: String, room: String, after: Int, upper: Int, limit: Int) async throws -> [ServerMessage] {
        fetchedRanges.append((after, upper))
        return try await withCheckedThrowingContinuation { fetchWaiting = $0 }
    }
    func completeFetch(_ rows: [ServerMessage]) { let waiting = fetchWaiting; fetchWaiting = nil; waiting?.resume(returning: rows) }
}
