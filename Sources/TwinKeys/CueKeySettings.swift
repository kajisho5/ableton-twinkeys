#if os(macOS)
import AppKit
import SwiftUI
import TwinKeysCore

/// Settings > Cue Keys (docs/design/cuekeys-settings-*.svg).
struct CueKeySettings: View {
    @ObservedObject var model: AppModel
    @State private var adding = false
    private var t: Strings { model.state.t }

    var body: some View {
        Section(t.cueKeysSection) {
            if !model.state.cueKeys.isEmpty {
                HStack(spacing: 12) {
                    Text(t.cueKeyColumn).frame(width: 84, alignment: .leading)
                    Text(t.cueMemoColumn).frame(maxWidth: .infinity, alignment: .leading)
                    Text(t.cueMidiColumn).frame(width: 84, alignment: .leading)
                    Color.clear.frame(width: 24)
                }
                .font(.system(size: Theme.caption, weight: .semibold)).foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
                ForEach(model.state.cueKeys) { k in row(k) }
            }
            HStack(spacing: 12) {
                Button(t.addCueKey) { adding = true }
                    .buttonStyle(TKButtonStyle(kind: .primary))
                    .disabled(CueKey.freeNote(in: model.state.cueKeys) == nil)
                Button(t.addLettersAndDigits) { model.addCueKeys(CueKey.alphanumericKeyCodes) }
                    .buttonStyle(TKButtonStyle())
                    .disabled(CueKey.freeNote(in: model.state.cueKeys) == nil
                              || CueKey.alphanumericKeyCodes.allSatisfy { c in model.state.cueKeys.contains { $0.keycode == c } })
            }
            Text(CueKey.freeNote(in: model.state.cueKeys) == nil ? t.cueKeysFull : t.addCueKeyHint)
                .font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $adding) { AddCueKeySheet(model: model, onClose: { adding = false }) }
        Section {
            Toggle(isOn: Binding(get: { model.state.blockCueKeys }, set: { model.setBlockCueKeys($0) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.blockCueKeys)
                    Text(t.blockCueKeysHelp).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .toggleStyle(.checkbox)
            if model.state.blockCueKeys && model.state.accessibility != .granted {
                Button(t.openAccessibilitySettings) { model.actions.openAccessibilitySettings() }
                    .buttonStyle(TKButtonStyle())
            }
        }
    }

    private func row(_ k: CueKey) -> some View {
        HStack(spacing: 12) {
            Text(k.label)
                .font(.system(size: Theme.body, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 8).frame(minWidth: 34, minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.buttonBackground))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.buttonBorder, lineWidth: 1))
                .frame(width: 84, alignment: .leading)
            MemoField(text: k.memo, placeholder: t.memoPlaceholder) { model.setCueMemo($0, for: k.keycode) }
                .accessibilityLabel(t.memoFor(k.label))
            Text("ch 2 · \(noteName(k.note))")
                .font(.system(size: 12, design: .monospaced)).foregroundStyle(Theme.textSecondary)
                .frame(width: 84, alignment: .leading)
            Button { model.removeCueKey(k.keycode) } label: { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .frame(width: 24)
                .help(t.removeCueKey(k.label))
                .accessibilityLabel(t.removeCueKey(k.label))
        }
    }
}

/// A text field that saves when editing ends (not on every keystroke).
private struct MemoField: View {
    let text: String
    let placeholder: String
    let onCommit: (String) -> Void
    @State private var value = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $value)
            .textFieldStyle(.roundedBorder)
            .focused($focused)
            .onAppear { value = text }
            .onChange(of: text) { if !focused { value = $0 } }
            .onChange(of: focused) { if !$0 { onCommit(value) } }
            .onSubmit { onCommit(value) }
    }
}

/// "Press the key to add" (docs/design/cuekeys-add-*.svg). While it is open, TwinKeys' own
/// key handling is paused so the key reaches this sheet and plays nothing.
struct AddCueKeySheet: View {
    @ObservedObject var model: AppModel
    let onClose: () -> Void
    @State private var monitor: Any?
    @State private var message: String?
    @State private var added: [String] = []
    private var t: Strings { model.state.t }

    var body: some View {
        VStack(spacing: 14) {
            Text(t.pressKeyToAdd).font(.system(size: 15, weight: .bold))
            Image(systemName: "keyboard")
                .font(.system(size: 26))
                .frame(width: 140, height: 44)
                .background(RoundedRectangle(cornerRadius: 8).fill(Theme.groupBackground))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.accent, lineWidth: 1.5))
                .accessibilityHidden(true)
            Text(message ?? t.pressKeyHint)
                .font(.system(size: Theme.caption))
                .foregroundStyle(message == nil ? Theme.textSecondary : Theme.warning)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if !added.isEmpty {
                Text(t.addedKeys(added.joined(separator: "  ")))
                    .font(.system(size: Theme.body, weight: .semibold))
                    .foregroundStyle(Theme.ok)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button(t.done, action: close).buttonStyle(TKButtonStyle(kind: .primary))
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear(perform: begin)
        .onDisappear(perform: end)
    }

    private func begin() {
        model.setRecordingCueKey(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
            // Every key (Esc too) is a candidate; Cancel is clicked with the mouse.
            guard mods.isEmpty else { return nil }
            let code = event.keyCode
            if let existing = model.state.cueKeys.first(where: { $0.keycode == code }) {
                message = t.keyAlreadyUsed(existing.label)
                return nil
            }
            if KeyNames.isModifier(code) { return nil }
            guard CueKey.freeNote(in: model.state.cueKeys) != nil else { message = t.cueKeysFull; return nil }
            model.addCueKey(code)
            // Stay open: several keys can be added one after another.
            message = nil
            added.append(KeyNames.label(for: code))
            return nil
        }
    }

    private func end() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        model.setRecordingCueKey(false)
    }

    private func close() { end(); onClose() }
}
#endif
