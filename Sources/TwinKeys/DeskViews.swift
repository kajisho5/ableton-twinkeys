#if os(macOS)
import SwiftUI
import TwinKeysCore

// 2.4 console takeover (experimental): docs/design-v2.4-ql.md, docs/design/mac-ql-dark.

/// The window's banner after a takeover or restore (or when the console could not be moved).
struct DeskBanner: View {
    let desk: DeskSnapshot
    let t: Strings
    let onRestore: () -> Void
    let onDismiss: () -> Void

    static func shows(_ d: DeskSnapshot) -> Bool { d.move != nil || d.refusal != nil || d.canRestore }

    private struct Line { var text: String; var warning: Bool }

    var body: some View {
        TKGroup(border: hasProblem ? Theme.warning : Theme.accent) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 12) { texts; Spacer(); button }
                VStack(alignment: .leading, spacing: 8) { texts; button }
            }
            .padding(12)
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(desk.refusal != nil ? Theme.warning : Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.text).font(.system(size: Theme.caption))
                    .foregroundStyle(line.warning ? Theme.warning : Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var button: some View {
        if desk.canRestore {
            Button(t.deskRestore, action: onRestore).buttonStyle(TKButtonStyle())
        } else if canHide {
            Button(t.deskHide, action: onDismiss).buttonStyle(TKButtonStyle())
        }
    }

    /// Not while the faders move or are being read back.
    private var canHide: Bool {
        guard let m = desk.move else { return true }
        return !m.running && m.check != DeskCheck.waiting
    }

    private var title: String {
        if let r = desk.refusal { return t.deskRefused(r) }
        guard let m = desk.move else { return t.deskSwitched(0) }
        switch m.kind {
        case .takeover: return m.running ? t.deskSwitching(m.fade) : t.deskSwitched(m.fade)
        case .restore: return m.running ? t.deskRestoring : t.deskRestored(m.fade)
        }
    }

    private var lines: [Line] {
        guard desk.refusal == nil, let m = desk.move else { return [] }
        var out: [Line] = []
        if m.kind == .takeover && !m.readLevels { out.append(Line(text: t.deskFixedUsed, warning: false)) }
        switch m.check {
        case .waiting: if !m.running { out.append(Line(text: t.deskCheckWaiting, warning: false)) }
        case .ok: out.append(Line(text: t.deskCheckOK, warning: false))
        case .notPossible: out.append(Line(text: t.deskCheckNotPossible, warning: false))
        case .interrupted: out.append(Line(text: t.deskCheckInterrupted, warning: true))
        case let .mismatches(list): out += list.map { Line(text: t.deskMismatch($0), warning: true) }
        }
        return out
    }

    private var hasProblem: Bool {
        if desk.refusal != nil { return true }
        guard let check = desk.move?.check else { return false }
        if case .interrupted = check { return true }
        if case .mismatches = check { return true }
        return false
    }
}

/// What Settings > Console (Yamaha) can ask the app to do.
struct DeskSettingsActions {
    var update: (DeskSettings) -> Void = { _ in }
    /// Asks first before switching to automatic.
    var setTrigger: (DeskTrigger) -> Void = { _ in }
    var check: () -> Void = {}
}

/// Settings > Console (Yamaha), laid out as docs/design/mac-ql-dark (left).
struct DeskSettingsSection: View {
    let state: ViewState
    let actions: DeskSettingsActions
    private var t: Strings { state.t }
    private var d: DeskSettings { state.deskSettings }

    var body: some View {
        Section(t.deskSection) {
            Group {
                Text(t.deskSubtitle).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                modelAndAddress
                statusLine
                DeskChannelTable(state: state, actions: actions)
                unreadableBox
                triggerChoice
                fadeChoice
                Toggle(isOn: binding(\.pullMainToMinusInfinity)) { Text(t.deskPullMain) }
                    .toggleStyle(.checkbox)
            }
            .disabled(!d.enabled)
            .opacity(d.enabled ? 1 : 0.5)
            Toggle(isOn: binding(\.enabled)) { Text(t.deskExperimental) }
                .toggleStyle(.checkbox)
            Text(t.deskOnlyFaders).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func binding(_ key: WritableKeyPath<DeskSettings, Bool>) -> Binding<Bool> {
        Binding(get: { d[keyPath: key] }, set: { (v: Bool) in
            var n = d
            n[keyPath: key] = v
            actions.update(n)
        })
    }

    // MARK: Model, address, check

    private var modelAndAddress: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel(t.deskModel)
                Picker(t.deskModel, selection: modelBinding) {
                    ForEach(DeskModel.allCases) { m in Text(m.displayName).tag(m) }
                }
                .labelsHidden()
                .frame(width: 190)
            }
            VStack(alignment: .leading, spacing: 4) {
                fieldLabel(t.deskAddress)
                DeskTextField(text: d.host, placeholder: "192.168.0.128") { (v: String) in
                    var n = d
                    n.host = v.trimmingCharacters(in: .whitespaces)
                    actions.update(n)
                }
                .frame(width: 170)
                .accessibilityLabel(t.deskAddress)
            }
            Button(t.deskCheck, action: actions.check)
                .buttonStyle(TKButtonStyle())
                .disabled(!state.deskActive)
            Spacer(minLength: 0)
        }
    }

    private var modelBinding: Binding<DeskModel> {
        Binding(get: { d.model }, set: { (m: DeskModel) in
            var n = d
            n.model = m
            actions.update(n)
        })
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(.system(size: Theme.caption, weight: .semibold)).foregroundStyle(Theme.textSecondary)
    }

    // MARK: Status line

    private struct StatusInfo { var color: Color; var text: String; var detail: String? }

    private var statusLine: some View {
        let info = statusInfo
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                StatusDot(color: info.color)
                Text(info.text).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(info.color == Theme.idleDot ? Theme.textSecondary : info.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            if let detail = info.detail {
                Text(detail).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !d.model.readVerified {
                Text(t.deskReadUnverified(d.model.shortName)).font(.system(size: Theme.caption)).foregroundStyle(Theme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(peerAndPort).font(.system(size: Theme.caption))
                .foregroundStyle(peerNotConnected ? Theme.warning : Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// The other Mac runs its console link but is not connected to the console.
    private var peerNotConnected: Bool {
        guard d.enabled, let p = state.peerDesk else { return false }
        return p != .off && !p.isConnected
    }

    /// "The other Mac (…) is connected too · TCP 49280 (…)": what the other Mac told about its own
    /// console link (nothing while it is not linked or runs an older version).
    private var peerAndPort: String {
        let name = state.deskOtherName ?? t.linkOtherMac
        guard d.enabled, let p = state.peerDesk, p != .off else { return t.deskPortNote }
        return (p.isConnected ? t.deskPeerConnected(name) : t.deskPeerNotConnected(name)) + t.s("  ·  ", " ・ ") + t.deskPortNote
    }

    private var statusInfo: StatusInfo {
        let m = d.model.shortName
        if !d.enabled { return StatusInfo(color: Theme.idleDot, text: t.deskStatusOff) }
        if d.host.isEmpty { return StatusInfo(color: Theme.idleDot, text: t.deskStatusNoAddress) }
        if !d.hasValidHost { return StatusInfo(color: Theme.warning, text: t.deskStatusBadAddress) }
        guard let snap = state.desk else { return StatusInfo(color: Theme.idleDot, text: t.deskStatusConnecting(m)) }
        switch snap.status {
        case .connecting: return StatusInfo(color: Theme.idleDot, text: t.deskStatusConnecting(m))
        case .checking: return StatusInfo(color: Theme.idleDot, text: t.deskStatusChecking)
        case .reading: return StatusInfo(color: Theme.ok, text: t.deskStatusReading(m))
        case .stale: return StatusInfo(color: Theme.warning, text: t.deskStatusStale(m))
        case let .fixedLevels(unconfirmed):
            return StatusInfo(color: Theme.warning, text: t.deskStatusFixed, detail: unconfirmed ? t.deskStatusFixedUnconfirmed : nil)
        case .cannotRead: return StatusInfo(color: Theme.warning, text: t.deskStatusCannotRead)
        case .notReachable:
            return StatusInfo(color: Theme.dangerText, text: t.deskStatusNotReachable(m), detail: d.model.supportsOSC ? nil : t.deskStatusQLNoOther)
        }
    }

    // MARK: When levels cannot be read

    private var unreadableBox: some View {
        VStack(alignment: .leading, spacing: 4) {
            fieldLabel(t.deskUnreadableTitle)
            Text(t.deskUnreadableLead).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle(isOn: binding(\.useFixedLevels)) { Text(t.deskUseFixed) }
                .toggleStyle(.checkbox)
            Text(t.deskUseFixedNote).font(.system(size: Theme.caption)).foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: When switching

    private var triggerChoice: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel(t.deskWhenSwitching)
            radio(.confirm, t.deskTriggerConfirm, t.deskTriggerConfirmDetail)
            radio(.automatic, t.deskTriggerAuto, t.deskTriggerAutoDetail)
        }
    }

    private func radio(_ value: DeskTrigger, _ title: String, _ detail: String) -> some View {
        let on = d.trigger == value
        return Button { actions.setTrigger(value) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(on ? Theme.accent : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: Theme.body, weight: on ? .semibold : .regular))
                    Text(detail).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    // MARK: Fade

    private var fadeChoice: some View {
        VStack(alignment: .leading, spacing: 6) {
            fieldLabel(t.deskFade)
            HStack(spacing: 8) {
                ForEach(DeskSettings.fades, id: \.self) { f in fadeButton(f) }
            }
        }
    }

    private func setFade(_ f: Double) {
        var n = d
        n.fade = f
        actions.update(n)
    }

    private func fadeButton(_ f: Double) -> some View {
        let on = d.fade == f
        return Button { setFade(f) } label: {
            Text(t.deskFadeText(f)).frame(minWidth: 64)
        }
        .buttonStyle(TKButtonStyle(kind: on ? .primary : .normal))
        .accessibilityAddTraits(on ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }
}

/// The channel table, written by Mac: this Mac's channel ⇄ the other Mac's channel, and the
/// level now of the channel of the Mac that is the main (when levels are read) or the level to
/// raise to (otherwise). The same table is on both Macs (the columns swap places there).
private struct DeskChannelTable: View {
    let state: ViewState
    let actions: DeskSettingsActions
    private var t: Strings { state.t }
    private var d: DeskSettings { state.deskSettings }
    private var me: String { state.deskMeID }
    private var other: String { state.deskOtherID }
    private var otherName: String { state.deskOtherName ?? t.linkOtherMac }

    /// Levels are shown only while they are being read.
    private var reading: Bool {
        guard let s = state.desk?.status else { return false }
        return s == .reading || s == .stale
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(t.deskMapping).font(.system(size: Theme.caption, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            if !d.rows.isEmpty { header }
            ForEach(Array(d.rows.enumerated()), id: \.element.id) { i, row in rowView(i, row) }
            HStack(spacing: 12) {
                Button(t.deskAddRow, action: addRow)
                    .buttonStyle(.borderless)
                    .disabled(d.newRow(me: me, other: other) == nil)
                Text(t.deskRowHint).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(d.problems(me: me, other: other).enumerated()), id: \.offset) { _, p in
                Text(t.deskProblem(p, model: d.model.shortName)).font(.system(size: Theme.caption)).foregroundStyle(Theme.warning)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(t.deskColumnKind).frame(width: DeskRowView.kindWidth, alignment: .leading)
            Text(t.deskColumnMac(state.deskMeName)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            Text("⇄").frame(width: DeskRowView.arrowWidth)
            Text(t.deskColumnMac(otherName)).lineLimit(1).frame(width: DeskRowView.otherWidth, alignment: .leading)
            Text(reading ? t.deskColumnLevel : t.deskColumnFixed).frame(width: DeskRowView.levelWidth, alignment: .leading)
            Color.clear.frame(width: 24)
        }
        .font(.system(size: Theme.caption, weight: .semibold)).foregroundStyle(Theme.textSecondary)
        .accessibilityHidden(true)
    }

    private func rowView(_ i: Int, _ row: DeskRow) -> some View {
        // The sounding channel is the main Mac's: this Mac's while it is the main.
        let mac = state.sendKeys ? me : other
        let ch = DeskChannel(row.kind, row.channels[mac] ?? 0)
        let level = reading ? state.desk?.levels[ch] : nil
        return DeskRowView(index: i, row: row, model: d.model, me: me, other: other,
                           meName: state.deskMeName, otherName: otherName, level: level,
                           fresh: state.desk?.fresh.contains(ch) == true, t: t,
                           onChange: { r in replace(i, r) }, onRemove: { remove(i) })
    }

    private func replace(_ i: Int, _ r: DeskRow) {
        var n = d
        guard n.rows.indices.contains(i) else { return }
        n.rows[i] = r
        actions.update(n)
    }

    private func remove(_ i: Int) {
        var n = d
        guard n.rows.indices.contains(i) else { return }
        n.rows.remove(at: i)
        actions.update(n)
    }

    private func addRow() {
        var n = d
        guard let r = n.newRow(me: me, other: other) else { return }
        n.rows.append(r)
        actions.update(n)
    }
}

private struct DeskRowView: View {
    static let kindWidth: CGFloat = 84
    static let arrowWidth: CGFloat = 16
    static let otherWidth: CGFloat = 140
    static let levelWidth: CGFloat = 96
    let index: Int
    let row: DeskRow
    let model: DeskModel
    /// The two Macs' keys in `row.channels`.
    let me: String
    let other: String
    let meName: String
    let otherName: String
    /// The main Mac's channel's level as read, or nil: show the fixed level to raise to.
    let level: Int?
    let fresh: Bool
    let t: Strings
    let onChange: (DeskRow) -> Void
    let onRemove: () -> Void

    private var limit: Int { max(1, model.channelLimit(row.kind)) }

    var body: some View {
        HStack(spacing: 8) {
            kindCell.frame(width: Self.kindWidth, alignment: .leading)
            HStack(spacing: 6) {
                channelField(row.channels[me], label: t.deskMacChannel(meName, row: index + 1), set: setMine)
                DeskTextField(text: row.name, placeholder: t.deskNamePlaceholder, onCommit: setName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("⇄").foregroundStyle(Theme.textSecondary).frame(width: Self.arrowWidth).accessibilityHidden(true)
            HStack(spacing: 6) {
                channelField(row.channels[other], label: t.deskMacChannel(otherName, row: index + 1), set: setOthers)
                if !row.name.isEmpty {
                    Text(row.name).font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                }
            }
            .frame(width: Self.otherWidth, alignment: .leading)
            levelCell.frame(width: Self.levelWidth, alignment: .leading)
            Button(action: onRemove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .frame(width: 24)
                .help(t.deskRemoveRow)
                .accessibilityLabel(t.deskRemoveRow)
        }
    }

    @ViewBuilder private var kindCell: some View {
        if model.hasStereoIn || row.kind == .stereoIn {
            Picker(t.deskColumnKind, selection: Binding(get: { row.kind }, set: setKind)) {
                Text(t.deskKindInput).tag(DeskChannelKind.input)
                Text(t.deskKindStereo).tag(DeskChannelKind.stereoIn)
            }
            .labelsHidden()
        } else {
            Text(t.deskKindInput)
                .font(.system(size: Theme.caption, weight: .semibold))
                .padding(.horizontal, 8).frame(minHeight: 22)
                .background(RoundedRectangle(cornerRadius: 4).fill(Theme.buttonBackground))
        }
    }

    private func setMine(_ n: Int) { var r = row; r.channels[me] = n; onChange(r) }
    private func setOthers(_ n: Int) { var r = row; r.channels[other] = n; onChange(r) }
    private func setName(_ v: String) { var r = row; r.name = String(v.prefix(40)); onChange(r) }

    private func setFixedLevel(_ v: String) {
        guard let x = DeskLevel.parse(v), x > DeskLevel.minusInfinity else { return }
        var r = row
        r.fixedLevel = x
        onChange(r)
    }

    /// Another kind of channel: the numbers are kept within its limit.
    private func setKind(_ k: DeskChannelKind) {
        var r = row
        r.kind = k
        let top = max(1, model.channelLimit(k))
        for key in [me, other] {
            if let n = r.channels[key] { r.channels[key] = min(top, max(1, n)) }
        }
        onChange(r)
    }

    private func channelField(_ n: Int?, label: String, set: @escaping (Int) -> Void) -> some View {
        let top = limit
        return DeskTextField(text: n.map { "\($0)" } ?? "", placeholder: "–") { (v: String) in
            guard let x = Int(v.trimmingCharacters(in: .whitespaces)) else { return }
            set(min(top, max(1, x)))
        }
        .frame(width: 48)
        .accessibilityLabel(label)
        .help("1–\(top)")
    }

    @ViewBuilder private var levelCell: some View {
        if let level {
            Text(DeskLevel.text(level))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(fresh ? Theme.ok : Theme.textSecondary)
        } else {
            HStack(spacing: 4) {
                DeskTextField(text: DeskLevel.number(row.fixedLevel), placeholder: "0.0", onCommit: setFixedLevel)
                    .frame(width: 58)
                    .accessibilityLabel(t.deskFixedLevelFor(index + 1))
                Text("dB").font(.system(size: Theme.caption)).foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

/// A text field that hands its text over when editing ends (not on every keystroke). An entry
/// that is not taken goes back to the stored value.
private struct DeskTextField: View {
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
            .onChange(of: text) { value = $0 }
            .onChange(of: focused) { if !$0 { commit() } }
            .onSubmit(commit)
            .onDisappear { if value != text { onCommit(value) } }     // Settings closed while typing
    }

    private func commit() {
        guard value != text else { return }
        onCommit(value)
        value = text
    }
}
#endif
