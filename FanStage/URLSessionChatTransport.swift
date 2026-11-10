import Foundation

@MainActor final class URLSessionChatTransport: ChatTransport {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func open(base: URL, token: String, room: String) throws -> any ChatConnection {
        guard var components = URLComponents(url: base.appendingPathComponent("ws/rooms/\(room)"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: request)
        task.resume()
        return URLSessionChatConnection(task: task)
    }

    func fetch(base: URL, token: String, room: String, after: Int, upper: Int, limit: Int) async throws -> [ServerMessage] {
        guard var components = URLComponents(url: base.appendingPathComponent("rooms/\(room)/messages"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        components.queryItems = [URLQueryItem(name: "afterSequence", value: String(after)), URLQueryItem(name: "upperSequence", value: String(upper)), URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return try JSONDecoder().decode([ServerMessage].self, from: data)
    }
}

@MainActor private final class URLSessionChatConnection: ChatConnection {
    private let task: URLSessionWebSocketTask
    init(task: URLSessionWebSocketTask) { self.task = task }
    func receive() async throws -> Envelope {
        let frame = try await task.receive()
        let data: Data
        switch frame {
        case .string(let value): data = Data(value.utf8)
        case .data(let value): data = value
        @unknown default: throw URLError(.cannotDecodeContentData)
        }
        guard data.count <= 8192 else { throw URLError(.cannotDecodeContentData) }
        return try JSONDecoder().decode(Envelope.self, from: data)
    }
    func send(clientMessageId: String, text: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["type": "send", "clientMessageId": clientMessageId, "text": text])
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }
    func close() { task.cancel(with: .goingAway, reason: nil) }
}
