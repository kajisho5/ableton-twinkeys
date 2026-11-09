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

        let (m, err) = store.loadMapping()
        XCTAssertNil(err); XCTAssertEqual(m, .default)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.paths.mappingFile.path))
    }

    func testPartialSettingsFileUsesDefaults() throws {
        let json = #"{"auto_note_off_seconds": 4, "midi_channel": 99}"#
        let s = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(s.autoNoteOffSeconds, 4)
        XCTAssertEqual(s.midiChannel, 16)
        XCTAssertTrue(s.sendKeys)
    }

    func testBrokenMappingFallsBackToDefault() throws {
        let store = ConfigStore(paths: AppPaths(home: tmp))
        try FileManager.default.createDirectory(at: store.paths.supportDir, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: store.paths.mappingFile)
        let (m, err) = store.loadMapping()
        XCTAssertEqual(m, .default)
        XCTAssertNotNil(err)
    }
}
