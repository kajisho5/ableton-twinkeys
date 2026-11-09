"""Live listeners that only mark the StateTracker dirty.

Live's API exposes add_<prop>_listener / remove_<prop>_listener /
<prop>_has_listener for observable properties. Callbacks here never change
Live's state (Live forbids changes from inside notifications); they only set
flags that the next update_display tick acts on. Polling in StateTracker
remains the fallback, so a missing listener only delays an update.
"""


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
            try:
                has = getattr(obj, "%s_has_listener" % prop, None)
                if has is not None and not has(callback):
                    continue
                getattr(obj, "remove_%s_listener" % prop)(callback)
            except Exception:
                pass  # object already deleted: nothing to remove


class LiveListenerBinder(object):

    SONG_PROPS = ("tracks", "scenes")
    TRACK_PROPS = ("name", "color", "mute", "solo", "playing_slot_index",
                   "fired_slot_index")
    SCENE_PROPS = ("name", "color", "is_triggered")

    def __init__(self, tracker, report=None):
        self._tracker = tracker
        self._song_listeners = ListenerRegistry(report)
        self._item_listeners = ListenerRegistry(report)
        self._song = None

    def rebind(self, song, tracks, scenes, master):
        if self._song is None or not (self._song is song or self._song == song):
            self._song_listeners.clear()
            self._song = song
            for prop in self.SONG_PROPS:
                self._song_listeners.add(song, prop,
                                         self._tracker.mark_structure_dirty)
        self._item_listeners.clear()
        for i, track in enumerate(tracks):
            cb = self._track_callback(i)
            for prop in self.TRACK_PROPS:
                self._item_listeners.add(track, prop, cb)
            try:
                mixer = track.mixer_device
                self._item_listeners.add(mixer.volume, "value", cb)
                self._item_listeners.add(mixer.panning, "value", cb)
            except Exception:
                pass
        for s, scene in enumerate(scenes):
            cb = self._scene_callback(s)
            for prop in self.SCENE_PROPS:
                self._item_listeners.add(scene, prop, cb)

    def _track_callback(self, index):
        tracker = self._tracker

        def on_track_changed():
            tracker.mark_track_dirty(index)
        return on_track_changed

    def _scene_callback(self, index):
        tracker = self._tracker

        def on_scene_changed():
            tracker.mark_scene_dirty(index)
        return on_scene_changed

    def disconnect(self):
        self._item_listeners.clear()
        self._song_listeners.clear()
        self._song = None
