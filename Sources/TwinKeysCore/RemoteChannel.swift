import Crypto
import Foundation

/// The iPhone ↔ main Mac connection (TwinKeys Remote). Runs over a TCP stream; this type only
/// turns bytes into messages and back, so it is the same code on both sides and testable here.
///
/// Handshake (both sides need the same pairing code; the iPhone also has its own key pair):
///  1. iPhone → Mac  ClientHello {device id, name, device public key (X25519), nonce}, tagged
///     with HMAC(pairing key). A wrong pairing code fails here.
///  2. Mac → iPhone  ServerHello {Mac id, name, fresh X25519 public key, nonce}, tagged with
///     HMAC(pairing key) over both hellos.
///  3. Both derive the session keys with HKDF from X25519(device key, Mac's fresh key), salted with
///     the pairing key and bound to both hellos. Only the holder of the device's private key gets
///     the same keys, so the device's first sealed message proves it is that device.
///  4. A device the Mac has not approved yet waits until someone clicks Allow on the Mac. Both show
///     the same 4-digit code (from a hash of both hellos) so the right iPhone is approved.
/// After that every message is sealed with ChaCha20-Poly1305, with a counter as nonce (a replayed
/// or reordered frame is refused).
public enum RemoteProtocol {
    public static let version = 1
    public static let serviceType = "_twinkeys-remote._tcp"
    public static let maxFrame = 4 * 1024 * 1024
    static let tagSize = 32
}

public struct RemoteClientHello: Codable, Equatable, Sendable {
    public var version: Int
    public var deviceID: String
    public var deviceName: String
    public var devicePublicKey: Data
    public var nonce: Data
}

extension RemoteClientHello {
    public static let maxNameLength = 64

    /// A device name that is safe to show in an alert or a log: no control or invisible formatting
    /// characters (line breaks, right-to-left overrides), trimmed, at most 64 characters.
    public static func sanitizedName(_ name: String) -> String {
        let kept = name.unicodeScalars.filter { u in
            switch u.properties.generalCategory {
            case .control, .format, .lineSeparator, .paragraphSeparator, .surrogate, .unassigned, .privateUse:
                return u == "\u{200D}"     // keep the zero-width joiner (emoji sequences)
            default:
                return true
            }
        }
        var s = String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces)
        if s.count > maxNameLength { s = String(s.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces) }
        return s.isEmpty ? "iPhone" : s
    }
}

public struct RemoteServerHello: Codable, Equatable, Sendable {
    public var version: Int
    public var serverID: String
    public var serverName: String
    public var ephemeralPublicKey: Data
    public var nonce: Data
}

/// Shown on the iPhone: the state of both Macs.
public struct RemoteStatus: Codable, Equatable, Sendable {
    public var mainName: String
    public var mainLiveConnected: Bool
    public var backupName: String?
    public var backupLinked: Bool
    public var backupLiveConnected: Bool
    public var latencyMs: Double?
    public var lastCue: CueSummary?
    public var cueKeys: [CueKeySummary]
    /// 2.1: how the backup's Live set differs from the main's (nil: same, or not known).
    public var setDiff: SetDiff?
    public init(mainName: String, mainLiveConnected: Bool, backupName: String?, backupLinked: Bool,
                backupLiveConnected: Bool, latencyMs: Double?, lastCue: CueSummary?, cueKeys: [CueKeySummary],
                setDiff: SetDiff? = nil) {
        self.mainName = mainName; self.mainLiveConnected = mainLiveConnected; self.backupName = backupName
        self.backupLinked = backupLinked; self.backupLiveConnected = backupLiveConnected
        self.latencyMs = latencyMs; self.lastCue = lastCue; self.cueKeys = cueKeys; self.setDiff = setDiff
    }

    public struct CueSummary: Codable, Equatable, Sendable {
        public var label: String
        public var memo: String
        public var count: Int
        /// "delivered", "waiting", "missing", "unconfirmed", "notConnected"
        public var delivery: String
        public init(label: String, memo: String, count: Int, delivery: String) {
            self.label = label; self.memo = memo; self.count = count; self.delivery = delivery
        }
    }

    public struct CueKeySummary: Codable, Equatable, Sendable, Identifiable {
        public var keycode: UInt16
        public var label: String
        public var memo: String
        public var id: UInt16 { keycode }
        public init(keycode: UInt16, label: String, memo: String) { self.keycode = keycode; self.label = label; self.memo = memo }
    }
}

/// Connection display (docs/design-links.md): the Apple Watch as the iPhone sees it
/// (WatchConnectivity). The watch never talks to a Mac; the iPhone reports it with each ping.
public struct RemoteWatchState: Codable, Equatable, Sendable {
    /// A watch is paired with the iPhone.
    public var paired: Bool
    /// TwinKeys is installed on that watch.
    public var appInstalled: Bool
    /// The watch app answers right now (it is open on the watch).
    public var reachable: Bool
    public init(paired: Bool, appInstalled: Bool, reachable: Bool) {
        self.paired = paired; self.appInstalled = appInstalled; self.reachable = reachable
    }

    public var level: WatchLevel {
        guard paired, appInstalled else { return .absent }
        return reachable ? .reachable : .notReachable
    }
}

/// What a screen shows for the Apple Watch.
public enum WatchLevel: UInt8, Equatable, Sendable, Comparable {
    /// No watch with TwinKeys (nothing is shown).
    case absent = 0
    /// Paired with TwinKeys installed, but not reachable now (yellow).
    case notReachable = 1
    /// Reachable through the iPhone (green).
    case reachable = 2

    public static func < (a: WatchLevel, b: WatchLevel) -> Bool { a.rawValue < b.rawValue }

    /// Several iPhones: the best watch counts (one reachable watch is enough to use it).
    /// nil: an iPhone that does not report its watch (TwinKeys Remote before the connection display).
    public static func combined(_ states: [RemoteWatchState?]) -> WatchLevel {
        states.compactMap { $0?.level }.max() ?? .absent
    }
}

/// Connection display: a Mac's TwinKeys Remote side in short (approved iPhones connected to it and
/// their Apple Watch). The main Mac tells the backup with each heartbeat (packet `remoteSummary`).
public struct RemoteSummary: Equatable, Sendable {
    public var phones: Int
    public var watch: WatchLevel
    public init(phones: Int, watch: WatchLevel) { self.phones = phones; self.watch = watch }
}

/// Messages after the handshake.
public enum RemoteMessage: Codable, Equatable, Sendable {
    // iPhone → Mac
    case command(id: Int, LiveCommand)
    /// 2.2: a command plus the Live layout (`LiveSong.structure`) the iPhone was showing when it
    /// was tapped; the Mac refuses it if Live's layout has changed since.
    case commandAt(id: Int, LiveCommand, structure: Int?)
    /// 2.3: GO — launch `scene` on both Macs and select the next one. Never stopped by the show
    /// lock (it is the way to run the show while everything else is locked).
    case go(id: Int, scene: Int, structure: Int?)
    /// 2.3: the show lock with what it stops (`LockScope.rawValue`).
    case lockScope(on: Bool, scope: UInt8)
    /// 2.3: "make this Mac the main" (sent to the backup Mac after the main stopped answering).
    case becomeMain(id: Int)
    case cue(id: Int, keycode: UInt16)
    case allNotesOff(id: Int)
    /// Every 2 s (and right after `welcome`). `watch` (connection display): the iPhone's Apple Watch,
    /// also sent at once when it changes. It rides on the ping instead of being a message of its own
    /// because a Mac before 2.4 cannot decode a message case it does not know (it closes the
    /// connection; 2.4 skips it), while an extra key inside a known case is skipped: older Macs
    /// read this as a plain ping, and a ping from an older iPhone decodes with `watch` nil.
    case ping(Double, watch: RemoteWatchState? = nil)
    /// The iPhone's show lock changed (also sent right after `welcome`). While on, the Mac refuses
    /// commands that are not `LiveCommand.allowedWhileLocked` (result error "locked").
    case lock(Bool)
    // Mac → iPhone
    case waitingForApproval(code: String)
    /// `features` (TwinKeys 2.4+): the iPhone → Mac message kinds this Mac understands
    /// (`RemoteFeature`). Nil from TwinKeys 2.2.0 and older, which say nothing (an older iPhone
    /// skips the extra key).
    case welcome(macName: String, features: [String]? = nil)
    case denied
    case update(LiveUpdate)
    case status(RemoteStatus)
    /// `backup`: "delivered", "missing", "unconfirmed", "notLinked", "notSent"
    case result(id: Int, ok: Bool, error: String?, backup: String)
    case pong(Double)
}

/// Message kinds added after TwinKeys 2.1 that a Mac may or may not understand. A Mac on 2.1
/// cannot decode them and closes the connection, so the iPhone only sends them to a Mac that
/// understands them (`RemoteMacCompat`).
public enum RemoteFeature {
    public static let commandAt = "commandAt"
    public static let go = "go"
    public static let lockScope = "lockScope"
    public static let becomeMain = "becomeMain"
    /// The Mac skips a message it cannot decode instead of closing the connection (2.4+).
    public static let skipsUnknown = "skipsUnknown"
    /// What this version understands (sent in `welcome`).
    public static let all = [commandAt, go, lockScope, becomeMain, skipsUnknown]
}

/// What the Mac the iPhone is connected to understands, and how to say things to it.
///
/// - A Mac that lists its features in `welcome` (2.4+) gets exactly what it lists.
/// - A Mac that lists nothing is 2.2.0 (it understands everything 2.2 added) or 2.1 (it closes the
///   connection on the first new message). The iPhone cannot tell them apart from the welcome, so it
///   first assumes 2.2.0 and probes: the show lock (`lockScope`, always sent right after the welcome)
///   is followed by a ping. A 2.2.0 Mac answers the ping; a 2.1 Mac closes before reading it. Closed
///   while probing: `legacy`, and the iPhone reconnects using only what 2.1 understands.
public struct RemoteMacCompat: Equatable, Sendable {
    /// From `welcome`; nil when the Mac listed nothing.
    public var advertised: Set<String>?
    /// The Mac closed the connection while being probed: TwinKeys 2.1 or older.
    public var legacy: Bool
    public init(advertised: [String]?, legacy: Bool) {
        self.advertised = advertised.map(Set.init); self.legacy = legacy
    }

    /// The Mac listed nothing and has not shown yet that it is 2.2.0 or newer.
    public var needsProbe: Bool { advertised == nil && !legacy }

    public func understands(_ feature: String) -> Bool {
        if let advertised { return advertised.contains(feature) }
        return !legacy
    }

    /// What to send for `m`: the message itself, or the 2.1 form of it (nothing if there is none).
    /// `sceneCount`: scenes in Live (for GO: select the next scene only if there is one).
    public func translate(_ m: RemoteMessage, sceneCount: Int) -> [RemoteMessage] {
        switch m {
        case let .commandAt(id, cmd, _) where !understands(RemoteFeature.commandAt):
            return [.command(id: id, cmd)]
        case let .go(id, scene, _) where !understands(RemoteFeature.go):
            // Under a 2.1 Mac's show lock (tempo and mixer only) scene launches still run.
            var out: [RemoteMessage] = [.command(id: id, .fireScene(scene))]
            if scene + 1 < sceneCount { out.append(.command(id: id, .selectScene(scene + 1))) }
            return out
        case let .lockScope(on, _) where !understands(RemoteFeature.lockScope):
            return [.lock(on)]          // the 2.1 Mac locks tempo and mixer; the iPhone still keeps its own choice
        case .becomeMain where !understands(RemoteFeature.becomeMain):
            return []
        default:
            return [m]
        }
    }
}

/// Matching a Mac's name as the other Mac knows it (from its hello: cut to 32 UTF-8 bytes, control
/// characters removed) with the name it shows on Bonjour (the full name, "Name (2)" when another
/// device on the network already uses it).
public enum RemoteNames {
    public static func matches(bonjour: String, linkName: String) -> Bool {
        let link = linkName.trimmingCharacters(in: .whitespaces)
        guard !link.isEmpty else { return false }
        var candidates = [bonjour]
        // "Name (2)": Bonjour renamed it because the name was taken.
        if bonjour.hasSuffix(")"), let open = bonjour.range(of: " (", options: .backwards),
           bonjour[open.upperBound..<bonjour.index(before: bonjour.endIndex)].allSatisfy(\.isNumber) {
            candidates.append(String(bonjour[..<open.lowerBound]))
        }
        func clean(_ x: String) -> String {
            String(x.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }).trimmingCharacters(in: .whitespaces)
        }
        func cut(_ x: String) -> String { String(decoding: Array(truncatedUTF8(x, max: maxNameBytes)), as: UTF8.self) }
        // The hello carries the name cut to 32 bytes; the receiving Mac then cleans it.
        return candidates.contains { c in clean(c) == link || clean(cut(c)) == link || clean(cut(clean(c))) == link }
    }

    /// The Mac among `names` that is `linkName`: an exact match first, then a Bonjour-renamed or cut one.
    public static func find(_ linkName: String, in names: [String], excluding: String? = nil) -> String? {
        let pool = names.filter { $0 != excluding }
        return pool.first { $0 == linkName } ?? pool.first { matches(bonjour: $0, linkName: linkName) }
    }
}

public enum RemoteError: Error, Equatable {
    case frameTooLarge, badHello, wrongPairingCode, versionMismatch, badKey, decryptFailed, outOfOrder, notReady
}

/// One side of a connection. Feed received bytes with `receive`; send with `seal`.
public final class RemoteSession {
    public enum Role { case client, server }
    public enum Event: Equatable {
        /// Server: a device said hello and proved the pairing code. Decide whether it is approved.
        case clientHello(RemoteClientHello, confirmCode: String)
        /// Client: the Mac answered; the encrypted channel is ready.
        case serverHello(RemoteServerHello, confirmCode: String)
        case message(RemoteMessage)
    }

    public let role: Role
    private let pairingKey: SymmetricKey
    private var buffer: [UInt8] = []
    private var sendKey: SymmetricKey?
    private var receiveKey: SymmetricKey?
    private var sendCounter: UInt64 = 0
    private var receiveCounter: UInt64 = 0
    private var clientHelloBytes: [UInt8] = []
    // Client side
    private let deviceKey: Curve25519.KeyAgreement.PrivateKey?
    private var clientNonce: [UInt8] = []
    // Server side
    private var ephemeral: Curve25519.KeyAgreement.PrivateKey?
    public private(set) var peerHello: RemoteClientHello?

    public var isReady: Bool { sendKey != nil }

    /// Client (iPhone): `deviceKey` is kept in the keychain and never leaves the device.
    public init(clientWith pairing: PairingSecret, deviceKey: Curve25519.KeyAgreement.PrivateKey) {
        role = .client; pairingKey = pairing.key; self.deviceKey = deviceKey
    }

    /// Server (Mac).
    public init(serverWith pairing: PairingSecret) {
        role = .server; pairingKey = pairing.key; deviceKey = nil
    }

    // MARK: Handshake

    /// Client: the first bytes to send.
    public func clientHello(deviceID: String, deviceName: String) -> [UInt8] {
        precondition(role == .client)
        clientNonce = SecureChannel.randomNonce()
        let hello = RemoteClientHello(version: RemoteProtocol.version, deviceID: deviceID, deviceName: String(deviceName.prefix(64)),
                                      devicePublicKey: deviceKey!.publicKey.rawRepresentation, nonce: Data(clientNonce))
        let json = Array((try? JSONEncoder().encode(hello)) ?? Data())
        clientHelloBytes = json
        return Self.frame(json + tag(json))
    }

    /// Server: answer to a client hello (call after `.clientHello`).
    public func serverHello(serverID: String, serverName: String) throws -> [UInt8] {
        guard role == .server, let ch = peerHello else { throw RemoteError.notReady }
        let eph = Curve25519.KeyAgreement.PrivateKey()
        ephemeral = eph
        let sh = RemoteServerHello(version: RemoteProtocol.version, serverID: serverID, serverName: String(serverName.prefix(64)),
                                   ephemeralPublicKey: eph.publicKey.rawRepresentation, nonce: Data(SecureChannel.randomNonce()))
        let json = Array(try JSONEncoder().encode(sh))
        let devicePub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ch.devicePublicKey)
        try deriveKeys(shared: eph.sharedSecretFromKeyAgreement(with: devicePub), serverHello: json)
        return Self.frame(json + tag(clientHelloBytes + json))
    }

    // MARK: Messages

    public func seal(_ m: RemoteMessage) throws -> [UInt8] {
        try seal(json: JSONEncoder().encode(m))
    }

    /// Seals any JSON (tests use it to send a message kind this version does not know).
    func seal(json plain: Data) throws -> [UInt8] {
        guard let key = sendKey else { throw RemoteError.notReady }
        sendCounter += 1
        let nonceBytes = Self.nonce(sendCounter)
        let box = try ChaChaPoly.seal(plain, using: key, nonce: ChaChaPoly.Nonce(data: nonceBytes))
        return Self.frame(Array(nonceBytes.prefix(8)) + Array(box.ciphertext) + Array(box.tag))
    }

    /// Feed bytes from the stream. Throws when the connection must be closed.
    public func receive(_ bytes: [UInt8]) throws -> [Event] {
        buffer += bytes
        var events: [Event] = []
        while buffer.count >= 4 {
            let len = Int(buffer[0]) << 24 | Int(buffer[1]) << 16 | Int(buffer[2]) << 8 | Int(buffer[3])
            guard len <= RemoteProtocol.maxFrame else { throw RemoteError.frameTooLarge }
            guard buffer.count >= 4 + len else { break }
            let payload = Array(buffer[4..<(4 + len)])
            buffer.removeFirst(4 + len)
            if let e = try handle(payload) { events.append(e) }
        }
        return events
    }

    private func handle(_ p: [UInt8]) throws -> Event? {
        if let key = receiveKey {
            guard p.count >= 8 + 16 else { throw RemoteError.decryptFailed }
            let counter = p[0..<8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            guard counter > receiveCounter else { throw RemoteError.outOfOrder }
            let nonceBytes = Self.nonce(counter)
            guard let box = try? ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonceBytes),
                                                       ciphertext: p[8..<(p.count - 16)], tag: p[(p.count - 16)...]),
                  let plain = try? ChaChaPoly.open(box, using: key) else { throw RemoteError.decryptFailed }
            receiveCounter = counter
            // An authentic message of a kind this version does not know (from a newer peer): skipped,
            // the connection stays. Crypto failures above still close it.
            guard let m = try? JSONDecoder().decode(RemoteMessage.self, from: plain) else { return nil }
            return .message(m)
        }
        guard p.count > RemoteProtocol.tagSize else { throw RemoteError.badHello }
        let json = Array(p.dropLast(RemoteProtocol.tagSize)), t = Array(p.suffix(RemoteProtocol.tagSize))
        switch role {
        case .server:
            guard Self.equal(tag(json), t) else { throw RemoteError.wrongPairingCode }
            guard let ch = try? JSONDecoder().decode(RemoteClientHello.self, from: Data(json)) else { throw RemoteError.badHello }
            guard ch.version == RemoteProtocol.version else { throw RemoteError.versionMismatch }
            guard ch.devicePublicKey.count == 32, ch.nonce.count == 16, !ch.deviceID.isEmpty, ch.deviceID.count <= 64 else { throw RemoteError.badHello }
            var hello = ch
            hello.deviceName = RemoteClientHello.sanitizedName(ch.deviceName)
            clientHelloBytes = json
            peerHello = hello
            return .clientHello(hello, confirmCode: Self.confirmCode(json))
        case .client:
            guard Self.equal(tag(clientHelloBytes + json), t) else { throw RemoteError.wrongPairingCode }
            guard let sh = try? JSONDecoder().decode(RemoteServerHello.self, from: Data(json)) else { throw RemoteError.badHello }
            guard sh.version == RemoteProtocol.version else { throw RemoteError.versionMismatch }
            guard let pub = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: sh.ephemeralPublicKey) else { throw RemoteError.badKey }
            try deriveKeys(shared: deviceKey!.sharedSecretFromKeyAgreement(with: pub), serverHello: json)
            return .serverHello(sh, confirmCode: Self.confirmCode(clientHelloBytes))
        }
    }

    private func deriveKeys(shared: SharedSecret, serverHello: [UInt8]) throws {
        let salt = pairingKey.withUnsafeBytes { Data($0) }
        let info = Data("TwinKeys remote v1".utf8) + Data(SHA256.hash(data: clientHelloBytes + serverHello))
        let km = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: info, outputByteCount: 64)
        let bytes = km.withUnsafeBytes { Array($0) }
        let c2s = SymmetricKey(data: bytes[0..<32]), s2c = SymmetricKey(data: bytes[32..<64])
        if role == .client { sendKey = c2s; receiveKey = s2c } else { sendKey = s2c; receiveKey = c2s }
    }

    private func tag(_ data: [UInt8]) -> [UInt8] {
        Array(HMAC<SHA256>.authenticationCode(for: Array("remote".utf8) + data, using: pairingKey))
    }

    /// 4 digits both sides show while the Mac asks for approval (same for the same client hello).
    static func confirmCode(_ clientHello: [UInt8]) -> String {
        let h = Array(SHA256.hash(data: clientHello))
        let n = (UInt32(h[0]) << 24 | UInt32(h[1]) << 16 | UInt32(h[2]) << 8 | UInt32(h[3])) % 10000
        return String(format: "%04d", n)
    }

    static func nonce(_ counter: UInt64) -> [UInt8] {
        withUnsafeBytes(of: counter.bigEndian) { Array($0) } + [0, 0, 0, 0]
    }

    static func frame(_ payload: [UInt8]) -> [UInt8] {
        let n = UInt32(payload.count)
        return [UInt8(n >> 24), UInt8((n >> 16) & 0xFF), UInt8((n >> 8) & 0xFF), UInt8(n & 0xFF)] + payload
    }

    static func equal(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        guard a.count == b.count else { return false }
        var d: UInt8 = 0
        for i in a.indices { d |= a[i] ^ b[i] }
        return d == 0
    }
}

/// Mac side: when to ask the person to approve a new device. At most one question at a time, each
/// with a time limit, and after "Don't Allow", no answer, or the device leaving while asked, that
/// device id is refused without asking for `coolDown` seconds. So a device that keeps reconnecting
/// cannot keep putting alerts on the screen during a show. Times are any monotonic seconds.
public struct RemoteApprovalGate {
    public static let timeout: Double = 60
    public static let coolDown: Double = 60

    public enum Decision: Equatable {
        /// Ask the person; answer with `finish(token:…)`.
        case ask(token: Int)
        /// Another question is open: refuse this connection without asking.
        case busy
        /// This device was refused a moment ago: refuse without asking.
        case coolingDown
    }

    private var open: (token: Int, deviceID: String, since: Double)?
    private var refusedAt: [String: Double] = [:]
    private var lastToken = 0

    public init() {}

    /// The token of the open question, if any.
    public var openToken: Int? { open?.token }

    public mutating func request(deviceID: String, now: Double) -> Decision {
        if let t = refusedAt[deviceID] {
            if now - t < Self.coolDown { return .coolingDown }
            refusedAt[deviceID] = nil
        }
        if let o = open {
            if now - o.since < Self.timeout { return .busy }
            finish(token: o.token, allowed: false, now: now)     // ran out of time (missed timer)
        }
        lastToken += 1
        open = (lastToken, deviceID, now)
        return .ask(token: lastToken)
    }

    /// The question `token` ended: allowed, refused, timed out or the device left. Returns false
    /// when it is not the open question any more (an old answer must then be ignored).
    @discardableResult
    public mutating func finish(token: Int, allowed: Bool, now: Double) -> Bool {
        guard let o = open, o.token == token else { return false }
        open = nil
        if !allowed {
            if refusedAt.count > 200 { refusedAt = refusedAt.filter { now - $0.value < Self.coolDown } }
            refusedAt[o.deviceID] = now
        }
        return true
    }

    /// Is `token` the open question and past its time limit?
    public func isExpired(token: Int, now: Double) -> Bool {
        guard let o = open, o.token == token else { return false }
        return now - o.since >= Self.timeout
    }
}

/// An iPhone the Mac allowed (stored in settings; the public key binds the approval to that device).
public struct ApprovedDevice: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var publicKey: Data
    public var approvedAt: Date
    public init(id: String, name: String, publicKey: Data, approvedAt: Date = Date()) {
        self.id = id; self.name = name; self.publicKey = publicKey; self.approvedAt = approvedAt
    }

    /// Approved only if both the id and the key match (a device cannot take over another's approval).
    public static func isApproved(_ hello: RemoteClientHello, in list: [ApprovedDevice]) -> Bool {
        list.contains { $0.id == hello.deviceID && RemoteSession.equal(Array($0.publicKey), Array(hello.devicePublicKey)) }
    }
}
