import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var version: Int = 1
    public var instanceID: UUID = UUID()
    public var sendKeys: Bool = true
    public var receiveNotes: Bool = true
    public var keyCapture: Bool = true
    public var autoNoteOffSeconds: Double = 10
    /// 1-16 as shown to people.
    public var midiChannel: Int = 1
    public var lastPeerID: String?
    /// CoreMIDI unique ID of the virtual port, kept stable so a DAW remembers it.
    public var midiUniqueID: Int32?
    /// UI language: "system", "en" or "ja".
    public var language: String = "system"
    /// Last IP address typed in "Connect by IP Address…".
    public var manualAddress: String?
    /// Keys that fire fixed cue notes (arrows, Space…).
    public var cueKeys: [CueKey] = CueKey.defaults
    /// Keep cue keys from other apps (needs the Accessibility permission).
    public var blockCueKeys: Bool = true
    /// Look for new versions and download them in the background.
    public var autoUpdate: Bool = true
    /// Show TwinKeys only in the menu bar (no Dock icon).
    public var menuBarOnly: Bool = false

    enum CodingKeys: String, CodingKey {
        case version
        case instanceID = "instance_id"
        case sendKeys = "send_keys"
        case receiveNotes = "receive_notes"
        case keyCapture = "key_capture"
        case autoNoteOffSeconds = "auto_note_off_seconds"
        case midiChannel = "midi_channel"
        case lastPeerID = "last_peer_id"
        case midiUniqueID = "midi_unique_id"
        case language
        case manualAddress = "manual_address"
        case cueKeys = "cue_keys"
        case blockCueKeys = "block_cue_keys"
        case autoUpdate = "auto_update"
        case menuBarOnly = "menu_bar_only"
    }

    public init() {}

    /// Missing keys fall back to defaults so older or hand-edited files still load.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? d.version
        instanceID = try c.decodeIfPresent(UUID.self, forKey: .instanceID) ?? d.instanceID
        sendKeys = try c.decodeIfPresent(Bool.self, forKey: .sendKeys) ?? d.sendKeys
        receiveNotes = try c.decodeIfPresent(Bool.self, forKey: .receiveNotes) ?? d.receiveNotes
        keyCapture = try c.decodeIfPresent(Bool.self, forKey: .keyCapture) ?? d.keyCapture
        autoNoteOffSeconds = try c.decodeIfPresent(Double.self, forKey: .autoNoteOffSeconds) ?? d.autoNoteOffSeconds
        midiChannel = min(16, max(1, (try? c.decodeIfPresent(Int.self, forKey: .midiChannel)) ?? d.midiChannel))
        lastPeerID = try c.decodeIfPresent(String.self, forKey: .lastPeerID)
        midiUniqueID = try c.decodeIfPresent(Int32.self, forKey: .midiUniqueID)
        let lang = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        language = ["system", "en", "ja"].contains(lang) ? lang : "system"
        manualAddress = try c.decodeIfPresent(String.self, forKey: .manualAddress)
        // A broken cue key list falls back to the defaults instead of losing every setting.
        // One unreadable entry drops only that entry, not the whole list.
        if let keys = try? c.decodeIfPresent([Lenient<CueKey>].self, forKey: .cueKeys) {
            cueKeys = CueKey.sanitized(keys.compactMap(\.value))
        }
        blockCueKeys = try c.decodeIfPresent(Bool.self, forKey: .blockCueKeys) ?? d.blockCueKeys
        autoUpdate = try c.decodeIfPresent(Bool.self, forKey: .autoUpdate) ?? d.autoUpdate
        menuBarOnly = try c.decodeIfPresent(Bool.self, forKey: .menuBarOnly) ?? d.menuBarOnly
    }
}

/// Decodes an element if it can, nil otherwise (so one bad entry does not fail the array).
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws { value = try? T(from: decoder) }
}

/// File locations. `home` is injectable for tests.
public struct AppPaths: Sendable {
    public var home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    public var supportDir: URL { home.appendingPathComponent("Library/Application Support/TwinKeys", isDirectory: true) }
    public var logsDir: URL { home.appendingPathComponent("Library/Logs/TwinKeys", isDirectory: true) }
    public var settingsFile: URL { supportDir.appendingPathComponent("settings.json") }
}

/// Loads and saves settings and mapping. Writes the defaults on first run so
/// people can find and edit them.
public struct ConfigStore: Sendable {
    public var paths: AppPaths
    public init(paths: AppPaths = AppPaths()) { self.paths = paths }

    public func loadSettings() -> AppSettings { loadSettingsReportingProblem().0 }

    /// Loads settings. If settings.json exists but cannot be read, it is kept as
    /// settings.broken-<time>.json (never silently lost), defaults are used, and the
    /// backup's name is returned as the problem.
    public func loadSettingsReportingProblem() -> (AppSettings, String?) {
        let fm = FileManager.default
        if let data = try? Data(contentsOf: paths.settingsFile) {
            if let s = try? JSONDecoder().decode(AppSettings.self, from: data) { return (s, nil) }
            let stamp = Int(Date().timeIntervalSince1970)
            let backup = paths.supportDir.appendingPathComponent("settings.broken-\(stamp).json")
            try? fm.moveItem(at: paths.settingsFile, to: backup)
            let s = AppSettings()
            try? save(s)
            return (s, backup.lastPathComponent)
        }
        let s = AppSettings()
        try? save(s)
        return (s, nil)
    }

    public func save(_ s: AppSettings) throws {
        try FileManager.default.createDirectory(at: paths.supportDir, withIntermediateDirectories: true)
        let enc = JSONEncoder(); enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        try enc.encode(s).write(to: paths.settingsFile, options: .atomic)
    }
}
