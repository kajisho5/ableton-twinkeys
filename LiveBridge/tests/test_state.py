import json
import unittest

from TwinKeysBridge import constants as C
from TwinKeysBridge.state import StateTracker
from tests.fake_live import FakeSong, FakeClock, FakeClip, FakeTrack


def decode(msgs):
    return [json.loads(m.decode("utf-8")) for m in msgs]


def of_type(msgs, t):
    return [m for m in decode(msgs) if m["type"] == t]


class TrackerTestBase(unittest.TestCase):

    def make(self, tracks=4, scenes=4):
        self.song = FakeSong(tracks, scenes)
        self.clock = FakeClock()
        self.errors = []
        self.tracker = StateTracker(lambda: self.song, clock=self.clock,
                                    report_error=self.errors.append)
        return self.tracker

    def tick(self, dt=0.1):
        self.clock.advance(dt)
        return self.tracker.tick()

    def settle(self, n=60):
        """Run enough ticks to send everything (incl. bulk) and pass the
        first full resend."""
        out = []
        for _ in range(n):
            out.extend(self.tick())
        return out


class DiffTest(TrackerTestBase):

    def test_first_tick_sends_full_state(self):
        self.make()
        self.song.tracks[1].clip_slots[2].clip = FakeClip("Bass", 0x112233, 8)
        msgs = decode(self.tick())
        types = set(m["type"] for m in msgs)
        self.assertTrue({"song", "tracks", "scenes", "clips"} <= types)
        song = [m for m in msgs if m["type"] == "song"][0]
        self.assertEqual(song["tracks"], 4)
        self.assertEqual(song["scenes"], 4)
        self.assertEqual(song["beat"], "1.1.1")
        self.assertEqual(song["sig"], [4, 4])
        self.assertEqual(song["selected_track"], 0)
        self.assertEqual(song["selected_scene"], 0)
        self.assertEqual(song["set_name"], "")
        tracks = [m for m in msgs if m["type"] == "tracks"][0]
        self.assertIn("master", tracks)
        self.assertEqual(set(tracks["master"]), {"volume", "pan"})
        item = tracks["items"][0]
        for k in ("index", "name", "color", "volume", "pan", "mute", "solo",
                  "playing_slot", "fired_slot", "is_group", "is_foldable"):
            self.assertIn(k, item)
        self.assertEqual(item["color"], "#00FF00")
        clips = [m for m in msgs if m["type"] == "clips" and m["track"] == 1]
        clip = clips[0]["items"][2]
        self.assertEqual(clip, {"scene": 2, "has_clip": True, "name": "Bass",
                                "color": "#112233", "is_playing": False,
                                "is_triggered": False, "length_beats": 8.0,
                                "position_beats": 0.0})

    def test_no_message_when_unchanged(self):
        self.make()
        self.settle()
        # Between full resends nothing changes -> nothing is sent.
        for _ in range(30):
            self.assertEqual(self.tick(), [])

    def test_full_resend_every_5_seconds(self):
        self.make()
        self.settle()

        def next_full():
            quiet = 0
            while True:
                msgs = self.tick()
                if msgs:
                    return quiet, msgs
                quiet += 1
        next_full()
        quiet, msgs = next_full()
        self.assertAlmostEqual((quiet + 1) * 0.1, C.FULL_RESEND_INTERVAL,
                               delta=0.15)
        self.assertEqual({m["type"] for m in decode(msgs)},
                         {"song", "tracks", "scenes", "clips"})

    def test_rate_limit_100ms(self):
        self.make()
        self.tick()
        self.song.tempo = 99.0
        self.clock.advance(0.03)
        self.assertEqual(of_type(self.tracker.tick(), "song"), [])
        self.clock.advance(0.07)
        self.assertEqual(of_type(self.tracker.tick(), "song")[0]["tempo"], 99.0)

    def test_song_change(self):
        self.make()
        self.settle()
        self.song.is_playing = True
        self.song.current_song_time = 66.25
        self.song.view.selected_scene = self.song.scenes[3]
        self.song.view.selected_track = self.song.master_track
        msgs = of_type(self.tick(), "song")
        self.assertEqual(len(msgs), 1)
        self.assertEqual(msgs[0]["beat"], "17.3.2")
        self.assertTrue(msgs[0]["playing"])
        self.assertEqual(msgs[0]["selected_scene"], 3)
        self.assertEqual(msgs[0]["selected_track"], -1)

    def test_track_change_sends_only_that_track(self):
        self.make(10, 2)
        self.settle()
        self.song.tracks[7].mute = True
        self.tracker.mark_track_dirty(7)   # as a Live listener would
        msgs = of_type(self.tick(), "tracks")
        self.assertEqual(len(msgs), 1)
        self.assertEqual(msgs[0]["start"], 7)
        self.assertEqual([i["index"] for i in msgs[0]["items"]], [7])
        self.assertTrue(msgs[0]["items"][0]["mute"])
        self.assertIn("master", msgs[0])

    def test_track_change_found_by_polling_without_listener(self):
        self.make(4, 2)
        self.settle()
        self.song.tracks[2].name = "Renamed"
        found = []
        for _ in range(5):
            found.extend(of_type(self.tick(), "tracks"))
        self.assertEqual(found[0]["items"][0]["name"], "Renamed")

    def test_master_only_change(self):
        self.make()
        self.settle()
        self.song.master_track.mixer_device.volume.value = 0.5
        msgs = of_type(self.tick(), "tracks")
        self.assertEqual(msgs, [{"type": "tracks", "start": 0,
                                 "master": {"volume": 0.5, "pan": 0.0},
                                 "items": []}])

    def test_clip_launch_updates_clips_scenes_tracks(self):
        self.make(3, 3)
        self.song.tracks[0].clip_slots[1].clip = FakeClip("A", 1, 4)
        self.settle()
        t = self.song.tracks[0]
        t.fired_slot_index = 1
        self.song.scenes[1].is_triggered = True
        self.tracker.mark_track_dirty(0)
        self.tracker.mark_scene_dirty(1)
        msgs = decode(self.tick())
        clips = [m for m in msgs if m["type"] == "clips"]
        self.assertEqual(len(clips), 1)
        self.assertEqual(clips[0]["track"], 0)
        self.assertEqual([i["scene"] for i in clips[0]["items"]], [1])
        self.assertTrue(clips[0]["items"][0]["is_triggered"])
        scenes = [m for m in msgs if m["type"] == "scenes"]
        self.assertTrue(scenes[0]["items"][0]["triggered"])
        # now it plays
        t.fired_slot_index = -1
        t.playing_slot_index = 1
        self.song.scenes[1].is_triggered = False
        self.song.is_playing = True
        self.tracker.mark_track_dirty(0)
        self.tracker.mark_scene_dirty(1)
        msgs = decode(self.tick())
        scene = [m for m in msgs if m["type"] == "scenes"][0]["items"][0]
        self.assertEqual((scene["index"], scene["playing"], scene["triggered"]),
                         (1, True, False))
        track = [m for m in msgs if m["type"] == "tracks"][0]["items"][0]
        self.assertEqual(track["playing_slot"], 1)
        clip = [m for m in msgs if m["type"] == "clips"][0]["items"][0]
        self.assertTrue(clip["is_playing"])

    def test_clip_position_change_alone_sends_no_clips(self):
        self.make(1, 2)
        clip = FakeClip("A", 1, 4)
        self.song.tracks[0].clip_slots[0].clip = clip
        self.song.tracks[0].playing_slot_index = 0
        self.song.is_playing = True
        self.settle()
        clip.playing_position = 1.5
        self.tracker.mark_track_dirty(0)
        self.assertEqual(of_type(self.tick(), "clips"), [])

    def test_new_clip_found_by_round_robin(self):
        self.make(2, 2)
        self.settle()
        self.song.tracks[1].clip_slots[0].clip = FakeClip("New")
        msgs = of_type(self.tick(), "clips")
        self.assertEqual(msgs[0]["items"][0]["name"], "New")

    def test_structure_change(self):
        self.make(2, 2)
        self.settle()
        self.song.tracks.insert(0, FakeTrack("Inserted", 2))
        self.tracker.mark_structure_dirty()
        msgs = decode(self.tick())
        song = [m for m in msgs if m["type"] == "song"][0]
        self.assertEqual(song["tracks"], 3)
        names = [i["name"] for m in msgs if m["type"] == "tracks"
                 for i in m["items"]]
        self.assertEqual(names, ["Inserted", "Track 0", "Track 1"])
        del self.song.tracks[:]
        self.song.scenes.pop()
        self.song.view.selected_track = None
        # no listener call: the 1 s structure poll must notice it
        msgs = decode(self.settle(12))
        song = [m for m in msgs if m["type"] == "song"][-1]
        self.assertEqual((song["tracks"], song["scenes"]), (0, 1))
        self.assertEqual(self.errors, [])


class MeterProgressTest(TrackerTestBase):

    def test_meters_only_while_playing_and_on_change(self):
        self.make(3, 1)
        self.settle()
        self.song.tracks[0].output_meter_left = 0.5
        for _ in range(int(C.METER_TAIL * 10) + 2):
            self.assertEqual(of_type(self.tick(), "meters"), [])
        self.song.is_playing = True
        m = of_type(self.tick(), "meters")
        self.assertEqual(len(m), 1)
        self.assertIn([0, 0.5, 0.0], m[0]["items"])
        self.assertEqual(m[0]["master"], [0.0, 0.0])
        # small change below threshold -> nothing
        self.song.tracks[0].output_meter_left = 0.505
        self.assertEqual(of_type(self.tick(), "meters"), [])
        self.song.tracks[0].output_meter_left = 0.6
        self.song.tracks[2].output_meter_right = 0.3
        m = of_type(self.tick(), "meters")[0]
        self.assertEqual(sorted(m["items"]), [[0, 0.6, 0.0], [2, 0.0, 0.3]])

    def test_meters_skip_tracks_without_audio(self):
        self.make(2, 1)
        self.song.tracks[1].has_audio_output = False
        self.song.tracks[1].output_meter_left = 0.9
        self.song.is_playing = True
        msgs = of_type(self.settle(3), "meters")
        idx = [i[0] for m in msgs for i in m["items"]]
        self.assertNotIn(1, idx)

    def test_progress(self):
        self.make(2, 2)
        clip = FakeClip("A", 1, 8)
        self.song.tracks[1].clip_slots[1].clip = clip
        self.song.tracks[1].playing_slot_index = 1
        self.song.is_playing = True
        self.settle(3)
        clip.playing_position = 2.0
        got = []
        for _ in range(3):
            got.extend(of_type(self.tick(), "progress"))
        self.assertEqual(len(got), 1)      # ~5 per second, only on change
        self.assertEqual(got[0]["items"], [[1, 2.0, 8.0]])
        self.song.is_playing = False
        got = []
        for _ in range(3):
            got.extend(of_type(self.tick(), "progress"))
        self.assertEqual(got[-1]["items"], [])


class BigSetTest(TrackerTestBase):

    def test_200_tracks_200_scenes_chunked(self):
        self.make(200, 200)
        long_name = "Clip name é音 " * 16   # truncated to 200 chars
        for t, track in enumerate(self.song.tracks):
            track.name = "Track with a fairly long name %d" % t
            for s, slot in enumerate(track.clip_slots):
                if (t + s) % 5 != 0:
                    slot.clip = FakeClip(long_name + str(s), 0xABCDEF, 16)
        for s in self.song.scenes:
            s.name = "Scene with a long name " * 3
        msgs = self.tracker.full_state()
        while self.tracker.bulk_pending():
            msgs.extend(self.tick())
        for m in msgs:
            self.assertLess(len(m), C.MAX_DATAGRAM_BYTES)
        decoded = decode(msgs)
        track_items = [i for m in decoded if m["type"] == "tracks"
                       for i in m["items"]]
        self.assertEqual(sorted({i["index"] for i in track_items}),
                         list(range(200)))
        self.assertEqual(sum(1 for m in decoded
                             if m["type"] == "tracks" and "master" in m), 1)
        scene_items = {i["index"] for m in decoded if m["type"] == "scenes"
                       for i in m["items"]}
        self.assertEqual(scene_items, set(range(200)))
        slots = {(m["track"], i["scene"]) for m in decoded
                 if m["type"] == "clips" for i in m["items"]}
        self.assertEqual(len(slots), 200 * 200)
        clip_msgs = [m for m in msgs if b'"clips"' in m[:20]]
        self.assertGreater(len(clip_msgs), 200)   # had to split some tracks

    def test_bulk_is_spread_over_ticks(self):
        self.make(200, 200)
        for track in self.song.tracks:
            for slot in track.clip_slots:
                slot.clip = FakeClip("x" * 40)
        first = self.tracker.full_state()
        self.assertLess(sum(len(m) for m in first),
                        C.BULK_BYTES_PER_TICK + C.MAX_DATAGRAM_BYTES * 2 + 200000)
        self.assertGreater(self.tracker.bulk_pending(), 0)

    def test_incremental_tick_is_budgeted(self):
        self.make(200, 200)
        self.settle(3)
        reads = {"n": 0}

        class CountingSlot(object):
            def __init__(self, inner):
                self.inner = inner

            @property
            def has_clip(self):
                reads["n"] += 1
                return self.inner.has_clip

        for t in range(200):
            self.tracker._slots[t] = [CountingSlot(s) for s in
                                      self.song.tracks[t].clip_slots]
        self.tick()
        self.assertLessEqual(reads["n"], C.SLOT_BUDGET + 200)


class ErrorIsolationTest(TrackerTestBase):

    def test_exception_in_one_track_does_not_escape(self):
        self.make(3, 2)
        self.settle()

        class Broken(FakeTrack):
            @property
            def name(self):
                raise RuntimeError("Object no longer exists")

            @name.setter
            def name(self, v):
                pass

        self.song.tracks[1] = Broken("x", 2)
        self.tracker.mark_structure_dirty()
        self.song.tracks[0].mute = True
        self.tracker.mark_track_dirty(0)
        msgs = decode(self.tick())         # must not raise
        self.assertTrue(any("Object no longer exists" in e for e in self.errors))
        items = [i for m in msgs if m["type"] == "tracks" for i in m["items"]]
        self.assertTrue(any(i["index"] == 0 and i["mute"] for i in items))

    def test_song_provider_exception(self):
        clock = FakeClock()
        errors = []

        def bad():
            raise RuntimeError("no song")
        tr = StateTracker(bad, clock=clock, report_error=errors.append)
        self.assertEqual(tr.tick(), [])
        self.assertEqual(tr.full_state(), [])
        self.assertTrue(errors)


if __name__ == "__main__":
    unittest.main()
