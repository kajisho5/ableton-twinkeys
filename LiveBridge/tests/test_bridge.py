import json
import unittest

from TwinKeysBridge import constants as C
from TwinKeysBridge.bridge import Bridge
from TwinKeysBridge.listeners import LiveListenerBinder
from TwinKeysBridge.constants import LOOPBACK_HOST, COMMAND_PORT, STATE_PORT
from tests.fake_live import FakeSong, FakeClock, FakeTrack


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


class BridgeBudgetTest(unittest.TestCase):

    def setUp(self):
        self.song = FakeSong(200, 30)
        self.clock = FakeClock()
        self.transport = FakeTransport()
        self.logs = []
        self.bridge = Bridge(lambda: self.song, log=self.logs.append,
                             transport_factory=lambda: self.transport,
                             clock=self.clock)
        self.ops = {"n": 0}
        ops = self.ops
        for obj in self.all_objects():
            self.wrap(obj)

    def all_objects(self):
        for t in self.song.tracks:
            yield t
            yield t.mixer_device.volume
            yield t.mixer_device.panning
        for s in self.song.scenes:
            yield s

    def wrap(self, obj):
        ops = self.ops
        listeners = obj._listeners

        def adder(prop):
            def add(cb):
                ops["n"] += 1
                listeners.setdefault(prop, []).append(cb)
            return add

        def remover(prop):
            def remove(cb):
                ops["n"] += 1
                listeners.get(prop, []).remove(cb)
            return remove
        for prop in LiveListenerBinder.TRACK_PROPS + \
                LiveListenerBinder.SCENE_PROPS + ("value",):
            object.__setattr__(obj, "add_%s_listener" % prop, adder(prop))
            object.__setattr__(obj, "remove_%s_listener" % prop,
                               remover(prop))

    def tick(self):
        self.ops["n"] = 0
        self.clock.advance(0.1)
        self.bridge.tick()
        out, self.transport.outbox = self.transport.outbox, []
        return out

    def settle(self):
        for _ in range(60):
            self.tick()
            self.assertLessEqual(self.ops["n"], C.LISTENER_OPS_PER_TICK + 10)

    def test_listener_rebind_is_bounded_and_incremental(self):
        self.settle()
        self.assertEqual(self.bridge._binder.pending(), 0)
        new = FakeTrack("New", 30)
        self.wrap(new)
        self.wrap(new.mixer_device.volume)
        self.wrap(new.mixer_device.panning)
        self.song.tracks.insert(0, new)
        self.song.notify("tracks")
        self.tick()
        # only the new track's listeners are added, not 200 x 8 again
        self.assertLessEqual(self.ops["n"], 8)
        self.settle()
        # old Track 5 is now index 6: its listener marks the right index
        self.song.tracks[6].solo = True
        self.song.tracks[6].notify("solo")
        out = [m for m in self.tick() if m["type"] == "tracks"]
        self.assertEqual([i["index"] for i in out[0]["items"]], [6])
        self.assertEqual(out[0]["items"][0]["name"], "Track 5")
        self.song.tracks[0].mute = True
        self.song.tracks[0].notify("mute")
        out = [m for m in self.tick() if m["type"] == "tracks"]
        self.assertEqual(out[0]["items"][0]["name"], "New")
        # a removed track's listeners go away, its callback is inert
        gone = self.song.tracks.pop(3)
        self.song.notify("tracks")
        self.settle()
        self.assertEqual(gone.listener_count(), 0)
        self.bridge.shutdown()
        for obj in self.all_objects():
            self.assertEqual(obj.listener_count(), 0)

    def test_many_reordered_scenes_spread_over_ticks(self):
        self.settle()
        self.song.scenes.reverse()        # most objects outside the window
        self.song.notify("scenes")
        self.tick()
        self.assertLessEqual(self.ops["n"], C.LISTENER_OPS_PER_TICK + 10)
        self.settle()
        self.assertEqual(self.bridge._binder.pending(), 0)
        for s in self.song.scenes:
            self.assertEqual(s.listener_count(), 3)

    def test_64_hellos_in_one_tick(self):
        self.settle()
        self.transport.inbox = [json.dumps({"cmd": "hello", "id": i}).encode()
                                for i in range(64)]
        out = self.tick()
        self.assertEqual(sum(1 for m in out if m["type"] == "ack"), 64)
        self.assertEqual(sum(1 for m in out if m["type"] == "song"), 1)

    def test_error_storm_is_bounded(self):
        for i in range(1000):
            self.bridge._report_error("distinct error %d" % i)
        self.assertLessEqual(len(self.logs), C.ERROR_LOG_MAX)
        self.assertLessEqual(len(self.bridge._last_error_at),
                             C.ERROR_KEYS_MAX)
        # identical repeats are still rate limited after the storm
        self.clock.advance(C.ERROR_REPEAT_INTERVAL + 0.1)
        n = len(self.logs)
        for _ in range(50):
            self.bridge._report_error("same")
        logged = self.logs[n:]
        self.assertEqual(sum(1 for l in logged if l.endswith(": same")), 1)
        self.assertTrue(any("980 further errors suppressed" in l
                            for l in logged))


if __name__ == "__main__":
    unittest.main()
