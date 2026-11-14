"""Tests for scripts/fake-qlab.py (run: python3 -m unittest discover -s scripts -p 'test_*.py')."""

import importlib.util
import json
import os
import socket
import time
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("fake_qlab", os.path.join(_HERE, "fake-qlab.py"))
fq = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(fq)

WS = fq.SAMPLE["workspaces"][0]["uniqueID"]


def sample():
    return fq.FakeQLab(json.loads(json.dumps(fq.SAMPLE)))


def data(replies):
    (address, args), = replies
    return json.loads(args[0])


class OSCAndSLIPTests(unittest.TestCase):
    def test_osc_round_trip_and_padding(self):
        b = fq.osc_encode("/workspace/WS-1/go")
        self.assertEqual(len(b) % 4, 0)
        self.assertEqual(b.hex(), "2f776f726b73706163652f57532d312f676f00002c000000")   # shared/test-vectors/qlab.json
        self.assertEqual(fq.osc_decode(fq.osc_encode("/a", ["1234", 1, 1.5, True])), ("/a", ["1234", 1, 1.5, True]))

    def test_slip_escapes_and_split_stream(self):
        framed = fq.slip_encode(bytes([1, 0xC0, 2, 0xDB, 3]))
        self.assertEqual(framed.hex(), "c001dbdc02dbdd03c0")
        d = fq.SlipDecoder()
        self.assertEqual(d.feed(framed[:4]), [])
        self.assertEqual(d.feed(framed[4:] + framed), [bytes([1, 0xC0, 2, 0xDB, 3])] * 2)


class FakeQLabTests(unittest.TestCase):
    def connect(self, f, code="1234", c="c"):
        r = data(f.handle(c, "/workspace/%s/connect" % WS, [code]))
        self.assertEqual(r["data"], "ok")
        f.handle(c, "/workspace/%s/alwaysReply" % WS, [1])
        f.handle(c, "/workspace/%s/updates" % WS, [1])

    def test_workspaces_and_passcodes(self):
        f = sample()
        self.assertEqual(data(f.handle("c", "/workspaces", []))["data"][0]["displayName"], "sample-show")
        self.assertEqual(data(f.handle("c", "/workspace/%s/cueLists" % WS, []))["status"], "denied")
        self.assertEqual(data(f.handle("c", "/workspace/%s/connect" % WS, ["0000"]))["data"], "badpass")
        self.assertEqual(data(f.handle("c", "/workspace/%s/connect" % WS, []))["data"], "badpass")   # no "No Passcode" rights
        self.connect(f)
        lists = data(f.handle("c", "/workspace/%s/cueLists" % WS, []))["data"]
        group = [c for c in lists[0]["cues"] if c["type"] == "Group"][0]
        self.assertEqual([c["number"] for c in group["cues"]], ["11", "11.5", "12", "13", "14"])

    def test_view_only_passcode_cannot_go(self):
        f = sample()
        self.connect(f, "5678")
        self.assertEqual(data(f.handle("c", "/workspace/%s/go" % WS, []))["status"], "denied")
        self.assertEqual(data(f.handle("c", "/workspace/%s/showMode" % WS, []))["data"], True)

    def test_go_moves_the_playhead_and_sends_updates(self):
        f = sample()
        self.connect(f)
        f.handle("c", "/workspace/%s/playhead/12" % WS, [])
        f.take_out()
        self.assertEqual(data(f.handle("c", "/workspace/%s/go" % WS, []))["status"], "ok")
        self.assertEqual(f.events[-1], "EVENT go 12")
        ph = data(f.handle("c", "/workspace/%s/cue/playhead/number" % WS, []))["data"]
        self.assertEqual(ph, "13")
        out = f.take_out()
        self.assertTrue(any(a.endswith("/playbackPosition") for _, a, _ in out), out)
        running = data(f.handle("c", "/workspace/%s/runningOrPausedCues/shallow" % WS, []))["data"]
        self.assertEqual([r["number"] for r in running], ["12"])
        uid = running[0]["uniqueID"]
        v = data(f.handle("c", "/workspace/%s/cue_id/%s/valuesForKeys" % (WS, uid), ['["currentDuration","actionElapsed"]']))["data"]
        self.assertEqual(v["currentDuration"], 200.0)

    def test_go_without_always_reply_is_silent(self):
        f = sample()
        self.assertEqual(data(f.handle("c", "/workspace/%s/connect" % WS, ["1234"]))["data"], "ok")
        self.assertEqual(f.handle("c", "/workspace/%s/go" % WS, []), [])

    def test_go_to_a_cue_and_panic_twice(self):
        f = sample()
        self.connect(f)
        uid = f.workspaces[0].by_number("90")["uid"]
        f.handle("c", "/workspace/%s/cue_id/%s/go" % (WS, uid), [])
        self.assertEqual(f.events[-1], "EVENT go 90")
        f.handle("c", "/workspace/%s/panic" % WS, [])
        self.assertEqual(f.events[-1], "EVENT panic")
        f.handle("c", "/workspace/%s/panic" % WS, [])
        self.assertEqual(f.events[-1], "EVENT panicNow")
        self.assertEqual(f.workspaces[0].running, {})

    def test_stop_needs_edit(self):
        f = sample()
        f.workspaces[0].passcodes["4321"] = {"view", "control"}
        self.connect(f, "4321")
        self.assertEqual(data(f.handle("c", "/workspace/%s/stop" % WS, []))["status"], "denied")
        self.assertEqual(data(f.handle("c", "/workspace/%s/hardStop" % WS, []))["status"], "ok")

    def test_cues_end_after_their_duration(self):
        f = sample()
        self.connect(f)
        f.handle("c", "/workspace/%s/playhead/4" % WS, [])
        f.handle("c", "/workspace/%s/go" % WS, [], now=100.0)
        f.tick(103.0)
        self.assertEqual(len(f.workspaces[0].running), 1)
        f.tick(106.5)
        self.assertEqual(f.workspaces[0].running, {})


class ServerTests(unittest.TestCase):
    def test_tcp_with_slip(self):
        srv = fq.Server(sample(), 0, udp=False)
        port = srv.tcp.getsockname()[1]
        srv.port = port
        srv.start()
        try:
            s = socket.create_connection(("127.0.0.1", port), timeout=3)
            s.sendall(fq.slip_encode(fq.osc_encode("/version")))
            dec = fq.SlipDecoder()
            got = []
            deadline = time.time() + 3
            while not got and time.time() < deadline:
                got = dec.feed(s.recv(4096))
            address, args = fq.osc_decode(got[0])
            self.assertEqual(address, "/reply/version")
            self.assertEqual(json.loads(args[0])["data"], "5.6.5")
            s.close()
        finally:
            srv.shutdown()


if __name__ == "__main__":
    unittest.main()
