import SwiftUI
import TwinKeysCore

@main
struct TwinKeysRemoteApp: App {
    /// `-demo` shows fictional sample data (for screenshots and checks without a Mac).
    @StateObject private var model = RemoteModel(demo: ProcessInfo.processInfo.arguments.contains("-demo"))

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .onAppear {
                    model.startBrowsing()
                    // `-landscape` turns the window sideways (screenshots on CI; the simulator starts upright).
                    if ProcessInfo.processInfo.arguments.contains("-landscape") {
                        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                            scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
                        }
                    }
                }
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
    static let tkAccent = Color(light: 0x0060C7, dark: 0x5AA9FF)
    static let tkOK = Color(light: 0x1B7A31, dark: 0x4FD06A)
    static let tkWarn = Color(light: 0x8A5A00, dark: 0xF2B13A)
    static let tkDanger = Color(red: 0xC0 / 255, green: 0x24 / 255, blue: 0x1A / 255)
    static let tkCell = Color(light: 0xE9E9EE, dark: 0x2C2C2E)
    static let tkCard = Color(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let tkBar = Color(light: 0xF9F9FB, dark: 0x121214)
    static let tkBG = Color(light: 0xF2F2F7, dark: 0x000000)

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
            default: PairView()
            }
        }
        .background(Color.tkBG.ignoresSafeArea())
    }
}
