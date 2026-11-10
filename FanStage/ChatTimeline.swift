import Foundation

/// A room-scoped, network-independent view of server sequence continuity.
struct ChatTimeline {
    let room: String
    private(set) var cursor = 0
    private(set) var highest = 0
    private var rows: [Int: ServerMessage] = [:]

    init(room: String) { self.room = room }

    var hasGap: Bool { cursor < highest }
    var messages: [ServerMessage] {
        Array(rows.values.sorted { $0.serverSequence < $1.serverSequence }.suffix(500))
    }
    mutating func observeHead(_ head: Int) { highest = max(highest, head) }
    @discardableResult mutating func merge(_ message: ServerMessage) -> Bool {
        guard message.roomId == room, message.serverSequence > 0 else { return false }
        if message.serverSequence > cursor && message.serverSequence - cursor <= 1000 {
            rows[message.serverSequence] = message
        }
        highest = max(highest, message.serverSequence)
        while rows[cursor + 1] != nil { cursor += 1 }
        if rows.count > 1000 { rows = rows.filter { $0.key > cursor - 1000 } }
        return true
    }
}
