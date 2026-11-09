#if os(macOS)
import AppKit
import Foundation
import Security
import TwinKeysCore

/// What the window shows about updates.
enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case downloading(version: String)
    /// Downloaded and checked; replaced when TwinKeys quits.
    case ready(version: String)
    /// A newer version exists but cannot be installed automatically (see `reason`).
    case manual(version: String, reason: ManualReason)
    case failed

    enum ManualReason: Equatable { case notWritable, notSigned, translocated }
}

/// Finds new versions on GitHub, downloads the .dmg, checks the signature and swaps the app
/// when TwinKeys quits. It never replaces or restarts the app on its own while it runs:
/// a show must never be interrupted.
@MainActor
final class Updater {
    private(set) var state: UpdateState = .idle { didSet { if state != oldValue { onChange?() } } }
    var onChange: (() -> Void)?
    var log: (String) -> Void = { _ in }

    private let current: AppVersion?
    private var timer: Timer?
    private var staged: URL?
    private var busy = false
    private var lastOffer: UpdateOffer?
    private let cacheDir: URL
    static let bundleID = "io.github.kajisho5.twinkeys"

    init() {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        current = v.flatMap(AppVersion.init)
        cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TwinKeys/Updates", isDirectory: true)
    }

    var currentVersion: String { current?.description ?? "?" }
    var pendingVersion: String? { if case let .ready(v) = state { return v }; return nil }
    var releasePage: URL { lastOffer?.pageURL ?? UpdateCheck.releasesPage }

    /// Starts the schedule (first check after a minute, then every six hours).
    func start(enabled: Bool) {
        timer?.invalidate(); timer = nil
        guard enabled else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + UpdateCheck.firstCheckDelay) { [weak self] in
            guard let self, self.timer != nil else { return }
            self.check()
        }
        timer = Timer.scheduledTimer(withTimeInterval: UpdateCheck.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }

    /// Checks now (also from "Check for Updates…").
    func check() {
        guard !busy, let current else { return }
        if case .ready = state { return }
        busy = true
        state = .checking
        var req = URLRequest(url: UpdateCheck.releasesURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("TwinKeys/\(current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let releases = (status == 200 ? data.flatMap { try? UpdateCheck.decode($0) } : nil)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let releases else {
                    self.log("Update check failed (HTTP \(status), \(error?.localizedDescription ?? "no data"))")
                    self.busy = false; self.state = .failed; return
                }
                guard let offer = UpdateCheck.newest(in: releases, newerThan: current) else {
                    self.busy = false; self.state = .upToDate; return
                }
                self.lastOffer = offer
                self.log("Update \(offer.version) found")
                if let reason = self.cannotInstallReason() {
                    self.busy = false; self.state = .manual(version: offer.version.description, reason: reason); return
                }
                self.download(offer)
            }
        }.resume()
    }

    /// Why the app cannot replace itself here (nil: it can).
    private func cannotInstallReason() -> UpdateState.ManualReason? {
        let app = Bundle.main.bundleURL
        if app.path.contains("/AppTranslocation/") { return .translocated }
        if Self.teamID(ofCodeAt: app) == nil { return .notSigned }
        let parent = app.deletingLastPathComponent().path
        if !FileManager.default.isWritableFile(atPath: parent) || !FileManager.default.isWritableFile(atPath: app.path) {
            return .notWritable
        }
        return nil
    }

    private func download(_ offer: UpdateOffer) {
        state = .downloading(version: offer.version.description)
        URLSession.shared.downloadTask(with: offer.dmgURL) { tmp, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            // Move the file before this handler returns (the temporary file is deleted afterwards).
            var dmg: URL?
            if let tmp, status == 200 {
                let dest = FileManager.default.temporaryDirectory.appendingPathComponent("TwinKeys-\(offer.version).dmg")
                try? FileManager.default.removeItem(at: dest)
                if (try? FileManager.default.moveItem(at: tmp, to: dest)) != nil { dmg = dest }
            }
            DispatchQueue.global(qos: .utility).async {
                let result = dmg.flatMap { self.unpackAndVerify(dmg: $0, version: offer.version) }
                if let dmg { try? FileManager.default.removeItem(at: dmg) }
                DispatchQueue.main.async {
                    self.busy = false
                    if let result {
                        self.staged = result
                        self.state = .ready(version: offer.version.description)
                        self.log("Update \(offer.version) is ready; it is installed when TwinKeys quits")
                    } else {
                        self.log("Update \(offer.version) download or check failed (HTTP \(status), \(error?.localizedDescription ?? "-"))")
                        self.state = .failed
                    }
                }
            }
        }.resume()
    }

    /// Mounts the .dmg, copies TwinKeys.app out and checks it is signed by the same developer
    /// with the same app ID. Returns the copied app, or nil.
    nonisolated private func unpackAndVerify(dmg: URL, version: AppVersion) -> URL? {
        let fm = FileManager.default
        let mount = fm.temporaryDirectory.appendingPathComponent("TwinKeys-mount-\(UUID().uuidString)")
        let dir = cacheDir.appendingPathComponent(version.description, isDirectory: true)
        try? fm.removeItem(at: dir)
        guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil,
              (try? fm.createDirectory(at: mount, withIntermediateDirectories: true)) != nil else { return nil }
        guard Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path, dmg.path]) else { return nil }
        defer {
            _ = Self.run("/usr/bin/hdiutil", ["detach", "-force", mount.path])
            try? fm.removeItem(at: mount)
        }
        let dest = dir.appendingPathComponent("TwinKeys.app")
        guard Self.run("/usr/bin/ditto", [mount.appendingPathComponent("TwinKeys.app").path, dest.path]) else { return nil }
        // Same developer team and app ID as the running app, and the version it claims.
        guard let myTeam = Self.teamID(ofCodeAt: Bundle.main.bundleURL), Self.verify(dest, team: myTeam) else {
            try? fm.removeItem(at: dir); return nil
        }
        let plist = NSDictionary(contentsOf: dest.appendingPathComponent("Contents/Info.plist"))
        guard plist?["CFBundleIdentifier"] as? String == Self.bundleID,
              plist?["CFBundleShortVersionString"] as? String == version.description else {
            try? fm.removeItem(at: dir); return nil
        }
        return dest
    }

    /// Replaces the app with the downloaded one after this process exits. Called while quitting.
    /// `relaunch`: open the new version afterwards ("Restart Now").
    func installOnQuit(relaunch: Bool = false) {
        guard let staged, FileManager.default.fileExists(atPath: staged.path) else { return }
        let app = Bundle.main.bundleURL.path
        let old = app + ".old-\(ProcessInfo.processInfo.processIdentifier)"
        // A small shell script waits for TwinKeys to exit, swaps the bundles, and keeps the old
        // one if anything fails. Paths are passed as arguments, never pasted into the script.
        let script = """
        pid="$1"; app="$2"; new="$3"; old="$4"; relaunch="$5"
        for i in $(seq 1 300); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
        if mv "$app" "$old" && /usr/bin/ditto "$new" "$app"; then
          rm -rf "$old" "$new"
        else
          rm -rf "$app"; mv "$old" "$app"
        fi
        [ "$relaunch" = 1 ] && /usr/bin/open "$app"
        exit 0
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", script, "twinkeys-update", "\(ProcessInfo.processInfo.processIdentifier)", app, staged.path, old, relaunch ? "1" : "0"]
        do { try p.run(); log("Installing update on quit") } catch { log("Could not start the update: \(error)") }
    }

    // MARK: Code signature

    /// Team ID of the Developer ID signature of the app at `url`, if it has a valid one.
    nonisolated static func teamID(ofCodeAt url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Valid Developer ID signature (all nested code too) of `team`, for TwinKeys' app ID.
    nonisolated static func verify(_ url: URL, team: String) -> Bool {
        guard team.allSatisfy({ $0.isLetter || $0.isNumber }) else { return false }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let text = "anchor apple generic and identifier \"\(bundleID)\" and certificate leaf[subject.OU] = \"\(team)\""
        var req: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &req) == errSecSuccess, let req else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, req) == errSecSuccess
    }

    nonisolated private static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
#endif
