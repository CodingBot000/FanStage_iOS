import Foundation

struct ServerMessage: Codable, Identifiable, Equatable {
    let roomId: String
    let messageId: String
    let clientMessageId: String?
    let serverSequence: Int
    let text: String
    let isOwn: Bool
    let sentAt: String
    var id: String { messageId }
}
private struct Envelope: Decodable {
    let type: String
    let headSequence: Int?
    let message: ServerMessage?
    let clientMessageId: String?
    let code: String?
}
struct PendingChat: Identifiable {
    let id: String
    let text: String
    var failed = false
}

@MainActor final class ChatSession: ObservableObject {
    @Published private(set) var messages: [ServerMessage] = []
    @Published private(set) var pending: [PendingChat] = []
    @Published private(set) var status = "Disconnected"
    @Published private(set) var gapUnresolved = false
    private let room: String
    private var base: URL?
    private var token = ""
    private var socket: URLSessionWebSocketTask?
    private var worker: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var epoch = 0
    private var cursor = 0
    private var highest = 0
    private var rows: [Int: ServerMessage] = [:]
    private let session: URLSession

    init(room: String, session: URLSession = .shared) { self.room = room; self.session = session }
    func connect(base: URL, token: String) {
        guard pending.isEmpty else { status = "Resolve pending messages first"; return }
        stop(); rows.removeAll(); messages.removeAll(); cursor = 0; highest = 0; gapUnresolved = false
        self.base = base; self.token = token
        let generation = epoch
        worker = Task { await run(generation) }
    }
    func stop() {
        epoch += 1; worker?.cancel(); recovery?.cancel(); socket?.cancel(with: .goingAway, reason: nil)
        worker = nil; recovery = nil; socket = nil; token = ""; status = "Disconnected"
    }
    private func run(_ generation: Int) async {
        var failures = 0
        while !Task.isCancelled && generation == epoch && failures < 6 {
            do {
                status = failures == 0 ? "Connecting" : "Reconnecting"
                guard let base, var components = URLComponents(url: base.appendingPathComponent("ws/rooms/\(room)"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
                components.scheme = components.scheme == "https" ? "wss" : "ws"
                guard let url = components.url else { throw URLError(.badURL) }
                var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let ws = session.webSocketTask(with: request); socket = ws; ws.resume()
                while !Task.isCancelled && generation == epoch {
                    let frame = try await ws.receive()
                    let data: Data
                    switch frame { case .string(let value): data = Data(value.utf8); case .data(let value): data = value; @unknown default: throw URLError(.cannotDecodeContentData) }
                    guard data.count <= 8192 else { throw URLError(.cannotDecodeContentData) }
                    let packet = try JSONDecoder().decode(Envelope.self, from: data)
                    if packet.type == "subscribed", let head = packet.headSequence, head >= 0 {
                        status = "Connected"; highest = max(highest, head); scheduleRecovery(generation)
                        for item in pending where !item.failed { try await transmit(item, socket: ws) }
                    } else if (packet.type == "ack" || packet.type == "message"), let message = packet.message {
                        merge(message); scheduleRecovery(generation)
                    } else if packet.type == "error", let id = packet.clientMessageId, let index = pending.firstIndex(where: { $0.id == id }), packet.code == "invalid" || packet.code == "conflict" {
                        pending[index].failed = true
                    }
                }
            } catch {
                guard !Task.isCancelled && generation == epoch else { return }
                socket?.cancel(with: .goingAway, reason: nil); socket = nil
                failures += 1; status = "Reconnecting"
                try? await Task.sleep(nanoseconds: UInt64(min(30, 1 << (failures - 1))) * 1_000_000_000)
            }
        }
        if generation == epoch { status = "Disconnected" }
    }
    func reconnect() {
        guard status == "Disconnected", base != nil, !token.isEmpty else { return }
        let generation = epoch
        worker = Task { await run(generation) }
    }
    func send(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.unicodeScalars.count <= 1000, pending.count < 200 else { return }
        let item = PendingChat(id: UUID().uuidString.lowercased(), text: clean)
        pending.append(item)
        if let socket, status == "Connected" { Task { try? await transmit(item, socket: socket) } }
    }
    func retry(_ id: String) {
        guard let index = pending.firstIndex(where: { $0.id == id }), let socket, status == "Connected" else { return }
        pending[index].failed = false; let item = pending[index]
        Task { try? await transmit(item, socket: socket) }
    }
    func discard(_ id: String) { if let item = pending.first(where: { $0.id == id }), item.failed { pending.removeAll { $0.id == id } } }
    private func transmit(_ item: PendingChat, socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["type": "send", "clientMessageId": item.id, "text": item.text])
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
    func merge(_ message: ServerMessage) {
        guard message.roomId == room, message.serverSequence > 0 else { return }
        if let id = message.clientMessageId { pending.removeAll { $0.id == id } }
        if message.serverSequence > cursor { rows[message.serverSequence] = message }
        highest = max(highest, message.serverSequence)
        while rows[cursor + 1] != nil { cursor += 1 }
        messages = Array(rows.values.sorted { $0.serverSequence < $1.serverSequence }.suffix(200))
        if rows.count > 400 { rows = rows.filter { $0.key > cursor - 200 } }
        gapUnresolved = cursor < highest
    }
    private func scheduleRecovery(_ generation: Int) {
        guard cursor < highest, recovery == nil else { return }
        recovery = Task {
            defer { recovery = nil }
            do {
                while cursor < highest && !Task.isCancelled && generation == epoch {
                    let before = cursor
                    guard let base, var components = URLComponents(url: base.appendingPathComponent("rooms/\(room)/messages"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
                    components.queryItems = [URLQueryItem(name: "afterSequence", value: String(cursor)), URLQueryItem(name: "upperSequence", value: String(highest)), URLQueryItem(name: "limit", value: "200")]
                    guard let url = components.url else { throw URLError(.badURL) }
                    var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (data, response) = try await session.data(for: request)
                    guard generation == epoch, (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    let page = try JSONDecoder().decode([ServerMessage].self, from: data)
                    for row in page { merge(row) }
                    guard cursor > before else { throw URLError(.cannotDecodeContentData) }
                }
            } catch { if generation == epoch { gapUnresolved = true } }
        }
    }
    func recover() { scheduleRecovery(epoch) }
}
