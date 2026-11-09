import SwiftUI

@main
struct FanStageApp: App {
    @StateObject private var store = FanStore()
    var body: some Scene {
        WindowGroup { RootView().environmentObject(store).tint(.plum) }
    }
}

extension Color {
    static let plum = Color(red: 0.396, green: 0.239, blue: 0.459)
    static let canvas = Color(red: 0.98, green: 0.973, blue: 0.988)
}
