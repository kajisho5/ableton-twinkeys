"""Reads Live's state, caches it and produces diff messages.

Works with any object that looks like Live's Song (the unit tests use a fake
one). All Live reads happen here; every unit of work is wrapped so that an
exception from Live (e.g. an object deleted mid-tick) is reported and the
caches are rebuilt instead of the exception escaping into Live.
"""

import collections
import time

from . import constants as C
from .protocol import (encode, pack_items, contiguous_runs, format_beat,
                       color_hex, clean_name, finite, rnd)


def same(a, b):
    """Live hands out new Python wrappers for the same object; they compare
    equal with ==. Fakes compare by identity."""
    if a is b:
        return True
    try:
        return bool(a == b)
    except Exception:
        return False


def index_of(seq, obj, hint=-1):
    if obj is None:
        return -1
    if 0 <= hint < len(seq) and same(seq[hint], obj):
        return hint
    for i, item in enumerate(seq):
        if same(item, obj):
            return i
    return -1


def param_norm(param):
    """DeviceParameter value -> 0..1 using its min/max."""
    lo = finite(param.min)
    hi = finite(param.max, 1.0)
    v = finite(param.value)
    if hi <= lo:
        return 0.0
    return min(1.0, max(0.0, (v - lo) / (hi - lo)))


def param_pan(param):
    """DeviceParameter value -> -1..1 using its min/max."""
    return param_norm(param) * 2.0 - 1.0


def read_sends(mixer, limit=C.MAX_SENDS):
    """The first `limit` sends of a mixer as 0..1 (each from its parameter's
    min/max). Shorter, or empty, when the set has fewer return tracks."""
    sends = getattr(mixer, "sends", None)
    if sends is None:
        return []
    return [rnd(param_norm(sends[k])) for k in range(min(limit, len(sends)))]


def _clip_same(a, b):
    """Clip items are equal ignoring position_beats (it moves constantly;
    the "progress" message carries it)."""
    if a is None or b is None:
        return a is b
    for key in ("has_clip", "name", "color", "is_playing", "is_triggered",
                "length_beats"):
        if a.get(key) != b.get(key):
            return False
    return True


class StateTracker(object):

    def __init__(self, song_provider, clock=time.monotonic,
                 report_error=None, on_structure=None,
                 limit=C.MAX_DATAGRAM_BYTES, structure_seed=None):
        self._song_provider = song_provider
        self._clock = clock
        self._report = report_error or (lambda msg: None)
        self._on_structure = on_structure
        self._limit = limit

        self._tracks = []
        self._scenes = []
        self._master = None
        self._slots = []              # per track: list of clip slots or None

        self._song_row = None
        self._track_rows = []         # per track: dict or None
        self._track_audio = []        # per track: has_audio_output
        self._master_row = None
        self._scene_live = []         # per scene: name/color/triggered
        self._scene_rows = []         # per scene: last sent row
        self._clip_items = []         # per track: list of item dicts or None
        self._clip_bytes = []         # per track: encoded full column or None

        self._meters = {}             # track index -> (l, r) last sent
        self._master_meter = None
        self._progress = []

        self._dirty_tracks = set()
        self._dirty_scenes = set()
        # Clip slots to re-read because a track's playing/fired slot moved:
        # track index -> set of slot indices (at most 4 per change).
        self._clip_patches = {}
        # Whole clip columns to re-read (startup, structure change), spread
        # over ticks under SLOT_BUDGET.
        self._rescan = collections.deque()
        self._rescan_set = set()
        # Columns the bulk queue wanted while they were still being re-read.
        self._resend_after_read = set()
        self._structure_dirty = True
        self._full_requested = False
        # Structure counter: increases whenever the track or scene list
        # changes. Seeded from the wall clock so a reloaded script does not
        # reuse a value a client still holds.
        if structure_seed is None:
            structure_seed = int(time.time() * 1000) % 1000000000
        self._structure = int(structure_seed)
        self._initialized = False

        self._track_cursor = 0
        self._scene_cursor = 0
        self._clip_cursor = 0
        self._bulk = collections.deque()
        self._bulk_set = set()

        neg = -1e9
        self._last_state = neg
        self._last_full = neg
        self._last_meter = neg
        self._last_progress = neg
        self._last_structure = neg
        self._last_full_state = neg
        self._meter_until = neg
        self._sel_track_hint = -1
        self._sel_scene_hint = -1

    # ------------------------------------------------------------ dirty marks
    # Called from Live listeners: they only set flags, never touch Live.

    def mark_structure_dirty(self):
        self._structure_dirty = True

    def mark_track_dirty(self, index):
        """Re-read the track row next tick. Clip slots are re-read only if
        the row's playing/fired slot changed (see _store_track), so mixer
        automation does not cause clip column reads."""
        self._dirty_tracks.add(index)

    def mark_all_tracks_dirty(self):
        """Re-read every track row next tick: the return-track list changed,
        so every track's sends did. Rows only; clip columns are not re-read
        (see mark_track_dirty)."""
        self._dirty_tracks.update(range(len(self._tracks)))

    def mark_scene_dirty(self, index):
        self._dirty_scenes.add(index)

    def request_full_state(self):
        """Ask for the full state (for "hello"). Coalesced: any number of
        requests produce at most one full send per FULL_STATE_MIN_INTERVAL,
        done by the next tick() under the usual budgets."""
        self._full_requested = True

    @property
    def structure(self):
        return self._structure

    def current_structure(self):
        """The structure counter, after applying a structure change a Live
        listener has already reported (so a command arriving in the same
        tick as the change is checked against the new lists)."""
        if self._structure_dirty and self._initialized:
            song = self._song()
            if song is not None:
                self._guard("structure", self._refresh_structure, song,
                            self._clock(), False)
        return self._structure

    @property
    def tracks(self):
        return self._tracks

    @property
    def scenes(self):
        return self._scenes

    @property
    def master(self):
        return self._master

    # ------------------------------------------------------------ main entry

    def tick(self, now=None):
        """Called about every 100 ms. Returns a list of datagrams (bytes)."""
        if now is None:
            now = self._clock()
        out = []
        full = self._full_requested and \
            now - self._last_full_state >= C.FULL_STATE_MIN_INTERVAL
        if full or now - self._last_state >= C.STATE_INTERVAL:
            self._last_state = now
            song = self._song()
            if song is None:
                return out
            if full:
                self._full_requested = False
                self._last_full_state = now
                self._send_full_head(song, now, out)
            elif not self._initialized:
                self._guard("initial scan", self._full_scan, song, now, True)
            else:
                self._guard("structure", self._refresh_structure, song, now,
                            False)
            self._guard("song", self._update_song, song, out)
            self._guard("tracks", self._update_tracks, out)
            self._guard("scenes", self._update_scenes, out)
            self._guard("clips", self._update_clips, out)
            self._guard("meters", self._update_meters, song, now, out)
            self._guard("progress", self._update_progress, song, now, out,
                        False)
            if now - self._last_full >= C.FULL_RESEND_INTERVAL:
                self._last_full = now
                self._guard("full resend", self._full_from_cache, out)
        self._guard("bulk", self._drain_bulk, out)
        return out

    def full_state(self, now=None):
        """Request the full state and run one tick (tests / direct use).
        Song, tracks, scenes, meters and progress come at once; the clip
        columns are re-read and streamed by later ticks under the budgets."""
        self.request_full_state()
        return self.tick(now)

    def _send_full_head(self, song, now, out):
        self._guard("full scan", self._full_scan, song, now,
                    not self._initialized)
        self._last_full = now
        self._guard("full", self._full_from_cache, out)
        self._meters = {}
        self._master_meter = None
        self._last_meter = now
        self._guard("meters", self._send_meters, song, out, True)
        self._guard("progress", self._update_progress, song, now, out, True)

    def bulk_pending(self):
        """Clip columns still to be re-read or sent."""
        return len(self._bulk) + len(self._rescan)

    # ------------------------------------------------------------ helpers

    def _song(self):
        try:
            return self._song_provider()
        except Exception as exc:
            self._report("cannot access song: %s" % exc)
            return None

    def _guard(self, where, fn, *args):
        try:
            return fn(*args)
        except Exception as exc:
            self._report("%s: %s: %s" % (where, type(exc).__name__, exc))
            self._structure_dirty = True
            return None

    def _pack(self, base, items, start=True, first_extra=None):
        return pack_items(base, items,
                          start_of=(lambda it: it["index"]) if start else None,
                          first_extra=first_extra, limit=self._limit)

    # ------------------------------------------------------------ structure

    def _refresh_structure(self, song, now, force):
        if not (force or self._structure_dirty
                or now - self._last_structure >= C.STRUCTURE_CHECK_INTERVAL):
            return
        self._last_structure = now
        self._structure_dirty = False
        tracks = list(song.tracks)
        scenes = list(song.scenes)
        master = song.master_track
        old_tracks = self._tracks
        scenes_changed = len(scenes) != len(self._scenes) or any(
            not same(a, b) for a, b in zip(scenes, self._scenes))
        changed_tracks = [i for i in range(len(tracks))
                          if i >= len(old_tracks)
                          or not same(tracks[i], old_tracks[i])]
        tracks_changed = bool(changed_tracks) or len(tracks) != len(old_tracks)
        master_changed = self._master is None or not same(master, self._master)
        if not (force or scenes_changed or tracks_changed or master_changed):
            return

        if scenes_changed or tracks_changed:
            self._structure += 1
        n = len(tracks)
        self._tracks = tracks
        self._scenes = scenes
        self._master = master

        def resize(lst, size, fill=None):
            del lst[size:]
            lst.extend([fill] * (size - len(lst)))

        for lst in (self._slots, self._track_rows, self._clip_items,
                    self._clip_bytes):
            resize(lst, n)
        resize(self._track_audio, n, False)
        # Drop queued work for indices that no longer exist.
        self._rescan = collections.deque(t for t in self._rescan if t < n)
        self._rescan_set = set(self._rescan)
        self._resend_after_read = set(t for t in self._resend_after_read
                                      if t < n)
        reset = range(n) if force else changed_tracks
        for i in reset:
            self._slots[i] = None
            self._track_rows[i] = None
            self._clip_items[i] = None
            self._clip_bytes[i] = None
            self._dirty_tracks.add(i)
            self._queue_rescan(i)
        if scenes_changed and not force:
            # Same tracks, new scene list: every column must be re-read, but
            # under SLOT_BUDGET over several ticks (the old column stays
            # cached until its re-read replaces it).
            for i in range(n):
                self._slots[i] = None
                self._queue_rescan(i)
        self._dirty_tracks = set(i for i in self._dirty_tracks if i < n)
        self._clip_patches = dict((t, v) for t, v in self._clip_patches.items()
                                  if t < n)
        self._meters = dict((k, v) for k, v in self._meters.items() if k < n)
        if scenes_changed or force:
            m = len(scenes)
            resize(self._scene_live, m)
            resize(self._scene_rows, m)
            for s in range(m):
                self._scene_live[s] = None
                self._scene_rows[s] = None
                self._dirty_scenes.add(s)
        self._dirty_scenes = set(s for s in self._dirty_scenes
                                 if s < len(scenes))
        self._bulk = collections.deque(t for t in self._bulk if t < n)
        self._bulk_set = set(self._bulk)
        if master_changed:
            self._master_row = None
        if not (scenes_changed or tracks_changed or master_changed
                or not self._initialized):
            return
        if self._on_structure is not None:
            try:
                self._on_structure(song, tracks, scenes, master)
            except Exception as exc:
                self._report("listener rebind: %s" % exc)

    def _get_slots(self, t):
        slots = self._slots[t]
        if slots is None:
            slots = list(self._tracks[t].clip_slots)
            self._slots[t] = slots
        return slots

    def _queue_rescan(self, t, front=False):
        if t in self._rescan_set:
            if front and self._rescan and self._rescan[0] != t:
                self._rescan.remove(t)
                self._rescan.appendleft(t)
            return
        self._rescan_set.add(t)
        if front:
            self._rescan.appendleft(t)
        else:
            self._rescan.append(t)

    def _full_scan(self, song, now, force):
        """Re-read the song, master, track and scene rows. Clip columns are
        not read here: columns without a cache are queued and re-read by
        _update_clips under SLOT_BUDGET."""
        self._refresh_structure(song, now, force)
        self._song_row = self._read_song(song)
        self._master_row = self._read_master()
        for i in range(len(self._tracks)):
            self._guard("track %d" % i, self._store_track, i)
        for s in range(len(self._scenes)):
            self._guard("scene %d" % s, self._store_scene_live, s)
        self._compose_scenes()
        self._dirty_tracks.clear()
        self._dirty_scenes.clear()
        self._initialized = True

    # ------------------------------------------------------------ song

    def _read_song(self, song):
        num = song.signature_numerator
        den = song.signature_denominator
        view = song.view
        sel_t = view.selected_track
        if sel_t is not None and self._master is not None \
                and same(sel_t, self._master):
            sel_track = -1
        else:
            sel_track = index_of(self._tracks, sel_t, self._sel_track_hint)
            if sel_track < 0 and sel_t is not None:
                sel_track = -2    # a return track (or not a session track)
            else:
                self._sel_track_hint = sel_track
        sel_scene = index_of(self._scenes, view.selected_scene,
                             self._sel_scene_hint)
        self._sel_scene_hint = sel_scene
        set_name = ""
        try:
            set_name = clean_name(getattr(song, "name", "") or "")
        except Exception:
            set_name = ""
        return {
            "type": "song",
            "tempo": rnd(song.tempo, 3),
            "playing": bool(song.is_playing),
            "beat": format_beat(song.current_song_time, num, den),
            "sig": [int(num), int(den)],
            "selected_track": sel_track,
            "selected_scene": sel_scene,
            "set_name": set_name,
            "tracks": len(self._tracks),
            "scenes": len(self._scenes),
            "structure": self._structure,
        }

    def _update_song(self, song, out):
        row = self._read_song(song)
        if row != self._song_row:
            self._song_row = row
            out.append(encode(row))

    # ------------------------------------------------------------ tracks

    def _read_track(self, i):
        track = self._tracks[i]
        mixer = track.mixer_device
        playing = int(track.playing_slot_index)
        fired = int(track.fired_slot_index)
        foldable = bool(track.is_foldable)
        try:
            self._track_audio[i] = bool(track.has_audio_output)
        except Exception:
            self._track_audio[i] = False
        return {
            "index": i,
            "name": clean_name(track.name),
            "color": color_hex(track.color),
            "volume": rnd(param_norm(mixer.volume)),
            "pan": rnd(param_pan(mixer.panning)),
            "sends": read_sends(mixer),
            "mute": bool(track.mute),
            "solo": bool(track.solo),
            "playing_slot": playing if playing >= 0 else -1,
            "fired_slot": fired if fired >= 0 else -1,
            "stop_fired": fired == -2,
            "is_group": foldable,
            "is_foldable": foldable,
            "is_grouped": bool(track.is_grouped),
        }

    def _store_track(self, i):
        row = self._read_track(i)
        old = self._track_rows[i]
        self._track_rows[i] = row
        if old is None:
            if self._clip_items[i] is None:
                self._queue_rescan(i)
        elif old["playing_slot"] != row["playing_slot"] \
                or old["fired_slot"] != row["fired_slot"]:
            # Only the slots that started/stopped playing or blinking.
            slots = self._clip_patches.setdefault(i, set())
            for s in (old["playing_slot"], row["playing_slot"],
                      old["fired_slot"], row["fired_slot"]):
                if s >= 0:
                    slots.add(s)
        return row != old

    def _read_master(self):
        if self._master is None:
            return None
        mixer = self._master.mixer_device
        return {"volume": rnd(param_norm(mixer.volume)),
                "pan": rnd(param_pan(mixer.panning))}

    def _round_robin(self, cursor, count, budget):
        if count == 0:
            return [], 0
        k = min(budget, count)
        idx = [(cursor + j) % count for j in range(k)]
        return idx, (cursor + k) % count

    def _update_tracks(self, out):
        n = len(self._tracks)
        rr, self._track_cursor = self._round_robin(
            self._track_cursor, n, C.TRACK_BUDGET)
        todo = sorted(set(i for i in self._dirty_tracks if i < n) | set(rr))
        self._dirty_tracks.clear()
        changed = []
        for i in todo:
            if self._guard("track %d" % i, self._store_track, i):
                changed.append(i)
        master = self._guard("master", self._read_master)
        master_changed = master is not None and master != self._master_row
        if master_changed:
            self._master_row = master
        if not changed and not master_changed:
            return
        extra = {"master": self._master_row} if self._master_row else None
        if not changed:
            out.extend(self._pack({"type": "tracks"}, [], first_extra=extra))
            return
        for run in contiguous_runs(changed):
            items = [self._track_rows[i] for i in run]
            out.extend(self._pack({"type": "tracks"}, items, first_extra=extra))
            extra = None

    # ------------------------------------------------------------ scenes

    def _store_scene_live(self, s):
        scene = self._scenes[s]
        self._scene_live[s] = {"name": clean_name(scene.name),
                               "color": color_hex(scene.color),
                               "triggered": bool(scene.is_triggered)}

    def _compose_scenes(self):
        """Scene "playing" = at least one clip in that scene row is playing
        (derived from each track's playing_slot_index). Returns changed
        indices."""
        playing = set(r["playing_slot"] for r in self._track_rows
                      if r is not None and r["playing_slot"] >= 0)
        changed = []
        for s, live in enumerate(self._scene_live):
            if live is None:
                continue
            row = {"index": s, "name": live["name"], "color": live["color"],
                   "triggered": live["triggered"], "playing": s in playing}
            if row != self._scene_rows[s]:
                self._scene_rows[s] = row
                changed.append(s)
        return changed

    def _update_scenes(self, out):
        m = len(self._scenes)
        rr, self._scene_cursor = self._round_robin(
            self._scene_cursor, m, C.SCENE_BUDGET)
        todo = sorted(set(s for s in self._dirty_scenes if s < m) | set(rr))
        self._dirty_scenes.clear()
        for s in todo:
            self._guard("scene %d" % s, self._store_scene_live, s)
        changed = self._compose_scenes()
        for run in contiguous_runs(changed):
            out.extend(self._pack({"type": "scenes"},
                                  [self._scene_rows[s] for s in run]))

    # ------------------------------------------------------------ clips

    @staticmethod
    def _read_slot(slot, s, playing, fired):
        if slot.has_clip:
            clip = slot.clip
            return {
                "scene": s, "has_clip": True,
                "name": clean_name(clip.name),
                "color": color_hex(clip.color),
                "is_playing": s == playing,
                "is_triggered": s == fired,
                "length_beats": rnd(clip.length, 3),
                "position_beats": rnd(clip.playing_position, 3)
                if s == playing else 0.0,
            }
        return {
            "scene": s, "has_clip": False, "name": "",
            "color": None, "is_playing": False,
            "is_triggered": s == fired,
            "length_beats": 0.0, "position_beats": 0.0,
        }

    def _read_clips(self, t):
        track = self._tracks[t]
        slots = self._get_slots(t)
        playing = int(track.playing_slot_index)
        fired = int(track.fired_slot_index)
        return [self._read_slot(slot, s, playing, fired)
                for s, slot in enumerate(slots)]

    def _store_clips(self, t):
        """Re-read one track's clip column; returns the changed items."""
        items = self._read_clips(t)
        old = self._clip_items[t]
        self._clip_items[t] = items
        if old is None or len(old) != len(items):
            self._clip_bytes[t] = None
            return items
        changed = [it for it, prev in zip(items, old)
                   if not _clip_same(it, prev)]
        if changed:
            self._clip_bytes[t] = None
        else:
            # Keep the last sent positions so the cache stays stable.
            self._clip_items[t] = old
        return changed

    def _patch_clips(self, t, indices):
        """Re-read only the given slots of a cached column (playing/fired
        slot change). Returns the changed items, or None if the column has
        to be re-read in full."""
        items = self._clip_items[t]
        row = self._track_rows[t]
        if items is None or row is None or t in self._rescan_set:
            return None
        slots = self._get_slots(t)
        if len(slots) != len(items):
            return None
        playing = row["playing_slot"]
        fired = row["fired_slot"]
        new_items = None
        changed = []
        for s in sorted(indices):
            if not 0 <= s < len(items):
                continue
            item = self._read_slot(slots[s], s, playing, fired)
            if not _clip_same(item, items[s]):
                if new_items is None:
                    new_items = list(items)
                new_items[s] = item
                changed.append(item)
        if new_items is not None:
            self._clip_items[t] = new_items
            self._clip_bytes[t] = None
        return changed

    def _read_column(self, t, out, full_send):
        """Re-read column t. A column read for the first time (or whose
        length changed) goes to the bulk queue, which sends it under the
        byte budget; otherwise only the changed items are sent now."""
        old = self._clip_items[t]
        changed = self._guard("clips %d" % t, self._store_clips, t)
        if changed is None:
            return
        new = self._clip_items[t]
        if full_send or old is None or new is None or len(old) != len(new):
            self._enqueue_bulk(t)
        elif changed:
            out.extend(self._pack({"type": "clips", "track": t}, changed,
                                  start=False))

    def _update_clips(self, out):
        n = len(self._tracks)
        if n == 0:
            return
        spent = 0
        done = set()
        # 1. Playing/fired changes: a few slots per track, never a column.
        patches, self._clip_patches = self._clip_patches, {}
        for t in sorted(patches):
            if t >= n:
                continue
            changed = self._guard("clips %d" % t, self._patch_clips, t,
                                  patches[t])
            spent += len(patches[t])
            if changed is None:
                self._queue_rescan(t, front=True)   # re-read it first
            elif changed:
                out.extend(self._pack({"type": "clips", "track": t}, changed,
                                      start=False))
        # 2. Whole columns queued by startup / structure changes.
        while self._rescan and spent < C.SLOT_BUDGET:
            t = self._rescan.popleft()
            self._rescan_set.discard(t)
            if t >= n:
                continue
            full_send = t in self._resend_after_read
            self._resend_after_read.discard(t)
            self._read_column(t, out, full_send)
            done.add(t)
            spent += max(1, len(self._scenes))
        # 3. Round robin with what is left of the budget.
        visited = 0
        while visited < n and spent < C.SLOT_BUDGET:
            t = self._clip_cursor % n
            self._clip_cursor = (t + 1) % n
            visited += 1
            if t in done:
                continue
            self._read_column(t, out, False)
            spent += max(1, len(self._scenes))

    def _clip_column(self, t):
        data = self._clip_bytes[t]
        if data is None:
            items = self._clip_items[t] or []
            data = self._pack({"type": "clips", "track": t}, items,
                              start=False)
            self._clip_bytes[t] = data
        return data

    def _enqueue_bulk(self, t):
        if t not in self._bulk_set:
            self._bulk.append(t)
            self._bulk_set.add(t)

    def _drain_bulk(self, out):
        spent = 0
        while self._bulk and spent < C.BULK_BYTES_PER_TICK:
            t = self._bulk.popleft()
            self._bulk_set.discard(t)
            if t >= len(self._tracks):
                continue
            if self._clip_items[t] is None or t in self._rescan_set:
                # Not read yet (or being re-read): sent once it is read.
                self._resend_after_read.add(t)
                self._queue_rescan(t)
                continue
            for chunk in self._clip_column(t):
                out.append(chunk)
                spent += len(chunk)

    # ------------------------------------------------------------ full state

    def _full_from_cache(self, out):
        if self._song_row is not None:
            out.append(encode(self._song_row))
        rows = [r for r in self._track_rows if r is not None]
        extra = {"master": self._master_row} if self._master_row else None
        out.extend(self._pack({"type": "tracks"}, rows, first_extra=extra))
        scenes = [r for r in self._scene_rows if r is not None]
        out.extend(self._pack({"type": "scenes"}, scenes))
        for t in range(len(self._tracks)):
            self._enqueue_bulk(t)

    # ------------------------------------------------------------ meters

    def _update_meters(self, song, now, out):
        if bool(song.is_playing):
            self._meter_until = now + C.METER_TAIL
        if now > self._meter_until:
            return
        if now - self._last_meter < C.METER_INTERVAL:
            return
        self._last_meter = now
        self._send_meters(song, out, False)

    def _send_meters(self, song, out, force):
        items = []
        for i, track in enumerate(self._tracks):
            if not self._track_audio[i]:
                continue
            try:
                l = rnd(track.output_meter_left, 3)
                r = rnd(track.output_meter_right, 3)
            except Exception:
                continue
            prev = self._meters.get(i)
            if force or prev is None \
                    or abs(prev[0] - l) > C.METER_THRESHOLD \
                    or abs(prev[1] - r) > C.METER_THRESHOLD:
                self._meters[i] = (l, r)
                items.append([i, l, r])
        master = [0.0, 0.0]
        if self._master is not None:
            master = [rnd(self._master.output_meter_left, 3),
                      rnd(self._master.output_meter_right, 3)]
        prev = self._master_meter
        master_changed = prev is None \
            or abs(prev[0] - master[0]) > C.METER_THRESHOLD \
            or abs(prev[1] - master[1]) > C.METER_THRESHOLD
        if not (force or items or master_changed):
            return
        if master_changed or force:
            self._master_meter = master
        out.extend(pack_items({"type": "meters"}, items,
                              first_extra={"master": self._master_meter},
                              limit=self._limit))

    # ------------------------------------------------------------ progress

    def _update_progress(self, song, now, out, force):
        if not force and now - self._last_progress < C.PROGRESS_INTERVAL:
            return
        self._last_progress = now
        items = []
        if bool(song.is_playing):
            for t, row in enumerate(self._track_rows):
                if row is None or row["playing_slot"] < 0:
                    continue
                try:
                    slots = self._get_slots(t)
                    ps = row["playing_slot"]
                    if ps >= len(slots):
                        continue
                    clip = slots[ps].clip
                    if clip is None:
                        continue
                    items.append([t, rnd(clip.playing_position, 3),
                                  rnd(clip.length, 3)])
                except Exception:
                    self._dirty_tracks.add(t)
        if items == self._progress and not force:
            return
        self._progress = items
        out.extend(pack_items({"type": "progress"}, items, limit=self._limit))
