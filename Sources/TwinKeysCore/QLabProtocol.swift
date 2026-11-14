import Foundation

// QLab 5's OSC dictionary, the part TwinKeys uses (docs/design-qlab.md 3.1):
// https://qlab.app/docs/v5/scripting/osc-dictionary-v5/

public enum QLabOSCAddress {
    /// Every command goes to one workspace: without `/workspace/{id}` QLab 5 sends it to every
    /// workspace on the port (design 10, "two workspaces open").
    public static func ws(_ id: String, _ path: String) -> String { "/workspace/\(id)/\(path)" }

    public static let version = "/version"
    public static let workspaces = "/workspaces"
    public static func connect(_ ws: String) -> String { Self.ws(ws, "connect") }
    public static func alwaysReply(_ ws: String) -> String { Self.ws(ws, "alwaysReply") }
    public static func updates(_ ws: String) -> String { Self.ws(ws, "updates") }
    public static func thump(_ ws: String) -> String { Self.ws(ws, "thump") }
    public static func go(_ ws: String) -> String { Self.ws(ws, "go") }
    public static func goCueID(_ ws: String, _ uid: String) -> String { Self.ws(ws, "cue_id/\(uid)/go") }
    public static func panic(_ ws: String) -> String { Self.ws(ws, "panic") }
    public static func hardStop(_ ws: String) -> String { Self.ws(ws, "hardStop") }
    public static func pause(_ ws: String) -> String { Self.ws(ws, "pause") }
    public static func resume(_ ws: String) -> String { Self.ws(ws, "resume") }
    public static func playheadNext(_ ws: String) -> String { Self.ws(ws, "playhead/next") }
    public static func playheadPrevious(_ ws: String) -> String { Self.ws(ws, "playhead/previous") }
    public static func playheadID(_ ws: String, _ uid: String) -> String { Self.ws(ws, "playheadID/\(uid)") }
    public static func cueLists(_ ws: String) -> String { Self.ws(ws, "cueLists") }
    public static func runningOrPaused(_ ws: String) -> String { Self.ws(ws, "runningOrPausedCues/shallow") }
    public static func valuesForKeys(_ ws: String, _ uid: String) -> String { Self.ws(ws, "cue_id/\(uid)/valuesForKeys") }
    public static func playheadUniqueID(_ ws: String) -> String { Self.ws(ws, "cue/playhead/uniqueID") }
    public static func showMode(_ ws: String) -> String { Self.ws(ws, "showMode") }
}

/// `/reply/{address} "{json}"`: `{ "workspace_id": …, "address": …, "status": "ok" | "error" | "denied", "data": … }`.
public struct QLabReply {
    public var address: String
    public var workspaceID: String?
    public var status: String
    public var data: Any?

    public init(address: String, workspaceID: String?, status: String, data: Any?) {
        self.address = address; self.workspaceID = workspaceID; self.status = status; self.data = data
    }

    public init?(_ m: OSCMessage) {
        guard m.address.hasPrefix("/reply/") || m.address == "/reply" else { return nil }
        let fromAddress = String(m.address.dropFirst("/reply".count))
        guard let json = m.arguments.first?.stringValue,
              let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed]) as? [String: Any] else {
            // A reply without JSON: only the address is known.
            self.init(address: fromAddress, workspaceID: nil, status: "ok", data: nil)
            return
        }
        self.init(address: (obj["address"] as? String) ?? fromAddress, workspaceID: obj["workspace_id"] as? String,
                  status: (obj["status"] as? String) ?? "ok", data: obj["data"])
    }

    public var string: String? { data as? String }
}

/// A change QLab reports after `/updates 1` (design 3.1).
public enum QLabUpdate: Equatable, Sendable {
    /// Read the cue lists again.
    case workspace(String)
    case cue(workspace: String, cue: String)
    /// The playhead of a cue list moved (nil: no cue standing by).
    case playbackPosition(workspace: String, list: String, cue: String?)
    /// The workspace is closing.
    case disconnect(String)

    public init?(_ m: OSCMessage) {
        let parts = m.address.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3, parts[0] == "update", parts[1] == "workspace" else { return nil }
        let ws = parts[2]
        if parts.count == 3 { self = .workspace(ws); return }
        switch parts[3] {
        case "disconnect" where parts.count == 4: self = .disconnect(ws)
        case "cue_id" where parts.count == 5: self = .cue(workspace: ws, cue: parts[4])
        case "cueList" where parts.count == 6 && parts[5] == "playbackPosition":
            let id = m.arguments.first?.stringValue
            self = .playbackPosition(workspace: ws, list: parts[4], cue: (id?.isEmpty ?? true) ? nil : id)
        case "dashboard", "settings", "lightDashboard":
            return nil
        default:
            return nil
        }
    }
}

public struct QLabWorkspaceInfo: Equatable, Sendable, Codable {
    public var uniqueID: String
    public var displayName: String
    public var version: String?
    public init(uniqueID: String, displayName: String, version: String? = nil) {
        self.uniqueID = uniqueID; self.displayName = displayName; self.version = version
    }
}

/// One cue list from `/cueLists`, its cues flattened.
public struct QLabCueListInfo: Equatable, Sendable {
    public var uniqueID: String
    public var name: String
    public var cues: [QLabCue]
}

public enum QLabParse {
    public static func workspaces(_ data: Any?) -> [QLabWorkspaceInfo] {
        guard let list = data as? [[String: Any]] else { return [] }
        return list.compactMap { w in
            guard let id = w["uniqueID"] as? String else { return nil }
            return QLabWorkspaceInfo(uniqueID: id, displayName: (w["displayName"] as? String) ?? id, version: w["version"] as? String)
        }
    }

    /// `/cueLists`: [{ uniqueID, number, name, listName, type, colorName, cues: […] }].
    public static func cueLists(_ data: Any?) -> [QLabCueListInfo] {
        guard let lists = data as? [[String: Any]] else { return [] }
        return lists.map { l in
            var out: [QLabCue] = []
            flatten((l["cues"] as? [[String: Any]]) ?? [], depth: 0, into: &out)
            let name = (l["listName"] as? String) ?? (l["name"] as? String) ?? ""
            return QLabCueListInfo(uniqueID: (l["uniqueID"] as? String) ?? "", name: name, cues: out)
        }
    }

    static func flatten(_ cues: [[String: Any]], depth: Int, into out: inout [QLabCue]) {
        for c in cues {
            guard let id = c["uniqueID"] as? String else { continue }
            let name = (c["listName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? (c["name"] as? String) ?? ""
            out.append(QLabCue(uniqueID: id, number: (c["number"] as? String) ?? "", name: name,
                               type: QLabCueType(qlab: (c["type"] as? String) ?? ""),
                               duration: number(c["duration"]) ?? number(c["currentDuration"]),
                               colorName: c["colorName"] as? String, depth: depth))
            if depth < 8, let sub = c["cues"] as? [[String: Any]] { flatten(sub, depth: depth + 1, into: &out) }
        }
    }

    /// `runningOrPausedCues/shallow`: the cues' uniqueIDs (also accepts plain strings).
    public static func cueIDs(_ data: Any?) -> [String] {
        if let ids = data as? [String] { return ids }
        guard let list = data as? [[String: Any]] else { return [] }
        return list.compactMap { $0["uniqueID"] as? String }
    }

    public static func number(_ v: Any?) -> Double? {
        if let d = v as? Double { return d }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    public static func bool(_ v: Any?) -> Bool? {
        if let b = v as? Bool { return b }
        if let n = v as? NSNumber { return n.intValue != 0 }
        if let s = v as? String { return ["1", "true", "yes"].contains(s.lowercased()) }
        return nil
    }
}
