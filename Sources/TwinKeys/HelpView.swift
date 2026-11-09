#if os(macOS)
import SwiftUI

/// Sheet shown from "How to Fix…" when no other TwinKeys can be found.
struct HelpView: View {
    let t: Strings
    let onClose: () -> Void
    let actions: ViewActions

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(t.helpTitle).font(.system(size: 15, weight: .semibold))
            ForEach(Array(t.helpSteps.enumerated()), id: \.offset) { i, text in
                step(i + 1, text)
            }
            HStack {
                Button(t.openLocalNetworkSettings, action: actions.openLocalNetworkSettings)
                    .buttonStyle(TKButtonStyle())
                Spacer()
                // The blue button is the one Return presses; Esc also closes the sheet.
                Button(t.done, action: onClose)
                    .buttonStyle(TKButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 4)
        }
        .padding(20)
        .onExitCommand(perform: onClose)   // Esc closes the sheet
        .frame(width: 440)
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
