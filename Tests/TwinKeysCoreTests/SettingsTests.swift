import XCTest
@testable import TwinKeysCore

final class SettingsTests: XCTestCase {
    var tmp: URL!
    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("twinkeys-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func testPaths() {
        let p = AppPaths(home: URL(fileURLWithPath: "/Users/example"))
        XCTAssertEqual(p.supportDir.path, "/Users/example/Library/Application Support/TwinKeys")
        XCTAssertEqual(p.logsDir.path, "/Users/example/Library/Logs/TwinKeys")
    }

    func testFirstRunWritesDefaultsAndKeepsInstanceID() throws {
        let store = ConfigStore(paths: AppPaths(home: tmp))
        let s1 = store.loadSettings()
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.paths.settingsFile.path))
        let s2 = store.loadSettings()
        XCTAssertEqual(s1.instanceID, s2.instanceID)
        XCTAssertEqual(s2.autoNoteOffSeconds, 10)
        XCTAssertEqual(s2.cueKeys, CueKey.defaults)
    }

    func testPartialSettingsFileUsesDefaults() throws {
        let json = #"{"auto_note_off_seconds": 4, "midi_channel": 99}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.autoNoteOffSeconds, 4)
        XCTAssertEqual(s.midiChannel, 16)
        XCTAssertTrue(s.sendKeys)
        XCTAssertEqual(s.language, "system")
    }

    func testLanguageSetting() throws {
        let ja = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"language": "ja"}"#.utf8))
        XCTAssertEqual(ja.language, "ja")
        let bad = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"language": "fr"}"#.utf8))
        XCTAssertEqual(bad.language, "system")
    }

    func testBrokenSettingsAreKeptAsBackup() throws {
        let store = ConfigStore(paths: AppPaths(home: tmp))
        try FileManager.default.createDirectory(at: store.paths.supportDir, withIntermediateDirectories: true)
        let broken = #"{"instance_id": "11111111-2222-3333-4444-555555555555", "midi_channel": 2"#   // missing closing brace
        try Data(broken.utf8).write(to: store.paths.settingsFile)
        let (s, problem) = store.loadSettingsReportingProblem()
        let name = try XCTUnwrap(problem)
        XCTAssertTrue(name.hasPrefix("settings.broken-"))
        let kept = try String(contentsOf: store.paths.supportDir.appendingPathComponent(name), encoding: .utf8)
        XCTAssertEqual(kept, broken)                     // the person's file is not lost
        XCTAssertEqual(s.midiChannel, 1)                  // defaults in use
        XCTAssertNil(store.loadSettingsReportingProblem().1)   // the new file reads fine
    }
}
