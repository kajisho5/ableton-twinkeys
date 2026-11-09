#if !os(macOS)
// TwinKeys is a macOS app. This stub only lets the package build elsewhere
// so the platform-independent tests in TwinKeysCore can run.
@main
enum TwinKeysUnsupportedPlatform {
    static func main() { print("TwinKeys runs on macOS only.") }
}
#endif
