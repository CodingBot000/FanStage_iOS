import SwiftUI

struct Artist: Identifiable, Hashable {
    let id: String
    let name: String
    let image: String
    let roomID: String
    let roomTitle: String
    static let all: [Artist] = [
        .init(id: "paper-lantern", name: "Paper Lantern", image: "paper_lantern", roomID: "studio-session", roomTitle: "Studio session"),
        .init(id: "blue-pencil", name: "Blue Pencil", image: "blue_pencil", roomID: "sketch-break", roomTitle: "Afternoon sketch break"),
        .init(id: "dice-garden", name: "Dice Garden", image: "dice_garden", roomID: "tabletop-night", roomTitle: "Tabletop night")
    ]
}
struct Post: Identifiable {
    let id: String
    let artist: Artist
    var liked = false
    var comments: [String] = []
}
struct Message: Identifiable {
    let id = UUID()
    let text: String
    let isOwn: Bool
}
@MainActor final class FanStore: ObservableObject {
    @Published var posts = Artist.all.map { Post(id: "post-\($0.id)", artist: $0) }
    @Published var conversations = Dictionary(uniqueKeysWithValues: Artist.all.map { ($0.id, [Message(text: "Welcome to our space!", isOwn: false)]) })
    func toggleLike(_ id: String) { if let i = posts.firstIndex(where: { $0.id == id }) { posts[i].liked.toggle() } }
    func comment(_ id: String, text: String) { let t = text.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty, let i = posts.firstIndex(where: { $0.id == id }) { posts[i].comments.append(t) } }
    func send(_ artist: Artist, text: String) { let t = text.trimmingCharacters(in: .whitespacesAndNewlines); if !t.isEmpty { conversations[artist.id, default: []].append(Message(text: t, isOwn: true)) } }
}
