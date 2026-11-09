import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack { DiscoverView() }.tabItem { Label("Discover", systemImage: "sparkles") }
            NavigationStack { CommunityView() }.tabItem { Label("Community", systemImage: "heart") }
            NavigationStack { MediaView() }.tabItem { Label("Media", systemImage: "play.rectangle") }
            NavigationStack { MessagesView() }.tabItem { Label("Messages", systemImage: "bubble.left.and.bubble.right") }
        }
    }
}
struct Artwork: View {
    let artist: Artist
    var variant: String = "hero"
    var body: some View { Image("\(artist.image)_\(variant)").resizable().scaledToFill().clipped() }
}
struct DiscoverView: View {
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text("Find your moment").font(.largeTitle.bold())
            Text("Meet your favorite artists, live and together.").foregroundStyle(.secondary)
            Text("Communities").font(.headline)
            ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(Artist.all) { artist in NavigationLink { CommunityView(artist: artist) } label: { VStack { Artwork(artist: artist, variant: "cover").frame(width: 68, height: 68).clipShape(Circle()); Text(artist.name).font(.caption) }.foregroundStyle(.primary) } } } }
            HStack { Text("LIVE NOW").font(.headline); Spacer(); Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(.red) }
            ForEach(Artist.all) { artist in
                NavigationLink { LiveView(artist: artist) } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        Artwork(artist: artist).frame(height: 185).clipShape(RoundedRectangle(cornerRadius: 18))
                        HStack { Text("LIVE").font(.caption.bold()).foregroundStyle(.red); Text(artist.name).foregroundStyle(.secondary) }
                        Text(artist.roomTitle).font(.headline).foregroundStyle(.primary)
                    }
                }.buttonStyle(.plain)
            }
            NavigationLink("Watch a replay") { ReplayView(title: "Replay") }.font(.headline)
        }.padding(20) }.background(Color.canvas).navigationTitle("FanStage")
    }
}
struct CommunityView: View {
    @EnvironmentObject var store: FanStore
    var artist: Artist? = nil
    var body: some View {
        ScrollView { LazyVStack(spacing: 18) {
            if artist == nil { ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach(Artist.all) { item in NavigationLink(item.name) { CommunityView(artist: item) }.buttonStyle(.bordered) } } } }
            ForEach(store.posts.filter { artist == nil || $0.artist.id == artist?.id }) { post in
                NavigationLink { PostView(id: post.id) } label: { PostCard(post: post) }.buttonStyle(.plain)
            }
        }.padding(20) }.background(Color.canvas).navigationTitle(artist?.name ?? "Community")
    }
}
struct PostCard: View {
    let post: Post
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(post.artist.name).font(.headline)
            Artwork(artist: post.artist, variant: "feed_01").frame(height: 250).clipShape(RoundedRectangle(cornerRadius: 14))
            Text("A little moment from our world.")
            Label("\(post.comments.count)", systemImage: post.liked ? "heart.fill" : "heart").foregroundStyle(Color.plum)
        }.padding().background(.white, in: RoundedRectangle(cornerRadius: 20))
    }
}
struct PostView: View {
    @EnvironmentObject var store: FanStore
    let id: String
    @State private var text = ""
    var body: some View {
        if let post = store.posts.first(where: { $0.id == id }) {
            ScrollView { VStack(alignment: .leading, spacing: 16) {
                PostCard(post: post)
                Button { store.toggleLike(id) } label: { Label(post.liked ? "Liked" : "Like", systemImage: post.liked ? "heart.fill" : "heart") }
                NavigationLink("See artist") { CommunityView(artist: post.artist) }
                Text("Comments").font(.headline)
                ForEach(Array(post.comments.enumerated()), id: \.offset) { _, comment in Text(comment) }
                HStack { TextField("Add a comment", text: $text); Button("Send") { store.comment(id, text: text); text = "" } }
            }.padding() }.navigationTitle("Post")
        }
    }
}
struct MediaView: View {
    @State private var filter = 0
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text("Videos & moments").font(.largeTitle.bold())
            Picker("Filter", selection: $filter) { Text("All").tag(0); Text("LIVE").tag(1); Text("Replay").tag(2) }.pickerStyle(.segmented)
            if filter != 1 { NavigationLink { ReplayView(title: "Replay") } label: { Label("Watch replay", systemImage: "play.circle.fill").font(.title2.bold()) } }
            if filter != 2 { ForEach(Artist.all) { artist in NavigationLink { LiveView(artist: artist) } label: {
                HStack { Artwork(artist: artist, variant: "cover").frame(width: 90, height: 90).clipShape(RoundedRectangle(cornerRadius: 12)); VStack(alignment: .leading) { Text(artist.roomTitle).font(.headline); Text(artist.name).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "play.circle") }.foregroundStyle(.primary)
            } } }
        }.padding(20) }.background(Color.canvas).navigationTitle("Media")
    }
}
struct MessagesView: View {
    @EnvironmentObject var store: FanStore
    var body: some View { List(Artist.all) { artist in NavigationLink { ConversationView(artist: artist) } label: {
        HStack { Artwork(artist: artist, variant: "cover").frame(width: 56, height: 56).clipShape(Circle()); VStack(alignment: .leading) { Text(artist.name).font(.headline); Text(store.conversations[artist.id]?.last?.text ?? "Welcome to our space!").foregroundStyle(.secondary) } }
    } }.navigationTitle("Messages") }
}
struct ConversationView: View {
    @EnvironmentObject var store: FanStore
    let artist: Artist
    @State private var text = ""
    var body: some View {
        ScrollView { LazyVStack(alignment: .leading, spacing: 12) { ForEach(store.conversations[artist.id] ?? []) { message in
            HStack { if message.isOwn { Spacer() }; Text(message.text).padding(12).background(message.isOwn ? Color.plum.opacity(0.18) : Color.gray.opacity(0.12), in: RoundedRectangle(cornerRadius: 16)); if !message.isOwn { Spacer() } }
        } }.padding() }.safeAreaInset(edge: .bottom) { HStack { TextField("Message", text: $text); Button("Send") { store.send(artist, text: text); text = "" } }.padding().background(.bar) }.navigationTitle(artist.name).navigationBarTitleDisplayMode(.inline)
    }
}
