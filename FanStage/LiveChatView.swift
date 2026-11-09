import SwiftUI

struct LiveChatView: View {
    let artist: Artist
    @StateObject private var session: ChatSession
    @State private var demo: [Message] = [Message(text: "Welcome to the live chat!", isOwn: false)]
    @State private var text = ""
    #if DEBUG
    @State private var serverMode = false
    @State private var endpoint = "http://127.0.0.1:18765"
    @State private var token = ""
    #endif
    init(artist: Artist) { self.artist = artist; _session = StateObject(wrappedValue: ChatSession(room: artist.roomID)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if DEBUG
            DisclosureGroup("Chat settings") {
                if session.pending.isEmpty {
                    Toggle("Local server", isOn: $serverMode).onChange(of: serverMode) { _ in session.stop() }
                }
                if serverMode {
                    TextField("Server URL", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Test token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Connect") { if let url = URL(string: endpoint), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !token.isEmpty { session.connect(base: url, token: token) } }
                    Text(session.status).font(.caption)
                }
            }.padding(.horizontal)
            #endif
            ScrollView { LazyVStack(alignment: .leading, spacing: 12) {
                #if DEBUG
                if serverMode {
                    ForEach(session.messages) { row in HStack { Text(row.isOwn ? "You" : artist.name).bold(); Text(row.text); Spacer() } }
                    ForEach(session.pending) { item in
                        HStack { Text(item.text); Text(item.failed ? "Failed" : "Pending").foregroundStyle(.secondary); Spacer()
                            Button("Retry") { session.retry(item.id) }
                            if item.failed { Button("Delete") { session.discard(item.id) } }
                        }
                    }
                    if session.gapUnresolved { Button("Messages missing · Retry") { session.recover() } }
                } else { demoRows }
                #else
                demoRows
                #endif
            }.padding() }
            HStack {
                TextField("Message", text: $text)
                Button("Send") {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, value.unicodeScalars.count <= 1000 else { return }
                    #if DEBUG
                    if serverMode { session.send(value) } else { demo.append(Message(text: value, isOwn: true)) }
                    #else
                    demo.append(Message(text: value, isOwn: true))
                    #endif
                    text = ""
                }
            }.padding().background(.bar)
        }.onDisappear { session.stop() }
    }
    private var demoRows: some View {
        ForEach(demo) { message in HStack(alignment: .top) { Text(message.isOwn ? "You" : artist.name).bold(); Text(message.text); Spacer() } }
    }
}
