import json
import unittest

from TwinKeysBridge.commands import CommandDispatcher
from TwinKeysBridge.state import StateTracker
from tests.fake_live import FakeSong, FakeClock, FakeClip, FakeTrack


def run(dispatcher, obj):
    data = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
    return [json.loads(m) for m in dispatcher.handle(data)]


class CommandTest(unittest.TestCase):

    def setUp(self):
        self.song = FakeSong(4, 3)
        self.d = CommandDispatcher(lambda: self.song)

    def ack(self, obj):
        msgs = run(self.d, obj)
        self.assertEqual(msgs[0]["type"], "ack")
        return msgs[0]

    def assertOk(self, obj):
        a = self.ack(obj)
        self.assertTrue(a["ok"], a)
        self.assertNotIn("error", a)
        self.assertEqual(a["id"], obj["id"])
        return a

    def assertBad(self, obj, needle=None):
        a = self.ack(obj)
        self.assertFalse(a["ok"])
        self.assertIsInstance(a["error"], str)
        if needle:
            self.assertIn(needle, a["error"])
        return a

    def test_transport_commands(self):
        self.assertOk({"cmd": "play", "id": 1})
        self.assertOk({"cmd": "stop", "id": 2})
        self.assertOk({"cmd": "continue", "id": 3})
        self.assertOk({"cmd": "stop_all", "id": 4})
        self.assertEqual(self.song.calls, ["start_playing", "stop_playing",
                                           "continue_playing",
                                           "stop_all_clips"])

    def test_fire_scene_and_clip(self):
        self.assertOk({"cmd": "fire_scene", "id": 1, "scene": 2})
        self.assertEqual(self.song.scenes[2].fired, 1)
        self.assertOk({"cmd": "fire_clip", "id": 2, "track": 1, "scene": 0})
        self.assertEqual(self.song.tracks[1].clip_slots[0].fired, 1)
        self.assertBad({"cmd": "fire_scene", "id": 3, "scene": 3}, "range")
        self.assertBad({"cmd": "fire_scene", "id": 4, "scene": -1}, "range")
        self.assertBad({"cmd": "fire_clip", "id": 5, "track": 4, "scene": 0})
        self.assertBad({"cmd": "fire_clip", "id": 6, "track": 0, "scene": 9})
        self.assertBad({"cmd": "fire_clip", "id": 7, "track": -1, "scene": 0},
                       "master")
        self.assertBad({"cmd": "fire_scene", "id": 8, "scene": "1"})
        self.assertBad({"cmd": "fire_scene", "id": 9, "scene": True})
        self.assertBad({"cmd": "fire_scene", "id": 10}, "missing")

    def test_stop_track(self):
        self.assertOk({"cmd": "stop_track", "id": 1, "track": 3})
        self.assertEqual(self.song.tracks[3].stopped, 1)
        self.assertBad({"cmd": "stop_track", "id": 2, "track": -1})

    def test_tempo(self):
        self.assertOk({"cmd": "set_tempo", "id": 1, "bpm": 128.5})
        self.assertEqual(self.song.tempo, 128.5)
        self.assertOk({"cmd": "set_tempo", "id": 2, "bpm": 20})
        self.assertOk({"cmd": "set_tempo", "id": 3, "bpm": 999})
        for bad in (19.99, 999.1, "120", None, True):
            self.assertBad({"cmd": "set_tempo", "id": 4, "bpm": bad})
        self.assertBad(b'{"cmd":"set_tempo","id":5,"bpm":NaN}')
        self.assertEqual(self.song.tempo, 999)

    def test_volume_pan_including_master(self):
        self.assertOk({"cmd": "set_volume", "id": 1, "track": 0, "value": 0.5})
        self.assertEqual(self.song.tracks[0].mixer_device.volume.value, 0.5)
        self.assertOk({"cmd": "set_volume", "id": 2, "track": -1, "value": 1})
        self.assertEqual(self.song.master_track.mixer_device.volume.value, 1.0)
        self.assertOk({"cmd": "set_pan", "id": 3, "track": 2, "value": -1})
        self.assertEqual(self.song.tracks[2].mixer_device.panning.value, -1.0)
        self.assertOk({"cmd": "set_pan", "id": 4, "track": -1, "value": 0.5})
        self.assertAlmostEqual(
            self.song.master_track.mixer_device.panning.value, 0.5)
        self.assertBad({"cmd": "set_volume", "id": 5, "track": 0, "value": 1.1})
        self.assertBad({"cmd": "set_volume", "id": 6, "track": 0, "value": -0.1})
        self.assertBad({"cmd": "set_pan", "id": 7, "track": 0, "value": 2})
        self.assertBad({"cmd": "set_volume", "id": 8, "track": -2, "value": 0})
        self.assertBad({"cmd": "set_volume", "id": 9, "track": 0})

    def test_volume_uses_parameter_range(self):
        p = self.song.tracks[1].mixer_device.volume
        p.min, p.max = 0.2, 0.6
        self.assertOk({"cmd": "set_volume", "id": 1, "track": 1, "value": 0.5})
        self.assertAlmostEqual(p.value, 0.4)

    def test_mute_solo(self):
        self.assertOk({"cmd": "set_mute", "id": 1, "track": 1, "on": True})
        self.assertTrue(self.song.tracks[1].mute)
        self.assertOk({"cmd": "set_solo", "id": 2, "track": 2, "on": True})
        self.assertTrue(self.song.tracks[2].solo)
        self.assertOk({"cmd": "set_mute", "id": 3, "track": 1, "on": False})
        self.assertFalse(self.song.tracks[1].mute)
        self.assertBad({"cmd": "set_mute", "id": 4, "track": 1, "on": 1})
        self.assertBad({"cmd": "set_solo", "id": 5, "track": -1, "on": True},
                       "master")
        self.assertBad({"cmd": "set_mute", "id": 6, "track": 9, "on": True})

    def test_select_scene(self):
        self.assertOk({"cmd": "select_scene", "id": 1, "scene": 2})
        self.assertIs(self.song.view.selected_scene, self.song.scenes[2])
        self.assertBad({"cmd": "select_scene", "id": 2, "scene": 5})

    def test_malformed(self):
        a = self.ack(b"not json")
        self.assertFalse(a["ok"])
        self.assertIsNone(a["id"])
        self.assertFalse(self.ack(b"\xff\xfe")["ok"])
        self.assertFalse(self.ack(b"[1,2]")["ok"])
        self.assertFalse(self.ack({"cmd": "play"})["ok"])
        self.assertFalse(self.ack({"cmd": "play", "id": "7"})["ok"])
        self.assertFalse(self.ack({"cmd": "play", "id": True})["ok"])
        a = self.ack({"id": 3})
        self.assertEqual((a["id"], a["ok"]), (3, False))
        self.assertBad({"cmd": "format_disk", "id": 4}, "unknown")
        self.assertEqual(self.song.calls, [])

    def test_live_exception_becomes_ack_error(self):
        def boom():
            raise RuntimeError("Changes cannot be triggered by notifications")
        self.song.start_playing = boom
        a = self.assertBad({"cmd": "play", "id": 11}, "Live error")
        self.assertEqual(a["id"], 11)

    def test_song_provider_failure(self):
        d = CommandDispatcher(lambda: None)
        self.assertFalse(run(d, {"cmd": "play", "id": 1})[0]["ok"])

    def test_hello_ack_then_full_state(self):
        self.song.tracks[0].clip_slots[1].clip = FakeClip("A")
        tracker = StateTracker(lambda: self.song, clock=FakeClock())
        d = CommandDispatcher(lambda: self.song, tracker)
        msgs = run(d, {"cmd": "hello", "id": 42})
        # The ack comes at once; the full state from the tracker's next tick.
        self.assertEqual(msgs, [{"type": "ack", "id": 42, "ok": True}])
        types = [json.loads(m)["type"] for m in tracker.tick()]
        for t in ("song", "tracks", "scenes", "clips", "meters", "progress"):
            self.assertIn(t, types)
        self.assertEqual(sum(1 for t in types if t == "clips"), 4)

    def test_repeated_hello_is_coalesced(self):
        clock = FakeClock()
        tracker = StateTracker(lambda: self.song, clock=clock)
        d = CommandDispatcher(lambda: self.song, tracker)
        tracker.tick()
        clock.advance(0.1)
        tracker.tick()
        scans = []
        real = tracker._full_scan
        tracker._full_scan = lambda *a: (scans.append(1), real(*a))
        for i in range(64):
            self.assertEqual(run(d, {"cmd": "hello", "id": i}),
                             [{"type": "ack", "id": i, "ok": True}])
        self.assertEqual(scans, [])          # nothing done inside handle()
        clock.advance(0.1)
        songs = [m for m in map(json.loads, tracker.tick())
                 if m["type"] == "song"]
        self.assertEqual(len(songs), 1)
        self.assertEqual(scans, [1])
        # More hellos right away: kept pending, sent once after the interval.
        sent = 0
        for _ in range(10):
            for i in range(64):
                run(d, {"cmd": "hello", "id": i})
            clock.advance(0.1)
            sent += sum(1 for m in map(json.loads, tracker.tick())
                        if m["type"] == "song")
        self.assertEqual(len(scans), 3)      # 1 s / FULL_STATE_MIN_INTERVAL
        self.assertEqual(sent, 2)

    # ------------------------------------------------------------ structure

    def make_tracked(self):
        self.clock = FakeClock()
        self.tracker = StateTracker(lambda: self.song, clock=self.clock,
                                    structure_seed=100)
        self.d = CommandDispatcher(lambda: self.song, self.tracker)
        self.song_msgs = [m for m in map(json.loads, self.tracker.tick())
                          if m["type"] == "song"]
        return self.song_msgs[-1]["structure"]

    def test_song_message_carries_structure(self):
        first = self.make_tracked()
        self.assertIsInstance(first, int)
        self.song.tracks.insert(0, FakeTrack("New", 3))
        self.tracker.mark_structure_dirty()
        self.clock.advance(0.1)
        songs = [m for m in map(json.loads, self.tracker.tick())
                 if m["type"] == "song"]
        second = songs[-1]["structure"]
        self.assertGreater(second, first)
        # reorder (same length) and scene removal also count
        self.song.tracks.reverse()
        self.tracker.mark_structure_dirty()
        self.clock.advance(0.1)
        self.tracker.tick()
        self.assertGreater(self.tracker.structure, second)
        third = self.tracker.structure
        self.song.scenes.pop()
        self.clock.advance(1.1)              # found by the 1 s poll
        self.tracker.tick()
        self.assertGreater(self.tracker.structure, third)
        # a mixer change does not
        fourth = self.tracker.structure
        self.song.tracks[0].mute = True
        self.tracker.mark_track_dirty(0)
        self.clock.advance(1.1)
        self.tracker.tick()
        self.assertEqual(self.tracker.structure, fourth)

    def test_structure_match_accepted(self):
        cur = self.make_tracked()
        a = self.assertOk({"cmd": "fire_clip", "id": 3, "track": 1,
                           "scene": 2, "structure": cur})
        self.assertEqual(a, {"type": "ack", "id": 3, "ok": True})
        self.assertEqual(self.song.tracks[1].clip_slots[2].fired, 1)

    def test_structure_missing_accepted(self):
        self.make_tracked()
        self.assertOk({"cmd": "fire_clip", "id": 3, "track": 1, "scene": 2})
        self.assertEqual(self.song.tracks[1].clip_slots[2].fired, 1)

    def test_structure_mismatch_rejected(self):
        old = self.make_tracked()
        target = self.song.tracks[1]
        # A track is inserted at 0; the listener marks the structure dirty
        # and the command arrives in the same tick, before tracker.tick().
        self.song.tracks.insert(0, FakeTrack("New", 3))
        self.tracker.mark_structure_dirty()
        msgs = run(self.d, {"cmd": "fire_clip", "id": 9, "track": 1,
                            "scene": 2, "structure": old})
        new = self.tracker.structure
        self.assertNotEqual(new, old)
        self.assertEqual(msgs, [{"type": "ack", "id": 9, "ok": False,
                                 "error": "structure_changed",
                                 "structure": new}])
        for t in self.song.tracks:
            self.assertEqual(sum(s.fired for s in t.clip_slots), 0)
        # With the new value it goes to the intended (moved) track.
        self.assertOk({"cmd": "fire_clip", "id": 10, "track": 2, "scene": 2,
                       "structure": new})
        self.assertEqual(target.clip_slots[2].fired, 1)
        # Non-integer values are rejected; hello ignores the field.
        self.assertBad({"cmd": "play", "id": 11, "structure": "x"},
                       "'structure' must be an integer")
        self.assertBad({"cmd": "play", "id": 12, "structure": True})
        self.assertFalse(self.song.is_playing)
        self.assertOk({"cmd": "hello", "id": 13, "structure": old})

    def test_commands_mark_tracker_dirty(self):
        tracker = StateTracker(lambda: self.song, clock=FakeClock())
        d = CommandDispatcher(lambda: self.song, tracker)
        run(d, {"cmd": "set_mute", "id": 1, "track": 2, "on": True})
        self.assertIn(2, tracker._dirty_tracks)


if __name__ == "__main__":
    unittest.main()
