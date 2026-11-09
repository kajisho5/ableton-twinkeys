import Foundation

/// A version like 1.0.0 or 1.1.0-beta.2 (semantic versioning, without build metadata).
public struct AppVersion: Comparable, Equatable, Sendable, CustomStringConvertible {
    public var major: Int, minor: Int, patch: Int
    /// "beta.2" for 1.1.0-beta.2; empty for a full release.
    public var prerelease: String

    public init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") { s.removeFirst() }
        if let plus = s.firstIndex(of: "+") { s = String(s[..<plus]) }
        let parts = s.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let nums = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard nums.count == 3, let a = Int(nums[0]), let b = Int(nums[1]), let c = Int(nums[2]),
              a >= 0, b >= 0, c >= 0 else { return nil }
        major = a; minor = b; patch = c
        prerelease = parts.count > 1 ? String(parts[1]) : ""
        if parts.count > 1 && prerelease.isEmpty { return nil }
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }
    public var description: String { "\(major).\(minor).\(patch)" + (prerelease.isEmpty ? "" : "-\(prerelease)") }

    public static func < (l: AppVersion, r: AppVersion) -> Bool {
        if (l.major, l.minor, l.patch) != (r.major, r.minor, r.patch) {
            return (l.major, l.minor, l.patch) < (r.major, r.minor, r.patch)
        }
        // A full release is newer than any of its pre-releases.
        if l.prerelease.isEmpty != r.prerelease.isEmpty { return !l.prerelease.isEmpty }
        let a = l.prerelease.split(separator: "."), b = r.prerelease.split(separator: ".")
        for (x, y) in zip(a, b) where x != y {
            switch (Int(x), Int(y)) {
            case let (i?, j?): return i < j
            case (_?, nil): return true        // numeric identifiers sort before text
            case (nil, _?): return false
            default: return x < y
            }
        }
        return a.count < b.count
    }
}

/// One entry of GitHub's "list releases" answer (only the fields we use).
public struct GitHubRelease: Decodable, Equatable, Sendable {
    public struct Asset: Decodable, Equatable, Sendable {
        public var name: String
        public var browserDownloadURL: String
        public var size: Int
        enum CodingKeys: String, CodingKey { case name, size; case browserDownloadURL = "browser_download_url" }
        public init(name: String, browserDownloadURL: String, size: Int) {
            self.name = name; self.browserDownloadURL = browserDownloadURL; self.size = size
        }
    }
    public var tagName: String
    public var draft: Bool
    public var prerelease: Bool
    public var htmlURL: String
    public var assets: [Asset]
    enum CodingKeys: String, CodingKey {
        case draft, prerelease, assets
        case tagName = "tag_name", htmlURL = "html_url"
    }
    public init(tagName: String, draft: Bool = false, prerelease: Bool = false, htmlURL: String = "", assets: [Asset]) {
        self.tagName = tagName; self.draft = draft; self.prerelease = prerelease; self.htmlURL = htmlURL; self.assets = assets
    }
}

/// An update that can be downloaded.
public struct UpdateOffer: Equatable, Sendable {
    public var version: AppVersion
    public var dmgURL: URL
    public var dmgSize: Int
    public var pageURL: URL?
}

public enum UpdateCheck {
    /// GitHub REST API: every release of the repository (newest first).
    /// https://docs.github.com/en/rest/releases/releases#list-releases
    public static let releasesURL = URL(string: "https://api.github.com/repos/kajisho5/ableton-twinkeys/releases?per_page=20")!
    public static let releasesPage = URL(string: "https://github.com/kajisho5/ableton-twinkeys/releases/latest")!
    /// First check one minute after launch, then every six hours.
    public static let firstCheckDelay: TimeInterval = 60
    public static let interval: TimeInterval = 6 * 3600

    /// The newest full release that is newer than `current` and has its .dmg
    /// (named TwinKeys-<version>.dmg, as the release workflow uploads it).
    /// Drafts and pre-releases are never offered.
    public static func newest(in releases: [GitHubRelease], newerThan current: AppVersion) -> UpdateOffer? {
        var best: UpdateOffer?
        for r in releases where !r.draft && !r.prerelease {
            guard let v = AppVersion(r.tagName), !v.isPrerelease, v > current else { continue }
            guard let dmg = r.assets.first(where: { $0.name == "TwinKeys-\(v).dmg" }),
                  let url = URL(string: dmg.browserDownloadURL), url.scheme == "https",
                  url.host == "github.com" || url.host?.hasSuffix(".githubusercontent.com") == true else { continue }
            if best == nil || v > best!.version {
                best = UpdateOffer(version: v, dmgURL: url, dmgSize: dmg.size, pageURL: URL(string: r.htmlURL))
            }
        }
        return best
    }

    public static func decode(_ data: Data) throws -> [GitHubRelease] {
        try JSONDecoder().decode([GitHubRelease].self, from: data)
    }
}
