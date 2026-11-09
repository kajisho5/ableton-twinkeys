#if os(macOS)
import AppKit
import SwiftUI

/// "TwinKeys Help" window. Reads docs/help/<lang>.md bundled in the app, so it works
/// without an internet connection (common at venues).
struct HelpWindowView: View {
    let language: AppLanguage

    private var t: Strings { Strings(language) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if let text = HelpContent.load(t.lang) {
                    ForEach(Array(HelpContent.blocks(text).enumerated()), id: \.offset) { _, block in
                        block.view
                    }
                } else {
                    Text(t.helpMissing).foregroundStyle(Theme.textSecondary)
                }
                Divider().padding(.vertical, 8)
                Button(t.helpOnGitHub) { NSWorkspace.shared.open(HelpContent.onlineURL(t.lang)) }
                    .buttonStyle(TKButtonStyle())
            }
            .padding(24)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 420, minHeight: 360)
        .background(Theme.windowBackground)
        .foregroundStyle(Theme.textPrimary)
    }
}

enum HelpContent {
    static func load(_ lang: AppLanguage) -> String? {
        let name = lang == .ja ? "ja" : "en"
        guard let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "help") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    static func onlineURL(_ lang: AppLanguage) -> URL {
        URL(string: "https://github.com/kajisho5/ableton-twinkeys/blob/main/docs/help/\(lang == .ja ? "ja" : "en").md")!
    }

    /// A deliberately small Markdown subset: #, ##, list items, **bold line**, paragraphs.
    enum Block {
        case title(String), heading(String), subheading(String), bullet(String), numbered(String, String), paragraph(String)

        @ViewBuilder var view: some View {
            switch self {
            case let .title(s):
                Text(inline(s)).font(.system(size: 22, weight: .bold)).padding(.bottom, 4)
                    .accessibilityAddTraits(.isHeader)
            case let .heading(s):
                Text(inline(s)).font(.system(size: 16, weight: .semibold)).padding(.top, 14)
                    .accessibilityAddTraits(.isHeader)
            case let .subheading(s):
                Text(inline(s)).font(.system(size: Theme.body, weight: .semibold)).padding(.top, 6)
            case let .bullet(s):
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("•").foregroundStyle(Theme.textSecondary)
                    Text(inline(s)).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 4)
            case let .numbered(n, s):
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(n).monospacedDigit().frame(minWidth: 18, alignment: .trailing)
                    Text(inline(s)).fixedSize(horizontal: false, vertical: true)
                }
            case let .paragraph(s):
                Text(inline(s)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    static func blocks(_ text: String) -> [Block] {
        var out: [Block] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("## ") { out.append(.heading(String(line.dropFirst(3)))) }
            else if line.hasPrefix("# ") { out.append(.title(String(line.dropFirst(2)))) }
            else if line.hasPrefix("- ") { out.append(.bullet(String(line.dropFirst(2)))) }
            else if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4 {
                out.append(.subheading(String(line.dropFirst(2).dropLast(2))))
            } else if let dot = line.firstIndex(of: "."), line[..<dot].allSatisfy(\.isNumber), !line[..<dot].isEmpty,
                      line[line.index(after: dot)...].hasPrefix(" ") {
                out.append(.numbered(String(line[...dot]), String(line[line.index(dot, offsetBy: 2)...])))
            } else { out.append(.paragraph(line)) }
        }
        return out
    }
}

private func inline(_ s: String) -> AttributedString {
    (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
}

/// Menu item that opens the help window (needs the openWindow environment value).
struct HelpMenuItem: View {
    let title: String
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button(title) { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}
#endif
