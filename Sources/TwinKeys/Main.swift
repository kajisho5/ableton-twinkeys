#if os(macOS)
import AppKit
import SwiftUI

@main
enum Main {
    static func main() {
        let args = CommandLine.arguments
        // `TwinKeys --snapshot <dir>` renders the UI to PNG files (used by CI for screenshots).
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            MainActor.assumeIsolated {
                Snapshot.render(to: URL(fileURLWithPath: args[i + 1]))
            }
            exit(0)
        }
        // `TwinKeys --check-update-signature <app> <teamID>`: prints "accepted" or "rejected" for the
        // updater's signature check (used by the release workflow to test it on a notarized build).
        if let i = args.firstIndex(of: "--check-update-signature"), i + 2 < args.count {
            let ok = Updater.verify(URL(fileURLWithPath: args[i + 1]), team: args[i + 2])
            print(ok ? "accepted" : "rejected")
            print("team of this app: \(Updater.teamID(ofCodeAt: Bundle.main.bundleURL) ?? "none")")
            exit(ok ? 0 : 1)
        }
        TwinKeysApp.main()
    }
}
#endif
