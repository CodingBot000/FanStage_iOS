import SwiftUI
import AVKit

struct ReplayView: View {
    let title: String
    var body: some View { PlaybackView(title: title, artist: nil) }
}
struct LiveView: View {
    let artist: Artist
    var body: some View { PlaybackView(title: artist.roomTitle, artist: artist) }
}
struct PlaybackView: View {
    let title: String
    let artist: Artist?
    @Environment(\.scenePhase) private var scenePhase
    @State private var player: AVPlayer?
    @State private var chat: [Message] = [Message(text: "Welcome to the live chat!", isOwn: false)]
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let player { VideoPlayer(player: player).frame(height: 230).background(.black) }
            else { Color.black.frame(height: 230).overlay { ProgressView().tint(.white) } }
            Text(title).font(.title2.bold()).padding(.horizontal)
            if let artist {
                Text("\(artist.name) · Demo chat").foregroundStyle(.secondary).padding(.horizontal)
                ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(chat) { message in
                    HStack(alignment: .top) { Text(message.isOwn ? "You" : artist.name).bold(); Text(message.text); Spacer() }
                } }.padding() }
                HStack { TextField("Message", text: $text); Button("Send") { let value = text.trimmingCharacters(in: .whitespacesAndNewlines); if !value.isEmpty { chat.append(Message(text: value, isOwn: true)); text = "" } } }.padding().background(.bar)
            } else { Spacer() }
        }.navigationTitle(artist == nil ? "Replay" : "LIVE").navigationBarTitleDisplayMode(.inline)
            .onAppear { if player == nil, let url = Bundle.main.url(forResource: "demo", withExtension: "mp4") { player = AVPlayer(url: url); player?.play() } }
            .onDisappear { player?.pause(); player = nil }
            .onChange(of: scenePhase) { phase in if phase != .active { player?.pause() } }
    }
}
