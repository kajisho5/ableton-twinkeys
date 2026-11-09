import json
import unittest

from TwinKeysBridge.commands import CommandDispatcher
from TwinKeysBridge.state import StateTracker
from tests.fake_live import FakeSong, FakeClock, FakeClip


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
        self.assertEqual(msgs[0], {"type": "ack", "id": 42, "ok": True})
        types = [m["type"] for m in msgs[1:]]
        for t in ("song", "tracks", "scenes", "clips", "meters", "progress"):
            self.assertIn(t, types)
        self.assertEqual(sum(1 for t in types if t == "clips"), 4)

    def test_commands_mark_tracker_dirty(self):
        tracker = StateTracker(lambda: self.song, clock=FakeClock())
        d = CommandDispatcher(lambda: self.song, tracker)
        run(d, {"cmd": "set_mute", "id": 1, "track": 2, "on": True})
        self.assertIn(2, tracker._dirty_tracks)


if __name__ == "__main__":
    unittest.main()
