import SwiftUI

/// TwinKeys Remote for Apple Watch (2.3): GO, choosing the next scene and All Notes Off.
/// It works through the iPhone app (WatchConnectivity); it never connects to the Macs.
@main
struct TwinKeysWatchApp: App {
    /// `-demo` shows fictional sample data (screenshots on CI); `-page go|scenes|panic` picks the first page.
    @StateObject private var model = WatchModel(demo: ProcessInfo.processInfo.arguments.contains("-demo"))
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(model)
                .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
        }
    }
}

/// Texts in English and Japanese (follows the language set for the watch), as on the iPhone.
enum L {
    static let ja = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
    static func s(_ en: String, _ jp: String) -> String { ja ? jp : en }
}

/// 1.3 (A1 green LED): the old names point at the A1 palette in iOS/Shared/Theme.swift (the watch is always dark).
extension Color {
    static let tkOK = TK.accent
    static let tkAccent = TK.blue
    static let tkWarn = TK.yellow
    static let tkDanger = TK.red
    static let tkCell = TK.panel
}
