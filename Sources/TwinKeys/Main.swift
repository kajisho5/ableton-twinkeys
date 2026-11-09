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
        TwinKeysApp.main()
    }
}
#endif
