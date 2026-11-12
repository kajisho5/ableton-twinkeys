import SwiftUI
import TwinKeysCore

@main
struct TwinKeysRemoteApp: App {
    /// `-demo` shows fictional sample data (for screenshots and checks without a Mac).
    @StateObject private var model = RemoteModel(demo: ProcessInfo.processInfo.arguments.contains("-demo"))
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onAppear {
                    model.startBrowsing()
                    WatchLink.shared.start(model)    // 2.3 Apple Watch (WatchLink.swift)
                    // `-landscape` turns the window sideways (screenshots on CI; the simulator starts upright).
                    if ProcessInfo.processInfo.arguments.contains("-landscape") {
                        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
                        }
                    }
                }
                .onChange(of: scenePhase) { p in if p == .active { model.appBecameActive() } }
        }
    }
}

/// Texts in English and Japanese (follows the iPhone's language).
enum L {
    static let ja = Locale.preferredLanguages.first?.hasPrefix("ja") ?? false
    static func s(_ en: String, _ jp: String) -> String { ja ? jp : en }
}

extension Color {
    init(hex: String) {
        var v: UInt64 = 0x888888
        let h = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if h.count == 6 { Scanner(string: h).scanHexInt64(&v) }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
    // 1.3 (A1 green LED): the old names point at the A1 palette in iOS/Shared/Theme.swift.
    static let tkAccent = TK.accent
    static let tkOK = TK.accent
    static let tkWarn = TK.yellow
    static let tkDanger = TK.red
    static let tkCell = TK.panel
    static let tkCard = TK.panel
    static let tkBar = TK.top
    static let tkBG = TK.bg

    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

/// Picks the layout from the space available (never from the device model or orientation name),
/// as Apple asks for iPhone Duo and resizable windows.
enum LayoutClass {
    case narrowPortrait, narrowLandscape, medium, wide
    static func of(_ size: CGSize) -> LayoutClass {
        if size.width >= 1000 { return .wide }
        if size.width >= 600 && size.height >= 500 { return .medium }
        if size.width > size.height { return .narrowLandscape }
        return .narrowPortrait
    }
}

struct RootView: View {
    @EnvironmentObject var model: RemoteModel

    var body: some View {
        Group {
            switch model.phase {
            case .connected: MainView()
            // Lost the link during a show: keep the main screen (with the switch-to-backup banner).
            case .failed(let why) where model.wasConnected && why != "code": MainView()
            // (Waiting for approval shows the pairing screen: it has the 4-digit code.)
            case .connecting, .searching:
                if model.wasConnected { MainView() } else { PairView() }
            default: PairView()
            }
        }
        .background(Color.tkBG.ignoresSafeArea())
        // 1.3: always the dark A1 look, also with the iPhone in Light Mode. The app is used on dark
        // stages, and the A1 colours (green LEDs, red All Notes Off) are made for a black screen; a light
        // version would need a second palette that was not designed. Sheets and Settings follow too.
        .preferredColorScheme(.dark)
        .tint(TK.accent)
    }
}
