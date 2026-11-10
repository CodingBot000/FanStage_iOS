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
struct Envelope: Decodable {
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
    var uncertain = false
}

struct ChatReconnectPolicy {
    private(set) var failures = 0
    let maximumFailures = 6
    mutating func subscribed() { failures = 0 }
    mutating func failed() -> Int? {
        failures += 1
        guard failures < maximumFailures else { return nil }
        return min(30, 1 << (failures - 1))
    }
}

@MainActor final class ChatSession: ObservableObject {
    @Published private(set) var messages: [ServerMessage] = []
    @Published private(set) var pending: [PendingChat] = []
    @Published var serverMode = false
    @Published private(set) var status = "Disconnected"
    @Published private(set) var gapUnresolved = false
    private let room: String
    private var base: URL?
    private var token = ""
    private var socket: URLSessionWebSocketTask?
    private var worker: Task<Void, Never>?
    private var recovery: Task<Void, Never>?
    private var epoch = 0
    private var timeline: ChatTimeline
    private var deadlines: [String: Task<Void, Never>] = [:]
    var hasServerSession: Bool { base != nil && !token.isEmpty }
    var canSend: Bool { hasServerSession }
    var generation: Int { epoch }
    private let session: URLSession
    private let retrySleep: (Int) async throws -> Void

    init(room: String, session: URLSession = .shared, retrySleep: @escaping (Int) async throws -> Void = { delay in try await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000) }) {
        self.room = room; self.timeline = ChatTimeline(room: room); self.session = session; self.retrySleep = retrySleep
    }
    func connect(base: URL, token: String) {
        guard pending.isEmpty else { return }
        stop(); timeline = ChatTimeline(room: room); messages.removeAll(); gapUnresolved = false
        self.base = base; self.token = token
        let generation = epoch
        status = "Connecting"
        worker = Task { await run(generation) }
    }
    func stop() {
        if !pending.isEmpty { suspend(); return }
        epoch += 1; worker?.cancel(); recovery?.cancel(); socket?.cancel(with: .goingAway, reason: nil)
        worker = nil; recovery = nil; socket = nil; deadlines.values.forEach { $0.cancel() }; deadlines.removeAll(); token = ""; base = nil; status = "Disconnected"
    }
    func suspend() {
        epoch += 1; worker?.cancel(); recovery?.cancel(); socket?.cancel(with: .goingAway, reason: nil)
        worker = nil; recovery = nil; socket = nil; deadlines.values.forEach { $0.cancel() }; deadlines.removeAll()
        for index in pending.indices where !pending[index].failed { pending[index].uncertain = true }
        status = "Disconnected"
    }
    private func run(_ generation: Int) async {
        var policy = ChatReconnectPolicy()
        while !Task.isCancelled && generation == epoch {
            do {
                status = policy.failures == 0 ? "Connecting" : "Reconnecting"
                guard let base, var components = URLComponents(url: base.appendingPathComponent("ws/rooms/\(room)"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
                components.scheme = components.scheme == "https" ? "wss" : "ws"
                guard let url = components.url else { throw URLError(.badURL) }
                var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let ws = session.webSocketTask(with: request); socket = ws; ws.resume()
                while !Task.isCancelled && generation == epoch {
                    guard let packet = try await receiveCurrent(generation: generation, receive: {
                        let frame = try await ws.receive()
                        let data: Data
                        switch frame { case .string(let value): data = Data(value.utf8); case .data(let value): data = value; @unknown default: throw URLError(.cannotDecodeContentData) }
                        guard data.count <= 8192 else { throw URLError(.cannotDecodeContentData) }
                        return try JSONDecoder().decode(Envelope.self, from: data)
                    }), socket === ws else { return }
                    if packet.type == "subscribed" {
                        policy.subscribed()
                        for item in pending where !item.failed {
                            let completed = try await completeSend(item, generation: generation, valid: { self.socket === ws }) {
                                try await self.transmit(item, socket: ws)
                            }
                            guard completed else { return }
                        }
                    }
                }
            } catch {
                guard !Task.isCancelled && generation == epoch else { return }
                socket?.cancel(with: .goingAway, reason: nil); socket = nil
                guard let delay = policy.failed() else { break }
                status = "Reconnecting"
                do { try await retrySleep(delay) } catch { return }
            }
        }
        if generation == epoch { status = "Disconnected" }
    }
    func receiveCurrent(generation: Int, receive: () async throws -> Envelope) async throws -> Envelope? {
        let packet = try await receive()
        guard process(packet, generation: generation) else { return nil }
        return packet
    }
    @discardableResult func process(_ packet: Envelope, generation: Int) -> Bool {
        guard generation == epoch, !Task.isCancelled else { return false }
        if packet.type == "subscribed" {
            guard let head = packet.headSequence, head >= 0 else { return false }
            status = "Connected"; timeline.observeHead(head); scheduleRecovery(generation)
        } else if (packet.type == "ack" || packet.type == "message"), let message = packet.message {
            merge(message); scheduleRecovery(generation)
        } else if packet.type == "error", let id = packet.clientMessageId, let index = pending.firstIndex(where: { $0.id == id }), packet.code == "invalid" || packet.code == "conflict" {
            deadlines[id]?.cancel(); deadlines[id] = nil; pending[index].failed = true
        }
        return true
    }
    func reconnect() {
        guard status == "Disconnected", base != nil, !token.isEmpty else { return }
        let generation = epoch
        status = "Connecting"
        worker = Task { await run(generation) }
    }
    @discardableResult func send(_ text: String) -> Bool {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !clean.isEmpty, clean.unicodeScalars.count <= 1000, pending.count < 1000 else { return false }
        let item = PendingChat(id: UUID().uuidString.lowercased(), text: clean)
        pending.append(item)
        if let socket, status == "Connected" { sendPending(item, socket: socket) }
        return true
    }
    func retry(_ id: String) {
        guard let index = pending.firstIndex(where: { $0.id == id }), let socket, status == "Connected" else { return }
        pending[index].failed = false; pending[index].uncertain = false; let item = pending[index]
        sendPending(item, socket: socket)
    }
    func discard(_ id: String, confirmed: Bool) {
        guard confirmed else { return }
        deadlines[id]?.cancel(); deadlines[id] = nil
        pending.removeAll { $0.id == id }
    }
    private func sendPending(_ item: PendingChat, socket: URLSessionWebSocketTask) {
        let generation = epoch
        Task {
            do { _ = try await completeSend(item, generation: generation, valid: { self.socket === socket }) { try await self.transmit(item, socket: socket) } }
            catch { if !Task.isCancelled, generation == epoch, self.socket === socket { socket.cancel(with: .goingAway, reason: nil) } }
        }
    }
    var deadlineCount: Int { deadlines.count }
    func completeSend(_ item: PendingChat, generation: Int, valid: () -> Bool, operation: () async throws -> Void) async throws -> Bool {
        try await operation()
        guard !Task.isCancelled, generation == epoch, valid() else { return false }
        if pending.contains(where: { $0.id == item.id }) { startDeadline(item.id) }
        return true
    }
    private func startDeadline(_ id: String) {
        deadlines[id]?.cancel()
        deadlines[id] = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard !Task.isCancelled, let index = pending.firstIndex(where: { $0.id == id }) else { return }
            pending[index].uncertain = true; deadlines[id] = nil
        }
    }
    private func transmit(_ item: PendingChat, socket: URLSessionWebSocketTask) async throws {
        let data = try JSONSerialization.data(withJSONObject: ["type": "send", "clientMessageId": item.id, "text": item.text])
        try await socket.send(.string(String(decoding: data, as: UTF8.self)))
    }
    func merge(_ message: ServerMessage) {
        guard timeline.merge(message) else { return }
        if message.isOwn, let id = message.clientMessageId { deadlines[id]?.cancel(); deadlines[id] = nil; pending.removeAll { $0.id == id } }
        messages = timeline.messages
        gapUnresolved = timeline.hasGap
    }
    private func scheduleRecovery(_ generation: Int) {
        guard timeline.hasGap, recovery == nil else { return }
        recovery = Task {
            defer { if generation == epoch { recovery = nil } }
            do {
                while timeline.hasGap && !Task.isCancelled && generation == epoch {
                    let before = timeline.cursor
                    guard let base, var components = URLComponents(url: base.appendingPathComponent("rooms/\(room)/messages"), resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
                    components.queryItems = [URLQueryItem(name: "afterSequence", value: String(timeline.cursor)), URLQueryItem(name: "upperSequence", value: String(timeline.highest)), URLQueryItem(name: "limit", value: "200")]
                    guard let url = components.url else { throw URLError(.badURL) }
                    var request = URLRequest(url: url); request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    let (data, response) = try await session.data(for: request)
                    guard !Task.isCancelled, generation == epoch, (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                    let page = try JSONDecoder().decode([ServerMessage].self, from: data)
                    for row in page { merge(row) }
                    guard timeline.cursor > before else { throw URLError(.cannotDecodeContentData) }
                }
            } catch { if generation == epoch { gapUnresolved = true } }
        }
    }
    func recover() { scheduleRecovery(epoch) }
}
