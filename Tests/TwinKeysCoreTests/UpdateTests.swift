import XCTest
@testable import TwinKeysCore

final class UpdateTests: XCTestCase {
    func v(_ s: String) -> AppVersion { AppVersion(s)! }

    func testVersionOrder() {
        XCTAssertLessThan(v("0.9.1"), v("0.10.0"))
        XCTAssertLessThan(v("1.0.0-beta.2"), v("1.0.0"))
        XCTAssertLessThan(v("1.0.0-beta.2"), v("1.0.0-beta.10"))
        XCTAssertLessThan(v("1.0.0-alpha"), v("1.0.0-beta"))
        XCTAssertEqual(v("v1.2.3"), v("1.2.3"))
        XCTAssertNil(AppVersion("1.2")); XCTAssertNil(AppVersion("1.2.x")); XCTAssertNil(AppVersion("1.2.3-"))
    }

    func asset(_ ver: String) -> GitHubRelease.Asset {
        .init(name: "TwinKeys-\(ver).dmg", browserDownloadURL: "https://github.com/kajisho5/ableton-twinkeys/releases/download/v\(ver)/TwinKeys-\(ver).dmg", size: 10)
    }

    func testPicksNewestFullReleaseWithItsDmg() {
        let list = [
            GitHubRelease(tagName: "v1.2.0", draft: true, assets: [asset("1.2.0")]),
            GitHubRelease(tagName: "v1.1.1-beta.1", prerelease: true, assets: [asset("1.1.1-beta.1")]),
            GitHubRelease(tagName: "v1.1.0", assets: []),                         // .dmg not uploaded yet
            GitHubRelease(tagName: "v1.0.1", assets: [asset("1.0.1")]),
            GitHubRelease(tagName: "v1.0.0", assets: [asset("1.0.0")]),
        ]
        XCTAssertEqual(UpdateCheck.newest(in: list, newerThan: v("1.0.0"))?.version, v("1.0.1"))
        XCTAssertNil(UpdateCheck.newest(in: list, newerThan: v("1.0.1")))
        XCTAssertEqual(UpdateCheck.newest(in: list, newerThan: v("0.5.0"))?.version, v("1.0.1"))
    }

    func testRejectsDownloadsFromOtherHosts() {
        let bad = GitHubRelease(tagName: "v2.0.0", assets: [.init(name: "TwinKeys-2.0.0.dmg", browserDownloadURL: "http://example.com/x.dmg", size: 1)])
        XCTAssertNil(UpdateCheck.newest(in: [bad], newerThan: v("1.0.0")))
    }

    func testDecodesGitHubAnswer() throws {
        let json = """
        [{"tag_name":"v1.0.1","draft":false,"prerelease":false,"html_url":"https://github.com/kajisho5/ableton-twinkeys/releases/tag/v1.0.1",
          "assets":[{"name":"TwinKeys-1.0.1.dmg","size":1234,"browser_download_url":"https://github.com/kajisho5/ableton-twinkeys/releases/download/v1.0.1/TwinKeys-1.0.1.dmg","other":1}],"body":"x"}]
        """
        let r = try UpdateCheck.decode(Data(json.utf8))
        XCTAssertEqual(UpdateCheck.newest(in: r, newerThan: v("1.0.0"))?.dmgSize, 1234)
    }
}
