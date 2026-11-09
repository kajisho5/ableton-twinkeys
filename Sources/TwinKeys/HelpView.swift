#if os(macOS)
import SwiftUI

/// Sheet shown from "How to Fix…" when no other TwinKeys can be found.
struct HelpView: View {
    let onClose: () -> Void
    let actions: ViewActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Finding the other Mac").font(.system(size: 15, weight: .semibold))
            step(1, "Open TwinKeys on both Macs.")
            step(2, "Connect both Macs to the same network. A wired network or a dedicated router is the most reliable.")
            step(3, "On each Mac, open System Settings > Privacy & Security > Local Network and turn on TwinKeys. (macOS 15 or later asks for this the first time.)")
            step(4, "If the macOS firewall asks whether TwinKeys may accept incoming connections, click Allow.")
            step(5, "Turn off VPN software and “Limit IP address tracking” for this network if the Macs still cannot see each other.")
            HStack {
                Button("Open Local Network Settings…", action: actions.openLocalNetworkSettings)
                    .buttonStyle(TKButtonStyle(kind: .primary))
                Spacer()
                Button("Done", action: onClose)
                    .buttonStyle(TKButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.windowBackground)
        .foregroundStyle(Theme.textPrimary)
    }

    private func step(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n).").font(.system(size: Theme.body, weight: .semibold)).frame(width: 18, alignment: .trailing)
            Text(text).font(.system(size: Theme.body)).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
