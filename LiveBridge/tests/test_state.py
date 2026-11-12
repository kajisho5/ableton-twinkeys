import json
import unittest

from TwinKeysBridge import constants as C
from TwinKeysBridge.state import StateTracker
from tests.fake_live import (FakeSong, FakeClock, FakeClip, FakeTrack,
                             FakeScene, FakeClipSlot, FakeParameter)


def decode(msgs):
    return [json.loads(m.decode("utf-8")) for m in msgs]


def of_type(msgs, t):
    return [m for m in decode(msgs) if m["type"] == t]


class TrackerTestBase(unittest.TestCase):

    def make(self, tracks=4, scenes=4, returns=0):
        self.song = FakeSong(tracks, scenes, returns)
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
        self.assertEqual(msgs[0]["bridge_version"], C.BRIDGE_VERSION)

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
        self.assertLess(C.MAX_DATAGRAM_BYTES, 9216)
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


class CountingSlot(object):
    def __init__(self, inner, reads):
        self.inner = inner
        self.reads = reads

    @property
    def has_clip(self):
        self.reads["n"] += 1
        return self.inner.has_clip

    @property
    def clip(self):
        return self.inner.clip


class BurstTest(TrackerTestBase):
    """Structure changes, hello and mixer changes stay within the budgets."""

    def big(self, returns=0):
        self.make(200, 200, returns)
        for t, track in enumerate(self.song.tracks):
            for s, slot in enumerate(track.clip_slots):
                if (t + s) % 3:
                    slot.clip = FakeClip("clip %d/%d" % (t, s), 0x123456, 8)
        self.drain()

    def drain(self):
        msgs = []
        for _ in range(200):
            msgs.extend(self.tick())
            if not self.tracker.bulk_pending():
                break
        self.assertEqual(self.tracker.bulk_pending(), 0)
        return msgs

    def count_reads(self):
        """Count has_clip reads, also for slot lists re-listed later."""
        reads = {"n": 0}
        tr = self.tracker
        for t in range(len(tr._slots)):
            tr._slots[t] = [CountingSlot(x, reads) for x in
                            tr.tracks[t].clip_slots]
        real = tr._get_slots

        def counting(t):
            if tr._slots[t] is None:
                tr._slots[t] = [CountingSlot(x, reads) for x in
                                tr.tracks[t].clip_slots]
            return real(t)
        tr._get_slots = counting
        return reads

    def assertTickBounded(self, msgs):
        size = sum(len(m) for m in msgs)
        # bulk budget + one column of overshoot + song/tracks/scenes rows
        self.assertLess(size, C.BULK_BYTES_PER_TICK + 150000)

    def test_scene_insert_is_spread_over_ticks(self):
        self.big()
        self.song.scenes.insert(0, FakeScene("New"))
        for track in self.song.tracks:
            track.clip_slots.insert(0, FakeClipSlot(FakeClip("Top")))
        self.tracker.mark_structure_dirty()
        reads = self.count_reads()
        all_msgs = []
        ticks = 0
        while True:
            reads["n"] = 0
            msgs = self.tick()
            ticks += 1
            self.assertLessEqual(reads["n"], C.SLOT_BUDGET + 201)
            self.assertTickBounded(msgs)
            all_msgs.extend(msgs)
            if not self.tracker.bulk_pending():
                break
            self.assertLess(ticks, 100)
        self.assertGreater(ticks, 10)       # it really was spread out
        cols = {}
        for m in decode(all_msgs):
            if m["type"] == "clips":
                for it in m["items"]:
                    cols.setdefault(m["track"], {})[it["scene"]] = it
        self.assertEqual(sorted(cols), list(range(200)))
        for t, items in cols.items():
            self.assertEqual(len(items), 201)
            self.assertEqual(items[0]["name"], "Top")
            want = "clip %d/%d" % (t, 0) if t % 3 else ""
            self.assertEqual(items[1]["name"], want)

    def test_track_insert_is_bounded(self):
        self.big()
        self.song.tracks.insert(0, FakeTrack("New", 200))
        self.tracker.mark_structure_dirty()
        reads = self.count_reads()
        msgs = self.tick()
        self.assertTickBounded(msgs)
        self.assertGreater(reads["n"], 0)
        self.assertLessEqual(reads["n"], C.SLOT_BUDGET + 200)
        self.assertGreater(self.tracker.bulk_pending(), 0)
        names = [i["name"] for m in decode(msgs + self.drain())
                 if m["type"] == "clips" and m["track"] == 1
                 for i in m["items"] if i["scene"] == 1]
        self.assertEqual(names[-1], "clip 0/1")

    def test_hello_on_big_set_is_bounded(self):
        self.big()
        reads = self.count_reads()
        msgs = self.tracker.full_state()
        self.assertTickBounded(msgs)
        self.assertLessEqual(reads["n"], C.SLOT_BUDGET + 200)
        self.assertGreater(self.tracker.bulk_pending(), 0)
        self.drain()

    def test_mixer_change_does_not_reread_clips(self):
        self.big()
        reads = self.count_reads()
        for i, track in enumerate(self.song.tracks):
            track.mixer_device.volume.value = 0.3
            self.tracker.mark_track_dirty(i)    # as the volume listener does
        msgs = decode(self.tick())
        items = [i for m in msgs if m["type"] == "tracks" for i in m["items"]]
        self.assertEqual(len(items), 200)
        # only the round-robin slice, not 200 columns
        self.assertLessEqual(reads["n"], C.SLOT_BUDGET + 200)
        self.assertEqual(self.tracker._clip_patches, {})
        self.assertEqual(self.tracker.bulk_pending(), 0)
        self.assertEqual([m for m in msgs if m["type"] == "clips"], [])

    def test_send_change_does_not_reread_clips(self):
        self.big(returns=2)
        reads = self.count_reads()
        for i, track in enumerate(self.song.tracks):
            track.mixer_device.sends[i % 2].value = 0.6
            self.tracker.mark_track_dirty(i)    # as the send listener does
        msgs = decode(self.tick())
        items = [i for m in msgs if m["type"] == "tracks" for i in m["items"]]
        self.assertEqual(len(items), 200)
        self.assertEqual(items[3]["sends"], [0.0, 0.6])
        self.assertLessEqual(reads["n"], C.SLOT_BUDGET + 200)
        self.assertEqual(self.tracker._clip_patches, {})
        self.assertEqual(self.tracker.bulk_pending(), 0)
        self.assertEqual([m for m in msgs if m["type"] == "clips"], [])

    def test_return_track_change_rereads_rows_not_clips(self):
        self.big(returns=1)
        reads = self.count_reads()
        structure = self.tracker.structure
        self.song.return_tracks.insert(0, FakeTrack("New return"))
        for track in self.song.tracks:
            track.mixer_device.sends.insert(0, FakeParameter(0.5, 0.0, 1.0))
        self.tracker.mark_all_tracks_dirty()  # as the return_tracks listener
        msgs = decode(self.tick())
        items = [i for m in msgs if m["type"] == "tracks" for i in m["items"]]
        self.assertEqual(len(items), 200)
        self.assertEqual(set(tuple(i["sends"]) for i in items), {(0.5, 0.0)})
        self.assertLessEqual(reads["n"], C.SLOT_BUDGET + 200)
        self.assertEqual(self.tracker.bulk_pending(), 0)
        self.assertEqual([m for m in msgs if m["type"] == "clips"], [])
        # Send indices are positions, not a track/scene layout change.
        self.assertEqual(self.tracker.structure, structure)

    def test_play_change_reads_only_affected_slots(self):
        self.make(3, 50)
        self.song.tracks[1].clip_slots[7].clip = FakeClip("P", 1, 4)
        self.settle()
        patched = []
        real = self.tracker._patch_clips
        self.tracker._patch_clips = lambda t, idx: (
            patched.append((t, sorted(idx))) or real(t, idx))
        self.song.tracks[1].playing_slot_index = 7
        self.tracker.mark_track_dirty(1)
        clips = of_type(self.tick(), "clips")
        self.assertEqual(patched, [(1, [7])])
        self.assertEqual([(m["track"], [i["scene"] for i in m["items"]])
                          for m in clips], [(1, [7])])
        self.assertTrue(clips[0]["items"][0]["is_playing"])
        self.song.tracks[1].playing_slot_index = -1
        self.song.tracks[1].fired_slot_index = 9
        self.tracker.mark_track_dirty(1)
        clips = of_type(self.tick(), "clips")
        self.assertEqual(patched[-1], (1, [7, 9]))
        got = {i["scene"]: i for i in clips[0]["items"]}
        self.assertFalse(got[7]["is_playing"])
        self.assertTrue(got[9]["is_triggered"])


class SendTest(TrackerTestBase):

    def track_items(self, msgs):
        return dict((i["index"], i) for m in of_type(msgs, "tracks")
                    for i in m["items"])

    def test_tracks_report_the_first_two_sends(self):
        self.make(3, 2, returns=3)
        sends = self.song.tracks[1].mixer_device.sends
        sends[0].value, sends[1].value, sends[2].value = 0.25, 0.5, 0.9
        items = self.track_items(self.tick())
        self.assertEqual(items[1]["sends"], [0.25, 0.5])   # Send C not sent
        self.assertEqual(items[0]["sends"], [0.0, 0.0])

    def test_fewer_return_tracks_give_a_shorter_list(self):
        for returns, want in ((0, []), (1, [0.0])):
            self.make(2, 1, returns=returns)
            items = self.track_items(self.tick())
            self.assertEqual([items[t]["sends"] for t in (0, 1)],
                             [want, want])

    def test_send_is_normalised_from_parameter_range(self):
        self.make(1, 1, returns=1)
        p = self.song.tracks[0].mixer_device.sends[0]
        p.min, p.max, p.value = -2.0, 2.0, 1.0
        self.assertEqual(self.track_items(self.tick())[0]["sends"], [0.75])

    def test_master_has_no_sends(self):
        self.make(2, 1, returns=2)
        tracks = of_type(self.tick(), "tracks")[0]
        self.assertEqual(set(tracks["master"]), {"volume", "pan"})

    def test_send_change_sends_only_that_track_row(self):
        self.make(10, 3, returns=2)
        self.settle()
        self.song.tracks[6].mixer_device.sends[1].value = 0.4
        self.tracker.mark_track_dirty(6)   # as the send listener does
        msgs = decode(self.tick())
        self.assertEqual([m["type"] for m in msgs], ["tracks"])
        self.assertEqual([i["index"] for i in msgs[0]["items"]], [6])
        self.assertEqual(msgs[0]["items"][0]["sends"], [0.0, 0.4])

    def test_send_change_found_by_polling_without_listener(self):
        self.make(4, 2, returns=2)
        self.settle()
        self.song.tracks[3].mixer_device.sends[0].value = 0.3
        found = []
        for _ in range(5):
            found.extend(of_type(self.tick(), "tracks"))
        self.assertEqual(found[0]["items"][0]["sends"], [0.3, 0.0])


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
