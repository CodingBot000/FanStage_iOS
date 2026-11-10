import Foundation

@MainActor protocol ChatConnection: AnyObject {
    func receive() async throws -> Envelope
    func send(clientMessageId: String, text: String) async throws
    func close()
}

@MainActor protocol ChatTransport {
    func open(base: URL, token: String, room: String) throws -> any ChatConnection
    func fetch(base: URL, token: String, room: String, after: Int, upper: Int, limit: Int) async throws -> [ServerMessage]
}
