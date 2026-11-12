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
    case cue(id: Int, keycode: UInt16)
    case allNotesOff(id: Int)
    case ping(Double)
    /// The iPhone's show lock changed (also sent right after `welcome`). While on, the Mac refuses
    /// commands that are not `LiveCommand.allowedWhileLocked` (result error "locked").
    case lock(Bool)
    // Mac → iPhone
    case waitingForApproval(code: String)
    case welcome(macName: String)
    case denied
    case update(LiveUpdate)
    case status(RemoteStatus)
    /// `backup`: "delivered", "missing", "unconfirmed", "notLinked", "notSent"
    case result(id: Int, ok: Bool, error: String?, backup: String)
    case pong(Double)
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
        guard let key = sendKey else { throw RemoteError.notReady }
        sendCounter += 1
        let nonceBytes = Self.nonce(sendCounter)
        let plain = try JSONEncoder().encode(m)
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
            events.append(try handle(payload))
        }
        return events
    }

    private func handle(_ p: [UInt8]) throws -> Event {
        if let key = receiveKey {
            guard p.count >= 8 + 16 else { throw RemoteError.decryptFailed }
            let counter = p[0..<8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            guard counter > receiveCounter else { throw RemoteError.outOfOrder }
            let nonceBytes = Self.nonce(counter)
            guard let box = try? ChaChaPoly.SealedBox(nonce: ChaChaPoly.Nonce(data: nonceBytes),
                                                       ciphertext: p[8..<(p.count - 16)], tag: p[(p.count - 16)...]),
                  let plain = try? ChaChaPoly.open(box, using: key) else { throw RemoteError.decryptFailed }
            receiveCounter = counter
            return .message(try JSONDecoder().decode(RemoteMessage.self, from: plain))
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
