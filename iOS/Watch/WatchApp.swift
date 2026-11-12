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

/// The iPhone app's dark colors (the watch is always dark).
extension Color {
    static let tkOK = Color(red: 0x4F / 255, green: 0xD0 / 255, blue: 0x6A / 255)
    static let tkAccent = Color(red: 0x5A / 255, green: 0xA9 / 255, blue: 0xFF / 255)
    static let tkWarn = Color(red: 0xF2 / 255, green: 0xB1 / 255, blue: 0x3A / 255)
    static let tkDanger = Color(red: 0xC0 / 255, green: 0x24 / 255, blue: 0x1A / 255)
    static let tkCell = Color(red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
    /// Text on the green GO button.
    static let tkOnGreen = Color(red: 0.04, green: 0.14, blue: 0.06)
}
