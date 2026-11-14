#if os(macOS)
import SwiftUI
import TwinKeysCore

/// Settings > QLab (docs/design-qlab.md 4.1, docs/design/qlab-mac-settings.png): what TwinKeys
/// drives, this Mac's QLab, the cue keys' QLab actions, keeping the two Macs together, and the
/// two QLabs side by side.
struct QLabSettingsSection: View {
    let state: ViewState
    var actions = QLabSettingsActions()
    @State private var passcode = ""
    @State private var editingPasscode = false
    private var t: Strings { state.t }
    private var st: ViewState { state }
    private var model: QLabSettingsActions { actions }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(t.qlabTargetTitle).font(.system(size: Theme.body, weight: .semibold))
                HStack(spacing: 8) {
                    ForEach(QLabTarget.allCases, id: \.self) { target in
                        Button(t.qlabTargetName(target)) { model.setTarget(target) }
                            .buttonStyle(TKButtonStyle(kind: st.target == target ? .primary : .normal))
                            .accessibilityAddTraits(st.target == target ? .isSelected : [])
                    }
                }
                Text(t.qlabTargetHelp).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            VStack(alignment: .leading, spacing: 2) {
                Text(t.qlabSection)
                Text(t.qlabSubtitle).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        if st.target.drivesQLab {
            thisMac
            keys
            sync
            twoMacs
        }
    }

    // MARK: This Mac's QLab

    private var stateColor: Color {
        switch st.qlab.state {
        case .ready: return Theme.ok
        case .viewOnly, .stale, .noAnswer, .noWorkspace, .choosingWorkspace, .authorizing: return Theme.warning
        case .off: return Theme.idleDot
        default: return Theme.dangerText
        }
    }

    private var thisMac: some View {
        Section(t.qlabThisMac) {
            HStack(spacing: 8) {
                StatusDot(color: stateColor)
                Text(t.qlabState(st.qlab, port: st.qlabSettings.port)).font(.system(size: Theme.body, weight: .semibold))
                    .foregroundStyle(st.qlab.state == .ready ? Theme.ok : Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !st.qlab.workspaces.isEmpty {
                Picker(t.qlabWorkspace, selection: Binding(
                    get: { st.qlab.workspace?.uniqueID ?? st.qlabSettings.workspaceID ?? "" },
                    set: { id in if let w = st.qlab.workspaces.first(where: { $0.uniqueID == id }) { model.chooseQLabWorkspace(w) } })) {
                    if st.qlab.workspace == nil { Text(t.qlabChooseWorkspace).tag("") }
                    ForEach(st.qlab.workspaces, id: \.uniqueID) { w in Text(w.displayName).tag(w.uniqueID) }
                }
            }
            HStack(spacing: 8) {
                Text(t.qlabPasscode)
                if editingPasscode || !st.qlabPasscodeSet {
                    SecureField("0000", text: $passcode)
                        .frame(width: 80)
                        .onSubmit(save)
                    Button(t.qlabPasscodeSave, action: save).buttonStyle(TKButtonStyle(kind: .primary))
                } else {
                    Text("●●●●").font(.system(size: Theme.body, design: .monospaced))
                    Button(t.qlabPasscodeChange) { editingPasscode = true; passcode = "" }.buttonStyle(TKButtonStyle())
                }
                Spacer()
                Text(t.qlabPermissions).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                perm(t.qlabPermView, st.qlab.permissions.contains(.view))
                perm(t.qlabPermControl, st.qlab.permissions.contains(.control))
                perm(t.qlabPermEdit, false)
            }
            Text(t.qlabPasscodeNote).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func save() {
        model.setQLabPasscode(passcode)
        passcode = ""
        editingPasscode = false
    }

    private func perm(_ name: String, _ on: Bool) -> some View {
        HStack(spacing: 4) {
            StatusDot(color: on ? Theme.ok : Theme.idleDot, size: 7)
            Text(name).font(.system(size: Theme.caption)).foregroundStyle(on ? Theme.textPrimary : Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Cue key → QLab action

    private static let choices: [QLabAction?] = [.go, .playheadNext, .playheadPrevious, .panic, .hardStop, .goCue, .setPlayhead, nil]

    private var keys: some View {
        Section(t.qlabKeysTitle) {
            HStack(spacing: 12) {
                Text(t.qlabKeyColumn).frame(width: 70, alignment: .leading)
                Text(t.qlabActionColumn).frame(width: 220, alignment: .leading)
                Text(t.qlabDescColumn).frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: Theme.caption, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            .accessibilityHidden(true)
            ForEach(st.cueKeys) { k in keyRow(k) }
        }
    }

    private func keyRow(_ k: CueKey) -> some View {
        let a = k.qlabAction
        return HStack(spacing: 12) {
            Text(k.label).font(.system(size: Theme.body, weight: .semibold)).lineLimit(1)
                .padding(.horizontal, 6).frame(width: 70, alignment: .center).frame(minHeight: 24)
                .background(RoundedRectangle(cornerRadius: 5).fill(Theme.windowBackground))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.buttonBorder, lineWidth: 1))
            HStack(spacing: 6) {
                Picker("", selection: Binding(get: { a?.action }, set: { new in
                    model.setCueQLab(QLabKeyAction(new, cue: new?.needsCue == true ? (a?.cue ?? "") : nil), k.keycode)
                })) {
                    ForEach(Array(Self.choices.enumerated()), id: \.offset) { _, c in Text(t.qlabActionName(c)).tag(c) }
                }
                .labelsHidden()
                .frame(width: a?.action?.needsCue == true ? 140 : 220)
                if a?.action?.needsCue == true {
                    CueNumberField(initial: a?.cue ?? "", placeholder: t.qlabCueNumberPlaceholder) { n in
                        model.setCueQLab(QLabKeyAction(a?.action, cue: n), k.keycode)
                    }
                    .frame(width: 72)
                }
            }
            .frame(width: 220, alignment: .leading)
            Text(t.qlabActionDesc(a)).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(k.label)
    }

    // MARK: Keeping the two Macs together

    private var sync: some View {
        Section(t.qlabSyncTitle) {
            toggle(t.qlabFollow, t.qlabFollowHelp, \.followPlayhead)
            toggle(t.qlabRefuseStale, t.qlabRefuseStaleHelp, \.refuseStaleGo)
            toggle(t.qlabNotes, t.qlabNotesHelp, \.notesInQLabMode, warn: true)
                .disabled(st.target != .qlab)
            Text(t.qlabNumbersNote).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggle(_ title: String, _ help: String, _ key: WritableKeyPath<QLabSettings, Bool>, warn: Bool = false) -> some View {
        Toggle(isOn: Binding(get: { st.qlabSettings[keyPath: key] }, set: { v in
            var q = st.qlabSettings; q[keyPath: key] = v; model.setQLabSettings(q)
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(help).font(.system(size: Theme.caption)).foregroundStyle(warn ? Theme.warning : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.checkbox)
    }

    // MARK: The two QLabs

    @ViewBuilder private var twoMacs: some View {
        Section(t.qlabTwoMacs) {
            let me = st.deskMeName.isEmpty ? "Mac" : st.deskMeName
            let other: String = { if case let .connected(n, _) = st.link { return n }; return "—" }()
            let p = st.peerQLab
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                GridRow {
                    Text("")
                    Text(me).font(.system(size: Theme.body, weight: .semibold))
                    Text(other).font(.system(size: Theme.body, weight: .semibold))
                }
                row(t.qlabRowQLab, mine: st.qlab.state.canView ? "\(st.qlab.version ?? "") \(t.qlabConnectedShort)" : t.qlabNotConnectedShort,
                    good: st.qlab.state.canView,
                    theirs: p.map { $0.state.canView ? t.qlabConnectedShort : t.qlabNotConnectedShort }, theirsGood: p?.state.canView)
                row(t.qlabRowWorkspace, mine: st.qlab.workspace?.displayName ?? "—", theirs: p == nil ? nil : "—")
                row(t.qlabRowPermissions, mine: perms(st.qlab.permissions), good: st.qlab.permissions.contains(.control),
                    theirs: p.map { perms($0.permissions) }, theirsGood: p?.permissions.contains(.control))
                row(t.qlabRowCues, mine: "\(st.qlab.cues.count)",
                    theirs: p.map { "\($0.cueCount)" + (st.qlabBackup?.sameCues == true ? " " + t.qlabSame : "") }, theirsGood: st.qlabBackup?.sameCues)
                row(t.qlabRowPlayhead, mine: st.qlab.playheadCue?.title ?? "—",
                    theirs: p.map { ($0.playhead ?? "—") + (st.qlabBackup?.samePlayhead == true ? " " + t.qlabSame : "") },
                    theirsGood: st.qlabBackup?.samePlayhead)
                row(t.qlabRowRunning, mine: "\(st.qlab.running.count)", theirs: p.map { "\($0.running)" })
                row(t.qlabRowShowMode, mine: st.qlab.showMode ? t.qlabOn : t.qlabOffWord, good: st.qlab.showMode,
                    theirs: p.map { $0.showMode ? t.qlabOn : t.qlabOffWord }, theirsGood: p?.showMode)
            }
            .font(.system(size: Theme.body))
            ForEach(warnings, id: \.self) { w in
                Label(w, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: Theme.caption, weight: .semibold)).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var warnings: [String] {
        var w: [String] = []
        let other: String = { if case let .connected(n, _) = st.link { return n }; return "" }()
        if st.peerUnderstandsQLab == false { w.append(t.qlabPeerOld) }
        if let p = st.peerQLab {
            if p.state == .off { w.append(t.qlabPeerNotQLab) }
            if p.target != st.target || p.keysHash != st.qlabKeysHash { w.append(t.qlabTargetsDiffer) }
            if p.state.canView, !p.showMode { w.append(t.qlabNotShowMode(other)) }
        }
        if st.qlab.state.canView, !st.qlab.showMode { w.append(t.qlabNotShowMode(st.deskMeName.isEmpty ? "Mac" : st.deskMeName)) }
        if let d = st.qlabDiff { w.append(t.qlabCuesDiffer(d.mainCount, d.backupCount)) }
        return w
    }

    private func perms(_ p: QLabPermissions) -> String {
        [p.contains(.view) ? t.qlabPermView : nil, p.contains(.control) ? t.qlabPermControl : nil].compactMap { $0 }.joined(separator: "・")
    }

    private func row(_ name: String, mine: String, good: Bool? = nil, theirs: String?, theirsGood: Bool? = nil) -> some View {
        GridRow {
            Text(name).foregroundStyle(Theme.textSecondary)
            Text(mine).foregroundStyle(good == true ? Theme.ok : good == false ? Theme.warning : Theme.textPrimary).lineLimit(1)
            Text(theirs ?? "—").foregroundStyle(theirsGood == true ? Theme.ok : theirsGood == false ? Theme.warning : Theme.textPrimary).lineLimit(1)
        }
    }
}

/// What the QLab settings can change (AppModel; no-ops for the screenshots).
struct QLabSettingsActions {
    var setTarget: (QLabTarget) -> Void = { _ in }
    var setQLabSettings: (QLabSettings) -> Void = { _ in }
    var chooseQLabWorkspace: (QLabWorkspaceInfo) -> Void = { _ in }
    var setQLabPasscode: (String) -> Void = { _ in }
    var setCueQLab: (QLabKeyAction, UInt16) -> Void = { _, _ in }
}

/// A cue number typed for "GO cue number" (saved when Return is pressed or the field is left).
private struct CueNumberField: View {
    let initial: String
    let placeholder: String
    let commit: (String) -> Void
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .focused($focused)
            .onAppear { text = initial }
            .onSubmit { commit(text) }
            .onChange(of: focused) { if !$0, text != initial { commit(text) } }
    }
}

/// Main window: this Mac's QLab and the last QLab command (docs/design-qlab.md 4.1, "直前のキュー").
struct QLabPanel: View {
    let state: ViewState
    private var t: Strings { state.t }

    var body: some View {
        TKGroup(border: state.qlabLast?.backup == "missing" ? Theme.dangerText : Theme.separator) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    StatusDot(color: state.qlab.state == .ready ? Theme.ok : state.qlab.state.canView ? Theme.warning : Theme.dangerText)
                    Text(t.qlabState(state.qlab, port: state.qlabSettings.port))
                        .font(.system(size: Theme.body, weight: .semibold)).lineLimit(2)
                    Spacer(minLength: 4)
                    if let b = state.qlabBackup, b.supported, b.state.canView {
                        Text(t.qlabBackupLinkOK).font(.system(size: Theme.caption, weight: .semibold)).foregroundStyle(Theme.ok)
                    }
                }
                if let ph = state.qlab.playheadCue {
                    Text("NEXT ▸ \(ph.title)").font(.system(size: Theme.body, weight: .bold, design: .monospaced)).lineLimit(1)
                }
                if let l = state.qlabLast {
                    HStack(spacing: 8) {
                        Text(t.qlabLastLine(l)).font(.system(size: Theme.value, weight: .bold)).lineLimit(1)
                        Text(t.qlabMainResult(l.main) + "  ·  " + t.qlabBackupResult(l.backup))
                            .font(.system(size: Theme.caption, weight: .semibold))
                            .foregroundStyle(["missing", "noSuchCue", "notConnected", "noAnswer", "denied", "badPasscode"].contains(l.backup)
                                             ? Theme.dangerText : l.backup == "corrected" ? Theme.warning : Theme.textSecondary)
                            .lineLimit(2)
                    }
                }
                if let d = state.qlabDiff {
                    Text(t.qlabCuesDiffer(d.mainCount, d.backupCount)).font(.system(size: Theme.caption, weight: .semibold))
                        .foregroundStyle(Theme.warning)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
