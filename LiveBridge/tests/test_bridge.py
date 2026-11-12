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

    def use_song_with_returns(self, n_returns):
        self.song = FakeSong(3, 2, n_returns=n_returns)
        for _ in range(60):
            self.tick()

    def test_send_listeners_mark_only_the_row(self):
        self.use_song_with_returns(3)
        sends = self.song.tracks[1].mixer_device.sends
        # Send A and Send B are listened to; the third send is not reported.
        self.assertEqual([p.listener_count() for p in sends], [1, 1, 0])
        sends[1].value = 0.4
        sends[1].notify("value")
        out = self.tick()
        self.assertEqual([m["type"] for m in out], ["tracks"])
        self.assertEqual([i["index"] for i in out[0]["items"]], [1])
        self.assertEqual(out[0]["items"][0]["sends"], [0.0, 0.4])

    def test_return_track_change_rebinds_send_listeners(self):
        self.use_song_with_returns(2)
        for t in self.song.tracks:
            t.mixer_device.sends[0].value = 0.5
        self.tick()
        old_a, old_b = self.song.tracks[0].mixer_device.sends
        structure = self.bridge.tracker.structure
        self.song.insert_return_track(0)    # fires return_tracks
        out = [m for m in self.tick() if m["type"] == "tracks"]
        rows = [i for m in out for i in m["items"]]
        self.assertEqual([i["sends"] for i in rows], [[0.0, 0.5]] * 3)
        self.assertEqual(self.bridge._binder.pending(), 0)
        for t in self.song.tracks:
            self.assertEqual([p.listener_count()
                              for p in t.mixer_device.sends], [1, 1, 0])
        self.assertEqual(old_b.listener_count(), 0)
        self.assertEqual(self.bridge.tracker.structure, structure)
        # The new Send A is live; removing it moves the old ones back.
        new_a = self.song.tracks[2].mixer_device.sends[0]
        new_a.value = 0.25
        new_a.notify("value")
        out = [m for m in self.tick() if m["type"] == "tracks"]
        self.assertEqual(out[0]["items"][0]["sends"], [0.25, 0.5])
        self.song.delete_return_track(0)
        self.tick()
        self.assertEqual(new_a.listener_count(), 0)
        self.assertEqual([old_a.listener_count(), old_b.listener_count()],
                         [1, 1])
        self.bridge.shutdown()
        for t in self.song.tracks:
            self.assertEqual([p.listener_count()
                              for p in t.mixer_device.sends], [0, 0])
        self.assertEqual(self.song.listener_count(), 0)

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
            for p in t.mixer_device.sends:
                yield p
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

    def test_return_track_change_rebinds_sends_in_steps(self):
        self.song = FakeSong(200, 30, n_returns=2)
        for obj in self.all_objects():
            self.wrap(obj)
        for t in self.song.tracks:
            t.mixer_device.sends[1].value = 0.5
        self.settle()
        self.assertEqual(self.bridge._binder.pending(), 0)
        self.song.insert_return_track(1)
        for t in self.song.tracks:
            self.wrap(t.mixer_device.sends[1])
        first = None
        ticks = 0
        while True:
            out = self.tick()
            ticks += 1
            self.assertLessEqual(self.ops["n"], C.LISTENER_OPS_PER_TICK + 10)
            self.assertEqual([m for m in out if m["type"] == "clips"], [])
            if first is None:
                first = [i for m in out if m["type"] == "tracks"
                         for i in m["items"]]
            if not self.bridge._binder.pending():
                break
            self.assertLess(ticks, 20)
        self.assertGreaterEqual(ticks, 2)    # 800 calls: spread out
        # Every row is re-read in the first tick: Send B is the new return.
        self.assertEqual(len(first), 200)
        self.assertEqual(set(tuple(i["sends"]) for i in first), {(0.0, 0.0)})
        for t in self.song.tracks:
            self.assertEqual([p.listener_count()
                              for p in t.mixer_device.sends], [1, 1, 0])

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
