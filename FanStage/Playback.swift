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
@MainActor final class PlaybackSession: ObservableObject {
    let player = AVPlayer()
    @Published var error: String?
    @Published var subtitles: [AVMediaSelectionOption] = []
    @Published var subtitleGroup: AVMediaSelectionGroup?
    @Published var selectedSubtitle = -1
    @Published var speed: Float = 1
    private var observation: NSKeyValueObservation?
    private var item: AVPlayerItem?
    private var currentURL: URL?
    private var loadTask: Task<Void, Never>?
    func load(_ url: URL) {
        loadTask?.cancel(); observation?.invalidate(); player.pause(); error = nil; subtitles = []; subtitleGroup = nil; selectedSubtitle = -1
        currentURL = url
        let asset = AVURLAsset(url: url); let next = AVPlayerItem(asset: asset); item = next
        observation = next.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let description = item.error?.localizedDescription
            Task { @MainActor in if item.status == .failed { self?.error = description ?? "Playback failed" } }
        }
        player.replaceCurrentItem(with: next); player.playImmediately(atRate: speed)
        loadTask = Task {
            do {
                let group = try await asset.loadMediaSelectionGroup(for: .legible)
                guard !Task.isCancelled, self.item === next else { return }
                subtitleGroup = group; subtitles = group?.options ?? []
            } catch { if !Task.isCancelled { subtitles = [] } }
        }
    }
    func retry() { if let currentURL { load(currentURL) } }
    func setSpeed(_ value: Float) { speed = value; if player.rate != 0 { player.rate = value } }
    func selectSubtitle(_ index: Int) {
        guard let item, let group = subtitleGroup else { return }
        guard index == -1 || subtitles.indices.contains(index) else { return }
        item.select(index == -1 ? nil : subtitles[index], in: group); selectedSubtitle = index
    }
    func setBitrate(_ value: Double) { item?.preferredPeakBitRate = value }
    func stop() { loadTask?.cancel(); observation?.invalidate(); observation = nil; player.pause(); player.replaceCurrentItem(with: nil); item = nil }
}
struct PlaybackView: View {
    let title: String
    let artist: Artist?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = PlaybackSession()
    @StateObject private var chat: ChatSession
    @State private var confirmExit = false
    init(title: String, artist: Artist?) {
        self.title = title; self.artist = artist
        _chat = StateObject(wrappedValue: ChatSession(room: artist?.roomID ?? "replay"))
    }
    @State private var expanded = false
    @State private var showSettings = false
    #if DEBUG
    @State private var source = ""
    #endif
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VideoPlayer(player: session.player).frame(height: 230).background(.black)
                .overlay(alignment: .topTrailing) { Button { expanded = true } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").padding(10).background(.ultraThinMaterial, in: Circle()) }.padding(8).accessibilityLabel("Full screen") }
            HStack { Text(title).font(.title2.bold()); Spacer(); Button { showSettings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Playback settings") }.padding(.horizontal)
            if let error = session.error { HStack { Text(error); Button("Retry") { session.retry() } }.padding(.horizontal) }
            #if DEBUG
            DisclosureGroup("Video source") {
                HStack { TextField("HLS or MP4 URL", text: $source).textInputAutocapitalization(.never).autocorrectionDisabled(); Button("Load") { if let url = URL(string: source), ["http", "https"].contains(url.scheme?.lowercased() ?? "") { session.load(url) } } }
            }.padding(.horizontal)
            #endif
            if let artist { LiveChatView(artist: artist, session: chat) } else { Spacer() }
        }.navigationTitle(artist == nil ? "Replay" : "LIVE").navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true)
            .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button { if chat.pending.isEmpty { dismiss() } else { confirmExit = true } } label: { Label("Back", systemImage: "chevron.left") } } }
            .alert("Pending messages", isPresented: $confirmExit) { Button("Stay", role: .cancel) {} ; Button("Leave", role: .destructive) { dismiss() } } message: { Text("Pending messages will be lost if you leave this room.") }
            .sheet(isPresented: $showSettings) { settings.presentationDetents([.medium, .large]) }
            .fullScreenCover(isPresented: $expanded) { ZStack(alignment: .topTrailing) { Color.black.ignoresSafeArea(); VideoPlayer(player: session.player); Button("Done") { expanded = false }.padding().background(.ultraThinMaterial, in: Capsule()).padding() } }
            .onAppear { if session.player.currentItem == nil, let url = Bundle.main.url(forResource: "demo", withExtension: "mp4") { session.load(url) } }
            .onDisappear { if !expanded { session.stop(); chat.stop() } }
            .onChange(of: scenePhase) { phase in if phase != .active { session.player.pause() } }
    }
    private var settings: some View {
        NavigationStack { Form {
            Picker("Speed", selection: Binding(get: { session.speed }, set: { session.setSpeed($0) })) {
                Text("0.5×").tag(Float(0.5)); Text("1×").tag(Float(1)); Text("1.5×").tag(Float(1.5)); Text("2×").tag(Float(2))
            }
            if !session.subtitles.isEmpty { Picker("Subtitles", selection: Binding(get: { session.selectedSubtitle }, set: { session.selectSubtitle($0) })) {
                Text("Off").tag(-1)
                ForEach(session.subtitles.indices, id: \.self) { index in Text(session.subtitles[index].displayName).tag(index) }
            } }
            Section("Maximum bitrate") {
                Button("Automatic") { session.setBitrate(0) }
                Button("Up to 1 Mbps") { session.setBitrate(1_000_000) }
                Button("Up to 3 Mbps") { session.setBitrate(3_000_000) }
                Text("Availability depends on the stream.").font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Playback settings").toolbar { Button("Done") { showSettings = false } } }
    }
}
