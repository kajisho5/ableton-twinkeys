import XCTest
@testable import TwinKeysCore

final class SettingsRemoteDefaultTests: XCTestCase {
    func testRemoteIsOffByDefaultAndForOldFiles() throws {
        XCTAssertFalse(AppSettings().remoteEnabled)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertFalse(old.remoteEnabled)
        let on = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"remote_enabled": true}"#.utf8))
        XCTAssertTrue(on.remoteEnabled)
    }
}
