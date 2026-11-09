"""A small fake of Live's object model for unit tests (no Live needed).

Mirrors the attribute names the bridge uses: Song, Song.View, Track,
MixerDevice, DeviceParameter (.value/.min/.max), Scene, ClipSlot, Clip, and
add_/remove_/_has_ listener methods.
"""


class Observable(object):
    """Generic add_<p>_listener / remove_<p>_listener / <p>_has_listener."""

    def __init__(self):
        object.__setattr__(self, "_listeners", {})

    def __getattr__(self, name):
        listeners = object.__getattribute__(self, "_listeners")
        if name.startswith("add_") and name.endswith("_listener"):
            prop = name[4:-9]
            return lambda cb: listeners.setdefault(prop, []).append(cb)
        if name.startswith("remove_") and name.endswith("_listener"):
            prop = name[7:-9]
            return lambda cb: listeners.get(prop, []).remove(cb)
        if name.endswith("_has_listener"):
            prop = name[:-13]
            return lambda cb: cb in listeners.get(prop, [])
        raise AttributeError(name)

    def notify(self, prop):
        for cb in list(self._listeners.get(prop, [])):
            cb()

    def listener_count(self):
        return sum(len(v) for v in self._listeners.values())


class FakeParameter(Observable):
    def __init__(self, value=0.0, min=0.0, max=1.0):
        Observable.__init__(self)
        self.value = value
        self.min = min
        self.max = max


class FakeMixer(object):
    def __init__(self, volume=0.85, pan=0.0):
        self.volume = FakeParameter(volume, 0.0, 1.0)
        self.panning = FakeParameter(pan, -1.0, 1.0)


class FakeClip(Observable):
    def __init__(self, name="Clip", color=0xFF0000, length=4.0):
        Observable.__init__(self)
        self.name = name
        self.color = color
        self.length = length
        self.playing_position = 0.0


class FakeClipSlot(Observable):
    def __init__(self, clip=None):
        Observable.__init__(self)
        self.clip = clip
        self.fired = 0

    @property
    def has_clip(self):
        return self.clip is not None

    def fire(self):
        self.fired += 1


class FakeTrack(Observable):
    def __init__(self, name="Track", n_scenes=0, color=0x00FF00):
        Observable.__init__(self)
        self.name = name
        self.color = color
        self.mute = False
        self.solo = False
        self.mixer_device = FakeMixer()
        self.clip_slots = [FakeClipSlot() for _ in range(n_scenes)]
        self.playing_slot_index = -1
        self.fired_slot_index = -1
        self.is_foldable = False
        self.is_grouped = False
        self.has_audio_output = True
        self.output_meter_left = 0.0
        self.output_meter_right = 0.0
        self.stopped = 0

    def stop_all_clips(self):
        self.stopped += 1


class FakeScene(Observable):
    def __init__(self, name="Scene", color=0x0000FF):
        Observable.__init__(self)
        self.name = name
        self.color = color
        self.is_triggered = False
        self.fired = 0

    def fire(self):
        self.fired += 1


class FakeView(Observable):
    def __init__(self):
        Observable.__init__(self)
        self.selected_track = None
        self.selected_scene = None


class FakeSong(Observable):
    def __init__(self, n_tracks=4, n_scenes=4):
        Observable.__init__(self)
        self.tempo = 120.0
        self.is_playing = False
        self.current_song_time = 0.0
        self.signature_numerator = 4
        self.signature_denominator = 4
        self.scenes = [FakeScene("Scene %d" % s) for s in range(n_scenes)]
        self.tracks = [FakeTrack("Track %d" % t, n_scenes)
                       for t in range(n_tracks)]
        self.master_track = FakeTrack("Master", 0)
        self.view = FakeView()
        if self.tracks:
            self.view.selected_track = self.tracks[0]
        if self.scenes:
            self.view.selected_scene = self.scenes[0]
        self.calls = []

    def start_playing(self):
        self.calls.append("start_playing")
        self.is_playing = True

    def stop_playing(self):
        self.calls.append("stop_playing")
        self.is_playing = False

    def continue_playing(self):
        self.calls.append("continue_playing")
        self.is_playing = True

    def stop_all_clips(self):
        self.calls.append("stop_all_clips")


class FakeClock(object):
    def __init__(self, t=1000.0):
        self.t = t

    def __call__(self):
        return self.t

    def advance(self, dt):
        self.t += dt
        return self.t
