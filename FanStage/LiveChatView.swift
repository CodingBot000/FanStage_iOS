import SwiftUI

struct LiveChatView: View {
    let artist: Artist
    @ObservedObject var session: ChatSession
    @State private var demo: [Message] = [Message(text: "Welcome to the live chat!", isOwn: false)]
    @State private var text = ""
    @State private var pendingToDiscard: String?
    @State private var confirmDiscard = false
    @FocusState private var inputFocused: Bool
    #if DEBUG
    @State private var endpoint = ProcessInfo.processInfo.environment["FANSTAGE_UI_TEST_URL"] ?? "http://127.0.0.1:18765"
    @State private var token = ProcessInfo.processInfo.environment["FANSTAGE_UI_TEST_TOKEN"] ?? ""
    #endif
    init(artist: Artist, session: ChatSession) {
        self.artist = artist; self.session = session
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            #if DEBUG
            DisclosureGroup("Chat settings") {
                if session.pending.isEmpty {
                    Toggle("Local server", isOn: $session.serverMode).onChange(of: session.serverMode) { enabled in if !enabled { session.stop() } }
                }
                if session.serverMode {
                    TextField("Server URL", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    SecureField("Test token", text: $token).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Connect") { if let url = URL(string: endpoint), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), !token.isEmpty { session.connect(base: url, token: token) } }.disabled(!session.pending.isEmpty)
                    Text(LocalizedStringKey(session.status)).font(.caption)
                    if session.status == "Disconnected" && !session.pending.isEmpty { Button("Reconnect") { session.reconnect() } }
                }
            }.padding(.horizontal)
            #endif
            ScrollView { LazyVStack(alignment: .leading, spacing: 12) {
                #if DEBUG
                if session.serverMode {
                    ForEach(session.messages) { row in HStack { Text(row.isOwn ? "You" : artist.name).bold(); Text(row.text); Spacer() } }
                    ForEach(session.pending) { item in
                        HStack { Text(item.text); Text(LocalizedStringKey(item.failed ? "Failed" : item.uncertain ? "Unconfirmed" : "Pending")).foregroundStyle(.secondary); Spacer()
                            Button("Retry") { session.retry(item.id) }
                            Button("Delete") { pendingToDiscard = item.id; confirmDiscard = true }
                        }.accessibilityIdentifier("pending_\(item.id)")
                    }
                    if session.gapUnresolved { Button("Messages missing · Retry") { session.recover() } }
                } else { demoRows }
                #else
                demoRows
                #endif
            }.padding() }
            HStack {
                TextField("Message", text: $text).focused($inputFocused)
                Button("Send") {
                    let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, value.unicodeScalars.count <= 1000 else { return }
                    #if DEBUG
                    if session.serverMode { guard session.send(value) else { return } } else { demo.append(Message(text: value, isOwn: true)) }
                    #else
                    demo.append(Message(text: value, isOwn: true))
                    #endif
                    text = ""; inputFocused = false
                }
                .accessibilityIdentifier("live_chat_send")
                #if DEBUG
                .disabled(session.serverMode && !session.canSend)
                #endif
            }.padding().background(.bar)
        }.onAppear { if session.hasServerSession { session.reconnect() } }
        .alert("Discard pending message?", isPresented: $confirmDiscard) {
            Button("Cancel", role: .cancel) { pendingToDiscard = nil }
            Button("Discard", role: .destructive) { if let id = pendingToDiscard { session.discard(id, confirmed: true) }; pendingToDiscard = nil }
        } message: { Text("This message may have been delivered. Discarding it removes the local retry state.") }
    }
    private var demoRows: some View {
        ForEach(demo) { message in HStack(alignment: .top) { Text(message.isOwn ? "You" : artist.name).bold(); Text(message.text); Spacer() } }
    }
}
