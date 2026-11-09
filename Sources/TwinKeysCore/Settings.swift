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
        midiChannel = min(16, max(1, try c.decodeIfPresent(Int.self, forKey: .midiChannel) ?? d.midiChannel))
        lastPeerID = try c.decodeIfPresent(String.self, forKey: .lastPeerID)
        midiUniqueID = try c.decodeIfPresent(Int32.self, forKey: .midiUniqueID)
        let lang = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        language = ["system", "en", "ja"].contains(lang) ? lang : "system"
    }
}

/// File locations. `home` is injectable for tests.
public struct AppPaths: Sendable {
    public var home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) { self.home = home }

    public var supportDir: URL { home.appendingPathComponent("Library/Application Support/TwinKeys", isDirectory: true) }
    public var logsDir: URL { home.appendingPathComponent("Library/Logs/TwinKeys", isDirectory: true) }
    public var settingsFile: URL { supportDir.appendingPathComponent("settings.json") }
    public var mappingFile: URL { supportDir.appendingPathComponent("mapping.json") }
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

    /// Returns the mapping and, if the file was broken, the reason (the default is used then).
    public func loadMapping() -> (KeyMapping, String?) {
        guard let data = try? Data(contentsOf: paths.mappingFile) else {
            try? writeDefaultMapping()
            return (.default, nil)
        }
        do { return (try KeyMapping.decode(data), nil) }
        catch { return (.default, "mapping.json could not be read (\(error)); using the default mapping") }
    }

    public func writeDefaultMapping() throws {
        try FileManager.default.createDirectory(at: paths.supportDir, withIntermediateDirectories: true)
        try KeyMapping.default.encoded().write(to: paths.mappingFile, options: .atomic)
    }
}
