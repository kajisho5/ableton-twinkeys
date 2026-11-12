"""Live listeners that only mark the StateTracker dirty.

Live's API exposes add_<prop>_listener / remove_<prop>_listener /
<prop>_has_listener for observable properties. Callbacks here never change
Live's state (Live forbids changes from inside notifications); they only set
flags that the next update_display tick acts on. Polling in StateTracker
remains the fallback, so a missing listener only delays an update.

On a structure change the binder keeps the listeners of tracks and scenes
that are still there (it only updates the index their callback marks) and
queues add/remove calls for the ones that came or went. pump() runs at most
LISTENER_OPS_PER_TICK of those calls per tick, so a big set never re-adds
thousands of listeners in one tick.

Sends: each track's first MAX_SENDS sends get a value listener (it marks the
track row dirty, like volume and pan, so it never re-reads clips). When the
return-track list changes, every track's sends change with it: the Song's
return_tracks listener re-marks every track row and queues a rebind of the
send listeners only, under the same per-tick budget.
"""

import collections

from . import constants as C


def _same(a, b):
    if a is b:
        return True
    try:
        return bool(a == b)
    except Exception:
        return False


def _remove(obj, prop, callback):
    try:
        has = getattr(obj, "%s_has_listener" % prop, None)
        if has is not None and not has(callback):
            return
        getattr(obj, "remove_%s_listener" % prop)(callback)
    except Exception:
        pass  # object already deleted: nothing to remove


class ListenerRegistry(object):

    def __init__(self, report=None):
        self._entries = []
        self._report = report or (lambda msg: None)

    def __len__(self):
        return len(self._entries)

    def add(self, obj, prop, callback):
        adder = getattr(obj, "add_%s_listener" % prop, None)
        if adder is None:
            return False
        try:
            adder(callback)
        except Exception as exc:
            self._report("add %s listener: %s" % (prop, exc))
            return False
        self._entries.append((obj, prop, callback))
        return True

    def clear(self):
        entries, self._entries = self._entries, []
        for obj, prop, callback in entries:
            _remove(obj, prop, callback)


class _Cell(object):
    """The current index of a bound track/scene. Callbacks read it, so a
    moved object keeps its listeners and only the index changes."""
    __slots__ = ("index",)

    def __init__(self, index):
        self.index = index


class _Entry(object):
    __slots__ = ("obj", "cell", "targets", "sends")

    def __init__(self, obj, index):
        self.obj = obj
        self.cell = _Cell(index)
        self.targets = []           # (object, prop, callback) actually added
        self.sends = []             # the same for send values (rebound alone)


class LiveListenerBinder(object):

    SONG_PROPS = ("tracks", "scenes")
    RETURNS_PROP = "return_tracks"  # every track's sends change with it
    TRACK_PROPS = ("name", "color", "mute", "solo", "playing_slot_index",
                   "fired_slot_index")
    SCENE_PROPS = ("name", "color", "is_triggered")
    MATCH_WINDOW = 8                # how far a moved object is searched for

    def __init__(self, tracker, report=None,
                 ops_per_tick=C.LISTENER_OPS_PER_TICK):
        self._tracker = tracker
        self._report = report or (lambda msg: None)
        self._song_listeners = ListenerRegistry(report)
        self._song = None
        self._ops_per_tick = ops_per_tick
        self._tracks = []           # _Entry per current track
        self._scenes = []           # _Entry per current scene
        # ("bind", kind, entry) / ("sends", None, entry) / ("unbind", None, entry)
        self._ops = collections.deque()
        self._sends_dirty = False

    def pending(self):
        return len(self._ops) + (1 if self._sends_dirty else 0)

    def rebind(self, song, tracks, scenes, master):
        if self._song is None or not _same(self._song, song):
            self._song_listeners.clear()
            self._song = song
            for prop in self.SONG_PROPS:
                self._song_listeners.add(song, prop,
                                         self._tracker.mark_structure_dirty)
            self._song_listeners.add(song, self.RETURNS_PROP,
                                     self._on_returns_changed)
        self._tracks = self._match(self._tracks, list(tracks), "track")
        self._scenes = self._match(self._scenes, list(scenes), "scene")

    def _find(self, old, used, obj, i, offset):
        n = len(old)
        for j in (i + offset, i):
            if 0 <= j < n and not used[j] and _same(old[j].obj, obj):
                return j
        c = i + offset
        for j in range(max(0, c - self.MATCH_WINDOW),
                       min(n, c + self.MATCH_WINDOW + 1)):
            if not used[j] and _same(old[j].obj, obj):
                return j
        return -1

    def _match(self, old, objs, kind):
        used = [False] * len(old)
        new = []
        offset = 0
        for i, obj in enumerate(objs):
            j = self._find(old, used, obj, i, offset)
            if j >= 0:
                used[j] = True
                offset = j - i
                entry = old[j]
                entry.cell.index = i
            else:
                entry = _Entry(obj, i)
                self._ops.append(("bind", kind, entry))
            new.append(entry)
        for j, entry in enumerate(old):
            if not used[j]:
                entry.cell.index = -1      # its callback is now a no-op
                self._ops.append(("unbind", None, entry))
        return new

    def _on_returns_changed(self):
        """Song.return_tracks listener: only sets flags. The track rows are
        re-read next tick and the send listeners rebound by pump()."""
        self._sends_dirty = True
        self._tracker.mark_all_tracks_dirty()

    def pump(self, budget=None):
        """Run queued add/remove calls, at most `budget` per call."""
        if budget is None:
            budget = self._ops_per_tick
        if self._sends_dirty:
            self._sends_dirty = False
            for entry in self._tracks:
                self._ops.append(("sends", None, entry))
        spent = 0
        while self._ops and spent < budget:
            op, kind, entry = self._ops.popleft()
            if op == "bind":
                spent += self._bind(entry, kind)
            elif op == "sends":
                spent += self._rebind_sends(entry)
            else:
                spent += self._unbind(entry)
        return spent

    def _add(self, targets, obj, prop, callback):
        adder = getattr(obj, "add_%s_listener" % prop, None)
        if adder is None:
            return
        try:
            adder(callback)
        except Exception as exc:
            self._report("add %s listener: %s" % (prop, exc))
            return
        targets.append((obj, prop, callback))

    def _bind(self, entry, kind):
        if entry.cell.index < 0:
            return 0                       # removed before it was bound
        if kind == "track":
            cb = self._track_callback(entry.cell)
            for prop in self.TRACK_PROPS:
                self._add(entry.targets, entry.obj, prop, cb)
            try:
                mixer = entry.obj.mixer_device
                # Mixer changes only re-read the track row, never clips.
                self._add(entry.targets, mixer.volume, "value", cb)
                self._add(entry.targets, mixer.panning, "value", cb)
            except Exception:
                pass
            return len(self.TRACK_PROPS) + 2 + self._bind_sends(entry, cb)
        cb = self._scene_callback(entry.cell)
        for prop in self.SCENE_PROPS:
            self._add(entry.targets, entry.obj, prop, cb)
        return len(self.SCENE_PROPS)

    def _bind_sends(self, entry, cb):
        """Value listeners on the track's first MAX_SENDS sends (like volume:
        they only re-read the track row). Returns the listener calls made."""
        try:
            sends = entry.obj.mixer_device.sends
            params = [sends[k] for k in range(min(C.MAX_SENDS, len(sends)))]
        except Exception:
            return 0                       # polling still reads the sends
        for param in params:
            self._add(entry.sends, param, "value", cb)
        return len(params)

    def _rebind_sends(self, entry):
        """The return tracks changed: drop this track's send listeners and
        add them for its current sends."""
        if entry.cell.index < 0:
            return 0                       # removed meanwhile
        old, entry.sends = entry.sends, []
        for obj, prop, callback in old:
            _remove(obj, prop, callback)
        return max(1, len(old) + self._bind_sends(
            entry, self._track_callback(entry.cell)))

    @staticmethod
    def _unbind(entry):
        targets = entry.targets + entry.sends
        entry.targets, entry.sends = [], []
        for obj, prop, callback in targets:
            _remove(obj, prop, callback)
        return max(1, len(targets))

    def _track_callback(self, cell):
        tracker = self._tracker

        def on_track_changed():
            if cell.index >= 0:
                tracker.mark_track_dirty(cell.index)
        return on_track_changed

    def _scene_callback(self, cell):
        tracker = self._tracker

        def on_scene_changed():
            if cell.index >= 0:
                tracker.mark_scene_dirty(cell.index)
        return on_scene_changed

    def disconnect(self):
        self._sends_dirty = False
        ops, self._ops = self._ops, collections.deque()
        for op, kind, entry in ops:
            if op == "unbind":
                self._unbind(entry)
        for entry in self._tracks + self._scenes:
            self._unbind(entry)
        self._tracks = []
        self._scenes = []
        self._song_listeners.clear()
        self._song = None
