#!/usr/bin/env python3
"""A small fake QLab for trying and testing TwinKeys' QLab mode (docs/design-qlab.md 8.2) without a
Mac running QLab. Standard library only.

This is not Figure 53's software and does not behave like QLab in every detail: it answers the
part of the QLab 5 OSC dictionary that TwinKeys uses, with made-up timing and simplified groups.

It listens for OSC on TCP (SLIP framing, OSC 1.1) and UDP on the same port (53000 by default; UDP
replies go to the sender's address, port 53001). Replies are `/reply/{address} "{json}"` with
`workspace_id`, `address`, `status` ("ok" / "error" / "denied") and `data`.

    /version, /workspaces
    /workspace/{id}/connect [passcode]      -> "ok" or "badpass" (each wrong try makes the next wait longer)
    /workspace/{id}/alwaysReply 1|0, /updates 1|0, /thump
    /workspace/{id}/go ["13"], /go/{number}, /cue/{number}/go, /cue_id/{id}/go
    /workspace/{id}/panic (again while fading: stop now), /panicInTime, /hardStop, /stop, /pause, /resume
    /workspace/{id}/playhead/next|previous|{number}, /playheadID/{id}
    /workspace/{id}/cueLists, /runningOrPausedCues[/shallow], /runningCues, /showMode
    /workspace/{id}/cue/playhead/uniqueID|number|displayName
    /workspace/{id}/cue_id/{id}/valuesForKeys "[\"currentDuration\",\"actionElapsed\"]", and single keys
With `/updates 1` it sends /update/workspace/{id}, /cue_id/{id}, /cueList/{list}/playbackPosition {id}
and /disconnect.

Permissions: passcodes per workspace ("1234": view, edit and control; "5678": view only by
default); without a passcode, the workspace's "No Passcode" permissions (none by default).
Commands without the permission get status "denied". `/stop` needs "edit" (as the dictionary's
table says). Without `/alwaysReply 1`, commands that change things (go, panic …) do not reply.

Every action prints a line `EVENT <what> <cue number>` on stdout (tests read them).

Usage:
    python3 scripts/fake-qlab.py                        # TCP and UDP 53000, the sample show
    python3 scripts/fake-qlab.py --port 53100 --no-udp --cues my-show.json
    python3 scripts/fake-qlab.py --two-workspaces       # a second workspace open
    python3 scripts/fake-qlab.py --silent               # OSC Access off: never answers
    python3 scripts/fake-qlab.py --delay 0.5            # answers late

While it runs, type on its terminal:
    go           GO (as if pressed on the Mac)
    next / prev  move the playhead
    move 15      move the playhead to cue 15
    show         the playhead and the running cues
    drop         close every TCP connection
    mute         stop answering (again to answer again)
    close        tell the clients the workspace is closing (/update/.../disconnect)
    quit
"""

import argparse
import json
import socket
import struct
import sys
import threading
import time

END, ESC, ESC_END, ESC_ESC = 0xC0, 0xDB, 0xDC, 0xDD

# ---------------------------------------------------------------- OSC and SLIP


def _pad(b):
    b = b + b"\0"
    return b + b"\0" * (-len(b) % 4)


def osc_encode(address, args=()):
    tags = ","
    data = b""
    for a in args:
        if isinstance(a, bool):
            tags += "T" if a else "F"
        elif isinstance(a, int):
            tags += "i"
            data += struct.pack(">i", a)
        elif isinstance(a, float):
            tags += "f"
            data += struct.pack(">f", a)
        else:
            tags += "s"
            data += _pad(str(a).encode("utf-8"))
    return _pad(address.encode("utf-8")) + _pad(tags.encode()) + data


def _read_string(b, i):
    end = b.index(b"\0", i)
    s = b[i:end].decode("utf-8", "replace")
    n = end + 1
    n += -(n - i) % 4
    return s, n


def osc_decode(b):
    """(address, [args]) or None."""
    try:
        address, i = _read_string(b, 0)
        if not address.startswith("/"):
            return None
        if i >= len(b):
            return address, []
        tags, i = _read_string(b, i)
        args = []
        for t in tags[1:]:
            if t == "s":
                s, i = _read_string(b, i)
                args.append(s)
            elif t == "i":
                args.append(struct.unpack(">i", b[i:i + 4])[0])
                i += 4
            elif t == "f":
                args.append(struct.unpack(">f", b[i:i + 4])[0])
                i += 4
            elif t == "T":
                args.append(True)
            elif t == "F":
                args.append(False)
            else:
                return None
        return address, args
    except (ValueError, struct.error, IndexError):
        return None


def slip_encode(packet):
    out = bytearray([END])
    for c in packet:
        if c == END:
            out += bytes([ESC, ESC_END])
        elif c == ESC:
            out += bytes([ESC, ESC_ESC])
        else:
            out.append(c)
    out.append(END)
    return bytes(out)


class SlipDecoder:
    def __init__(self):
        self.buf = bytearray()
        self.esc = False

    def feed(self, data):
        out = []
        for c in data:
            if c == END:
                if self.buf:
                    out.append(bytes(self.buf))
                self.buf = bytearray()
                self.esc = False
            elif self.esc:
                self.esc = False
                self.buf.append(END if c == ESC_END else ESC if c == ESC_ESC else c)
            elif c == ESC:
                self.esc = True
            else:
                self.buf.append(c)
        return out


# ---------------------------------------------------------------- The show (fictional names only)

SAMPLE = {
    "workspaces": [{
        "uniqueID": "8B1C5A3E-0000-4000-8000-00000000A001",
        "displayName": "sample-show",
        "passcodes": {"1234": ["view", "edit", "control"], "5678": ["view"]},
        "noPasscode": [],
        "showMode": True,
        "cueLists": [{
            "uniqueID": "LIST-MAIN",
            "name": "Main",
            "cues": [
                {"number": "1", "name": "開演前の確認", "type": "Memo"},
                {"number": "2", "name": "客入れ BGM", "type": "Audio", "duration": 1080},
                {"number": "3", "name": "客入れ BGM フェードアウト", "type": "Fade", "duration": 8},
                {"number": "4", "name": "開演ベル", "type": "Audio", "duration": 6},
                {"number": "10", "name": "第1場", "type": "Group", "cues": [
                    {"number": "11", "name": "鳥の声（朝）", "type": "Audio", "duration": 90},
                    {"number": "11.5", "name": "夜の環境音（ループ）", "type": "Audio", "duration": 0},
                    {"number": "12", "name": "雨の音（遠く）", "type": "Audio", "duration": 200},
                    {"number": "13", "name": "雷鳴 1", "type": "Audio", "duration": 12},
                    {"number": "14", "name": "雨 フェードアウト", "type": "Fade", "duration": 5},
                ]},
                {"number": "15", "name": "映像へ合図", "type": "Network"},
                {"number": "90", "name": "雷（予備）", "type": "Audio", "duration": 4},
            ],
        }],
    }],
}

SECOND_WORKSPACE = {
    "uniqueID": "8B1C5A3E-0000-4000-8000-00000000B002",
    "displayName": "rehearsal",
    "passcodes": {"1234": ["view", "edit", "control"]},
    "noPasscode": [],
    "showMode": False,
    "cueLists": [{"uniqueID": "LIST-R", "name": "Main", "cues": [{"number": "1", "name": "テスト音", "type": "Audio", "duration": 3}]}],
}

NEEDS = {  # the permission each command needs (the dictionary's table; /stop: edit)
    "go": "control", "panic": "control", "panicInTime": "control", "hardStop": "control", "stop": "edit",
    "pause": "control", "resume": "control", "playhead": "control", "playheadID": "control", "reset": "control",
}


class Workspace:
    def __init__(self, spec, uid_counter):
        self.id = spec["uniqueID"]
        self.name = spec["displayName"]
        self.passcodes = {k: set(v) for k, v in spec.get("passcodes", {}).items()}
        self.no_passcode = set(spec.get("noPasscode", []))
        self.show_mode = bool(spec.get("showMode", False))
        self.lists = []
        self.flat = []          # every cue: dict with uid, number, name, type, duration, depth, list, parent, children
        for lst in spec.get("cueLists", []):
            cues = []
            self.lists.append({"uniqueID": lst.get("uniqueID", "LIST-%d" % len(self.lists)), "name": lst.get("name", "Main"), "cues": cues})
            self._add(lst.get("cues", []), 0, cues, self.lists[-1]["uniqueID"], None, uid_counter)
        self.playhead = 0 if self.flat else None    # index into flat
        self.running = {}       # uid -> {"start": t, "paused_at": t or None, "fade_until": t or None}
        self.panic_until = None

    def _add(self, cues, depth, into, list_id, parent, counter):
        for c in cues:
            counter[0] += 1
            cue = {"uid": c.get("uniqueID", "CUE-%04d" % counter[0]), "number": str(c.get("number", "")), "name": c.get("name", ""),
                   "type": c.get("type", "Audio"), "duration": c.get("duration"), "depth": depth, "list": list_id,
                   "parent": parent, "children": []}
            self.flat.append(cue)
            into.append(cue)
            self._add(c.get("cues", []), depth + 1, cue["children"], list_id, cue, counter)

    # -------- lookups
    def by_number(self, n):
        return next((c for c in self.flat if c["number"] == n and n != ""), None)

    def by_uid(self, u):
        return next((c for c in self.flat if c["uid"] == u), None)

    def playhead_cue(self):
        return self.flat[self.playhead] if self.playhead is not None and self.playhead < len(self.flat) else None

    def index(self, cue):
        return self.flat.index(cue)

    def json_cue(self, c):
        d = {"uniqueID": c["uid"], "number": c["number"], "name": c["name"], "listName": c["name"], "type": c["type"],
             "colorName": "none", "flagged": False, "armed": True}
        if c["type"] == "Group":
            d["cues"] = [self.json_cue(x) for x in c["children"]]
        return d

    def cue_lists(self):
        return [{"uniqueID": l["uniqueID"], "number": "", "name": l["name"], "listName": l["name"], "type": "Cue List",
                 "cues": [self.json_cue(c) for c in l["cues"]]} for l in self.lists]

    def elapsed(self, uid, now):
        r = self.running[uid]
        end = r["paused_at"] if r["paused_at"] is not None else now
        return max(0.0, end - r["start"])


class FakeQLab:
    """The whole fake, without sockets: `handle` takes one message from a client and returns what to send."""

    def __init__(self, spec, connect_permissions=False):
        counter = [0]
        self.workspaces = [Workspace(w, counter) for w in spec["workspaces"]]
        self.connect_permissions = connect_permissions
        self.lock = threading.RLock()
        self.clients = {}        # client -> {"ws": {id: perms}, "always": bool, "updates": bool, "fails": int}
        self.out = []            # (client, address, args) queued updates for other clients
        self.events = []

    def client(self, c):
        return self.clients.setdefault(c, {"ws": {}, "always": False, "updates": False, "fails": 0})

    def event(self, what, cue=None):
        line = "EVENT %s%s" % (what, "" if cue is None else " " + (cue["number"] or cue["uid"]))
        self.events.append(line)
        print(line, flush=True)

    def reply(self, ws, address, status="ok", data=None):
        d = {"workspace_id": ws.id if ws else None, "address": address, "status": status}
        if data is not None:
            d["data"] = data
        if ws is None:
            del d["workspace_id"]
        return ("/reply" + address, [json.dumps(d, ensure_ascii=False)])

    def update(self, ws, path, args=()):
        for c, st in self.clients.items():
            if st["updates"] and ws.id in st["ws"]:
                self.out.append((c, "/update/workspace/%s%s" % (ws.id, path), list(args)))

    def playhead_moved(self, ws):
        cue = ws.playhead_cue()
        lst = cue["list"] if cue else (ws.lists[0]["uniqueID"] if ws.lists else "")
        self.update(ws, "/cueList/%s/playbackPosition" % lst, [cue["uid"]] if cue else [])

    # -------- the show
    def start(self, ws, cue, now):
        ws.running[cue["uid"]] = {"start": now, "paused_at": None}
        self.event("go", cue)
        self.update(ws, "/cue_id/%s" % cue["uid"])
        for child in cue["children"]:
            self.start(ws, child, now)
        # The playhead goes to the cue after this one (after a group's cues).
        i = ws.index(cue) + 1
        while i < len(ws.flat) and ws.flat[i]["depth"] > cue["depth"]:
            i += 1
        ws.playhead = i if i < len(ws.flat) else None
        self.playhead_moved(ws)

    def stop_all(self, ws, why):
        for uid in list(ws.running):
            del ws.running[uid]
            self.update(ws, "/cue_id/%s" % uid)
        ws.panic_until = None
        self.event(why)

    def tick(self, now):
        """Cues end after their duration; a panic fade ends."""
        with self.lock:
            for ws in self.workspaces:
                if ws.panic_until is not None and now >= ws.panic_until:
                    self.stop_all(ws, "panicDone")
                for uid in list(ws.running):
                    c = ws.by_uid(uid)
                    d = c["duration"]
                    if c["type"] == "Group":
                        if not any(x["uid"] in ws.running for x in c["children"]):
                            del ws.running[uid]
                            self.update(ws, "/cue_id/%s" % uid)
                        continue
                    if d == 0 and c["type"] in ("Audio", "Video"):
                        continue        # a loop: runs until stopped
                    if ws.elapsed(uid, now) >= (d or 0.05):
                        del ws.running[uid]
                        self.update(ws, "/cue_id/%s" % uid)

    def move(self, ws, cue):
        ws.playhead = ws.index(cue) if cue else None
        self.event("playhead", cue)
        self.playhead_moved(ws)

    # -------- messages
    def handle(self, c, address, args, now=None):
        """Returns the replies (address, args) for this client; updates for others go to self.out."""
        now = time.monotonic() if now is None else now
        with self.lock:
            st = self.client(c)
            r = self._handle(st, address, args, now)
            return [r] if r else []

    def _handle(self, st, address, args, now):
        if address == "/version":
            return self.reply(None, address, data="5.6.5")
        if address == "/workspaces":
            return self.reply(None, address, data=[{"uniqueID": w.id, "displayName": w.name, "hasPasscode": bool(w.passcodes),
                                                     "port": 53000, "udpReplyPort": 53001, "version": "5.6.5"} for w in self.workspaces])
        parts = [p for p in address.split("/") if p]
        if len(parts) < 3 or parts[0] != "workspace":
            return self.reply(None, address, "error")
        ws = next((w for w in self.workspaces if w.id == parts[1] or w.name == parts[1]), None)
        if ws is None:
            return self.reply(None, address, "error")
        cmd, rest = parts[2], parts[3:]
        if cmd == "connect":
            code = str(args[0]) if args else None
            perms = ws.passcodes.get(code) if code is not None else ws.no_passcode
            if not perms:
                st["fails"] += 1
                # Each wrong try in a row waits longer (QLab does the same).
                time.sleep(min(2.0, 0.05 * (2 ** (st["fails"] - 1))) if st["fails"] > 1 else 0)
                return self.reply(ws, address, data="badpass")
            st["fails"] = 0
            st["ws"][ws.id] = set(perms)
            self.event("connect")
            data = "ok"
            if self.connect_permissions:
                data = "ok:" + "|".join(p for p in ("view", "edit", "control") if p in perms)
            return self.reply(ws, address, data=data)
        perms = st["ws"].get(ws.id)
        if perms is None:
            return self.reply(ws, address, "denied")
        if cmd == "alwaysReply":
            st["always"] = bool(args and args[0])
            return self.reply(ws, address)
        if cmd == "updates":
            st["updates"] = bool(args and args[0])
            return self.reply(ws, address)
        if cmd == "thump":
            return self.reply(ws, address, data="thump")
        if cmd == "disconnect":
            st["ws"].pop(ws.id, None)
            return self.reply(ws, address)
        need = NEEDS.get(cmd)
        if cmd == "cue" or cmd == "cue_id":
            need = "control" if rest[-1:] in (["go"], ["start"], ["stop"], ["panic"]) else "view"
        if need is None:
            need = "view"
        if need not in perms:
            return self.reply(ws, address, "denied")
        changes = need != "view"
        r = self._run(ws, cmd, rest, args, address, now)
        if r is None:
            return None
        status, data = r
        if changes and not st["always"] and status == "ok":
            return None         # commands do not answer without /alwaysReply 1
        return self.reply(ws, address, status, data)

    def _run(self, ws, cmd, rest, args, address, now):
        if cmd == "go":
            target = rest[0] if rest else (str(args[0]) if args else None)
            cue = ws.by_number(target) if target else ws.playhead_cue()
            if cue is None:
                return ("error", None)
            self.start(ws, cue, now)
            return ("ok", None)
        if cmd in ("panic", "panicInTime"):
            if ws.panic_until is not None:
                self.stop_all(ws, "panicNow")
            elif ws.running:
                ws.panic_until = now + (float(args[0]) if cmd == "panicInTime" and args else 0.5)
                self.event("panic")
            else:
                self.event("panic")
            return ("ok", None)
        if cmd in ("hardStop", "stop", "reset"):
            self.stop_all(ws, cmd)
            if cmd == "reset" and ws.flat:
                self.move(ws, ws.flat[0])
            return ("ok", None)
        if cmd in ("pause", "resume"):
            for r in ws.running.values():
                if cmd == "pause" and r["paused_at"] is None:
                    r["paused_at"] = now
                elif cmd == "resume" and r["paused_at"] is not None:
                    r["start"] += now - r["paused_at"]
                    r["paused_at"] = None
            self.event(cmd)
            return ("ok", None)
        if cmd == "playhead":
            if not rest:
                return ("error", None)
            i = ws.playhead if ws.playhead is not None else len(ws.flat)
            if rest[0] == "next":
                cue = ws.flat[min(i + 1, len(ws.flat) - 1)] if ws.flat else None
            elif rest[0] == "previous":
                cue = ws.flat[max(i - 1, 0)] if ws.flat else None
            else:
                cue = ws.by_number(rest[0])
                if cue is None:
                    return ("error", None)
            self.move(ws, cue)
            return ("ok", None)
        if cmd == "playheadID":
            cue = ws.by_uid(rest[0] if rest else (str(args[0]) if args else ""))
            if cue is None:
                return ("error", None)
            if cue is not ws.playhead_cue():
                self.move(ws, cue)
            return ("ok", None)
        if cmd == "cueLists":
            return ("ok", ws.cue_lists())
        if cmd in ("runningOrPausedCues", "runningCues"):
            ids = [u for u in ws.running if cmd == "runningOrPausedCues" or ws.running[u]["paused_at"] is None]
            return ("ok", [{"uniqueID": u, "number": ws.by_uid(u)["number"], "listName": ws.by_uid(u)["name"],
                            "type": ws.by_uid(u)["type"]} for u in ids])
        if cmd == "showMode":
            return ("ok", ws.show_mode)
        if cmd in ("cue", "cue_id"):
            if not rest:
                return ("error", None)
            if rest[0] == "playhead" and cmd == "cue":
                cue = ws.playhead_cue()
                key = rest[1] if len(rest) > 1 else "uniqueID"
                if cue is None:
                    return ("ok", "none")
            else:
                cue = ws.by_number(rest[0]) if cmd == "cue" else ws.by_uid(rest[0])
                key = rest[1] if len(rest) > 1 else "uniqueID"
                if cue is None:
                    return ("error", None)
            if key in ("go", "start"):
                self.start(ws, cue, now)
                return ("ok", None)
            if key == "valuesForKeys":
                try:
                    keys = json.loads(args[0]) if args else []
                except (ValueError, TypeError):
                    return ("error", None)
                return ("ok", {k: self.value(ws, cue, k, now) for k in keys})
            return ("ok", self.value(ws, cue, key, now))
        return ("error", None)

    def value(self, ws, cue, key, now):
        running = cue["uid"] in ws.running
        if key == "uniqueID":
            return cue["uid"]
        if key == "number":
            return cue["number"]
        if key in ("name", "listName", "displayName"):
            return cue["name"] if key != "displayName" else (cue["number"] + " " + cue["name"]).strip()
        if key == "type":
            return cue["type"]
        if key in ("duration", "currentDuration"):
            return float(cue["duration"] or 0)
        if key == "actionElapsed":
            return ws.elapsed(cue["uid"], now) if running else 0.0
        if key == "percentActionElapsed":
            d = cue["duration"] or 0
            return (ws.elapsed(cue["uid"], now) / d) if running and d else 0.0
        if key == "isRunning":
            return running and ws.running[cue["uid"]]["paused_at"] is None
        if key == "isPaused":
            return running and ws.running[cue["uid"]]["paused_at"] is not None
        if key in ("isBroken", "isLoaded"):
            return key == "isLoaded"
        return None

    def take_out(self):
        with self.lock:
            out, self.out = self.out, []
            return out


# ---------------------------------------------------------------- Sockets


class Server:
    def __init__(self, fake, port, udp=True, silent=False, delay=0.0, udp_reply_port=53001):
        self.fake = fake
        self.port = port
        self.silent = silent
        self.delay = delay
        self.udp_reply_port = udp_reply_port
        self.conns = {}          # client key -> socket
        self.send_lock = threading.Lock()
        self.stop = threading.Event()
        self.tcp = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.tcp.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.tcp.bind(("127.0.0.1", port))
        self.tcp.listen(8)
        self.port = self.tcp.getsockname()[1]      # --port 0: any free port (printed below)
        self.udp = None
        if udp:
            self.udp = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            self.udp.bind(("127.0.0.1", self.port))

    def start(self):
        threading.Thread(target=self.accept_loop, daemon=True).start()
        threading.Thread(target=self.tick_loop, daemon=True).start()
        if self.udp:
            threading.Thread(target=self.udp_loop, daemon=True).start()
        print("fake QLab: TCP%s 127.0.0.1:%d" % ("+UDP" if self.udp else "", self.port), flush=True)

    def send(self, key, address, args):
        if self.silent:
            return
        data = osc_encode(address, args)
        with self.send_lock:
            if isinstance(key, tuple) and key[0] == "udp":
                try:
                    self.udp.sendto(data, (key[1], self.udp_reply_port))
                except OSError:
                    pass
                return
            s = self.conns.get(key)
            if s is None:
                return
            try:
                s.sendall(slip_encode(data))
            except OSError:
                pass

    def flush_updates(self):
        for key, address, args in self.fake.take_out():
            self.send(key, address, args)

    def answer(self, key, packet):
        m = osc_decode(packet)
        if m is None:
            return
        if self.delay:
            time.sleep(self.delay)
        for address, args in self.fake.handle(key, m[0], m[1]):
            self.send(key, address, args)
        self.flush_updates()

    def accept_loop(self):
        n = 0
        while not self.stop.is_set():
            try:
                s, _ = self.tcp.accept()
            except OSError:
                return
            n += 1
            key = "tcp%d" % n
            s.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            self.conns[key] = s
            threading.Thread(target=self.client_loop, args=(key, s), daemon=True).start()

    def client_loop(self, key, s):
        dec = SlipDecoder()
        while True:
            try:
                data = s.recv(65536)
            except OSError:
                break
            if not data:
                break
            for p in dec.feed(data):
                self.answer(key, p)
        self.conns.pop(key, None)
        with self.fake.lock:
            self.fake.clients.pop(key, None)
        try:
            s.close()
        except OSError:
            pass

    def udp_loop(self):
        while not self.stop.is_set():
            try:
                data, addr = self.udp.recvfrom(65536)
            except OSError:
                return
            self.answer(("udp", addr[0]), data)

    def tick_loop(self):
        while not self.stop.is_set():
            self.fake.tick(time.monotonic())
            self.flush_updates()
            time.sleep(0.05)

    def drop(self):
        for k, s in list(self.conns.items()):
            # Separately: on macOS shutdown can fail (the peer is gone) and the socket must still close.
            try:
                s.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            try:
                s.close()
            except OSError:
                pass
            self.conns.pop(k, None)

    def close_workspace(self):
        with self.fake.lock:
            for ws in self.fake.workspaces:
                self.fake.update(ws, "/disconnect")
        self.flush_updates()

    def shutdown(self):
        self.stop.set()
        self.drop()
        self.tcp.close()
        if self.udp:
            self.udp.close()


def console(server):
    fake = server.fake
    for line in sys.stdin:
        words = line.split()
        if not words:
            continue
        ws = fake.workspaces[0]
        with fake.lock:
            w = words[0]
            if w == "go":
                cue = ws.playhead_cue()
                if cue:
                    fake.start(ws, cue, time.monotonic())
            elif w in ("next", "prev"):
                fake._run(ws, "playhead", ["next" if w == "next" else "previous"], [], "", time.monotonic())
            elif w == "move" and len(words) > 1:
                cue = ws.by_number(words[1])
                if cue:
                    fake.move(ws, cue)
                else:
                    print("no cue %s" % words[1], flush=True)
            elif w == "show":
                ph = ws.playhead_cue()
                print("playhead %s, running %s" % (ph["number"] if ph else "none",
                                                     [ws.by_uid(u)["number"] for u in ws.running]), flush=True)
            elif w == "mute":
                server.silent = not server.silent
                print("muted" if server.silent else "answering", flush=True)
            elif w == "quit":
                break
        if w == "drop":
            server.drop()
        elif w == "close":
            server.close_workspace()
        server.flush_updates()
    server.shutdown()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--port", type=int, default=53000)
    ap.add_argument("--no-udp", action="store_true")
    ap.add_argument("--cues", help="a JSON file like the built-in sample (fictional names)")
    ap.add_argument("--two-workspaces", action="store_true")
    ap.add_argument("--no-passcode", default="", help="permissions without a passcode, e.g. view,control")
    ap.add_argument("--connect-permissions", action="store_true", help="answer connect with ok:view|control")
    ap.add_argument("--silent", action="store_true", help="never answer (OSC Access off)")
    ap.add_argument("--delay", type=float, default=0.0)
    ap.add_argument("--no-console", action="store_true", help="do not read commands from stdin (run until killed)")
    a = ap.parse_args(argv)
    spec = json.load(open(a.cues, encoding="utf-8")) if a.cues else json.loads(json.dumps(SAMPLE))
    if a.two_workspaces:
        spec["workspaces"].append(SECOND_WORKSPACE)
    if a.no_passcode:
        for w in spec["workspaces"]:
            w["noPasscode"] = [p for p in a.no_passcode.split(",") if p]
    server = Server(FakeQLab(spec, a.connect_permissions), a.port, udp=not a.no_udp, silent=a.silent, delay=a.delay)
    server.start()
    if a.no_console:
        try:
            while True:
                time.sleep(3600)
        except KeyboardInterrupt:
            pass
        server.shutdown()
    else:
        console(server)


if __name__ == "__main__":
    main()
