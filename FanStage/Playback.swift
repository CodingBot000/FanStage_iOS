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
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let player { VideoPlayer(player: player).frame(height: 230).background(.black) }
            else { Color.black.frame(height: 230).overlay { ProgressView().tint(.white) } }
            Text(title).font(.title2.bold()).padding(.horizontal)
            if let artist {
                LiveChatView(artist: artist)
            } else { Spacer() }
        }.navigationTitle(artist == nil ? "Replay" : "LIVE").navigationBarTitleDisplayMode(.inline)
            .onAppear { if player == nil, let url = Bundle.main.url(forResource: "demo", withExtension: "mp4") { player = AVPlayer(url: url); player?.play() } }
            .onDisappear { player?.pause(); player = nil }
            .onChange(of: scenePhase) { phase in if phase != .active { player?.pause() } }
    }
}
