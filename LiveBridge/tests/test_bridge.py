import json
import unittest

from TwinKeysBridge.bridge import Bridge
from TwinKeysBridge.constants import LOOPBACK_HOST, COMMAND_PORT, STATE_PORT
from tests.fake_live import FakeSong, FakeClock


class FakeTransport(object):
    def __init__(self):
        self.listen_addr = (LOOPBACK_HOST, COMMAND_PORT)
        self.dest_addr = (LOOPBACK_HOST, STATE_PORT)
        self.inbox = []
        self.outbox = []
        self.closed = False

    def receive(self, n):
        got, self.inbox = self.inbox[:n], self.inbox[n:]
        return got

    def send(self, data):
        self.outbox.append(json.loads(data.decode("utf-8")))
        return True

    def close(self):
        self.closed = True


class BridgeTest(unittest.TestCase):

    def setUp(self):
        self.song = FakeSong(3, 2)
        self.clock = FakeClock()
        self.transport = FakeTransport()
        self.logs = []
        self.bridge = Bridge(lambda: self.song, log=self.logs.append,
                             transport_factory=lambda: self.transport,
                             clock=self.clock)

    def tick(self):
        self.clock.advance(0.1)
        self.bridge.tick()
        out, self.transport.outbox = self.transport.outbox, []
        return out

    def test_hello_flow(self):
        self.tick()
        self.transport.inbox.append(b'{"cmd":"hello","id":5}')
        out = self.tick()
        self.assertEqual(out[0], {"type": "ack", "id": 5, "ok": True})
        self.assertIn("song", [m["type"] for m in out])

    def test_listeners_bound_and_used(self):
        self.tick()
        self.assertGreater(self.song.tracks[0].listener_count(), 0)
        self.assertGreater(self.song.listener_count(), 0)
        for _ in range(60):
            self.tick()
        self.song.tracks[2].solo = True
        self.song.tracks[2].notify("solo")
        out = [m for m in self.tick() if m["type"] == "tracks"]
        self.assertEqual(out[0]["items"][0]["index"], 2)
        self.assertTrue(out[0]["items"][0]["solo"])
        self.bridge.shutdown()
        self.assertEqual(self.song.tracks[0].listener_count(), 0)
        self.assertEqual(self.song.listener_count(), 0)
        self.assertTrue(self.transport.closed)

    def test_internal_error_reported_not_raised(self):
        self.tick()

        class Boom(object):
            def __getattr__(self, name):
                raise RuntimeError("kaboom")
        self.song.view = Boom()
        out = self.tick()
        errs = [m for m in out if m["type"] == "error"]
        self.assertTrue(errs)
        self.assertIn("kaboom", errs[0]["message"])
        self.assertTrue(any("kaboom" in l for l in self.logs))
        # repeated identical errors are rate limited
        out = self.tick()
        self.assertEqual([m for m in out if m["type"] == "error"], [])

    def test_bind_failure_retries(self):
        attempts = []

        def factory():
            attempts.append(1)
            if len(attempts) == 1:
                raise OSError(48, "Address already in use")
            return self.transport
        b = Bridge(lambda: self.song, log=self.logs.append,
                   transport_factory=factory, clock=self.clock)
        b.tick()
        self.assertIsNone(b.transport)
        self.clock.advance(1)
        b.tick()
        self.assertEqual(len(attempts), 1)
        self.clock.advance(5)
        b.tick()
        self.assertIs(b.transport, self.transport)

    def test_garbage_input_does_not_break_loop(self):
        self.tick()
        self.transport.inbox.extend([b"\x00\x01", b"{}",
                                     b'{"cmd":"play","id":1}'])
        out = self.tick()
        acks = [m for m in out if m["type"] == "ack"]
        self.assertEqual([a["ok"] for a in acks], [False, False, True])
        self.assertTrue(self.song.is_playing)


if __name__ == "__main__":
    unittest.main()
