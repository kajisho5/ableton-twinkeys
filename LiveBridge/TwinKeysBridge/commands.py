"""Command parsing, validation and dispatch (no Live dependency).

Every command is a JSON object with "cmd" (str) and "id" (int). The reply is
{"type": "ack", "id": N, "ok": true} or
{"type": "ack", "id": N, "ok": false, "error": "..."}.
A command may carry "structure": <int>; if it differs from the tracker's
structure counter the command is not run and the reply is
{"type": "ack", "id": N, "ok": false, "error": "structure_changed",
 "structure": <current int>}.
No exception escapes handle(): bad input and errors raised by Live both
become ok:false.
"""

import json
import math

from . import constants as C
from .protocol import encode


class CommandError(Exception):
    extra = None


class StructureChanged(CommandError):

    def __init__(self, current):
        CommandError.__init__(self, "structure_changed")
        self.extra = {"structure": current}


def _is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def _get_int(cmd, key):
    if key not in cmd:
        raise CommandError("missing '%s'" % key)
    v = cmd[key]
    if isinstance(v, float) and v.is_integer() and not math.isinf(v):
        v = int(v)
    if not _is_int(v):
        raise CommandError("'%s' must be an integer" % key)
    return v


def _get_number(cmd, key, lo, hi):
    if key not in cmd:
        raise CommandError("missing '%s'" % key)
    v = cmd[key]
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        raise CommandError("'%s' must be a number" % key)
    v = float(v)
    if math.isnan(v) or math.isinf(v):
        raise CommandError("'%s' must be finite" % key)
    if v < lo or v > hi:
        raise CommandError("'%s' must be between %g and %g" % (key, lo, hi))
    return v


def _get_bool(cmd, key):
    if key not in cmd:
        raise CommandError("missing '%s'" % key)
    v = cmd[key]
    if not isinstance(v, bool):
        raise CommandError("'%s' must be true or false" % key)
    return v


def _set_param(param, fraction):
    """Set a DeviceParameter to min + fraction * (max - min), clamped."""
    lo = float(param.min)
    hi = float(param.max)
    value = lo + fraction * (hi - lo)
    param.value = min(hi, max(lo, value))


class CommandDispatcher(object):

    def __init__(self, song_provider, tracker=None):
        self._song_provider = song_provider
        self._tracker = tracker
        self._handlers = {
            "hello": self._hello,
            "fire_scene": self._fire_scene,
            "fire_clip": self._fire_clip,
            "stop_track": self._stop_track,
            "stop_all": self._stop_all,
            "play": self._play,
            "stop": self._stop,
            "continue": self._continue,
            "set_tempo": self._set_tempo,
            "set_volume": self._set_volume,
            "set_pan": self._set_pan,
            "set_mute": self._set_mute,
            "set_solo": self._set_solo,
            "select_scene": self._select_scene,
        }

    @property
    def commands(self):
        return sorted(self._handlers)

    # ---------------------------------------------------------------- entry

    def handle(self, data):
        """Handle one datagram. Returns a list of datagrams to send back."""
        cmd_id = None
        try:
            try:
                text = data.decode("utf-8") if isinstance(data, bytes) else data
                cmd = json.loads(text)
            except (UnicodeDecodeError, ValueError):
                raise CommandError("invalid JSON")
            if not isinstance(cmd, dict):
                raise CommandError("command must be a JSON object")
            if _is_int(cmd.get("id")):
                cmd_id = cmd["id"]
            else:
                raise CommandError("missing or non-integer 'id'")
            name = cmd.get("cmd")
            if not isinstance(name, str):
                raise CommandError("missing 'cmd'")
            handler = self._handlers.get(name)
            if handler is None:
                raise CommandError("unknown command '%s'" % name[:64])
            song = self._song_provider()
            if song is None:
                raise CommandError("no song available")
            if name != "hello":
                self._check_structure(cmd)
            follow_up = handler(song, cmd) or []
            return [self._ack(cmd_id, True)] + list(follow_up)
        except CommandError as exc:
            return [self._ack(cmd_id, False, str(exc), exc.extra)]
        except Exception as exc:  # errors raised by Live itself
            return [self._ack(cmd_id, False, "Live error: %s: %s"
                              % (type(exc).__name__, exc))]

    @staticmethod
    def _ack(cmd_id, ok, error=None, extra=None):
        msg = {"type": "ack", "id": cmd_id, "ok": bool(ok)}
        if not ok:
            msg["error"] = error or "failed"
        if extra:
            msg.update(extra)
        return encode(msg)

    def _check_structure(self, cmd):
        """Optional "structure" field: reject the command if the track or
        scene list changed since the client last saw the song message."""
        if "structure" not in cmd:
            return
        expected = cmd["structure"]
        if not _is_int(expected):
            raise CommandError("'structure' must be an integer")
        if self._tracker is None:
            return
        current = self._tracker.current_structure()
        if expected != current:
            raise StructureChanged(current)

    # ---------------------------------------------------------------- lookup

    def _track(self, song, cmd, allow_master=False):
        idx = _get_int(cmd, "track")
        if idx == -1:
            if not allow_master:
                raise CommandError("master track not allowed for this command")
            return song.master_track, -1
        tracks = song.tracks
        if not 0 <= idx < len(tracks):
            raise CommandError("track %d out of range (0..%d)"
                               % (idx, len(tracks) - 1))
        return tracks[idx], idx

    def _scene(self, song, cmd):
        idx = _get_int(cmd, "scene")
        scenes = song.scenes
        if not 0 <= idx < len(scenes):
            raise CommandError("scene %d out of range (0..%d)"
                               % (idx, len(scenes) - 1))
        return scenes[idx], idx

    def _dirty_track(self, idx):
        if self._tracker is not None and idx >= 0:
            self._tracker.mark_track_dirty(idx)

    def _dirty_scene(self, idx):
        if self._tracker is not None:
            self._tracker.mark_scene_dirty(idx)

    # ---------------------------------------------------------------- commands

    def _hello(self, song, cmd):
        # Coalesced: the tracker sends the full state from its next tick,
        # at most once per FULL_STATE_MIN_INTERVAL however many hellos come.
        if self._tracker is not None:
            self._tracker.request_full_state()
        return []

    def _fire_scene(self, song, cmd):
        scene, idx = self._scene(song, cmd)
        scene.fire()
        self._dirty_scene(idx)

    def _fire_clip(self, song, cmd):
        track, t = self._track(song, cmd)
        s = _get_int(cmd, "scene")
        slots = track.clip_slots
        if not 0 <= s < len(slots):
            raise CommandError("scene %d out of range (0..%d)"
                               % (s, len(slots) - 1))
        slots[s].fire()
        self._dirty_track(t)

    def _stop_track(self, song, cmd):
        track, t = self._track(song, cmd)
        track.stop_all_clips()
        self._dirty_track(t)

    def _stop_all(self, song, cmd):
        song.stop_all_clips()

    def _play(self, song, cmd):
        song.start_playing()

    def _stop(self, song, cmd):
        song.stop_playing()

    def _continue(self, song, cmd):
        song.continue_playing()

    def _set_tempo(self, song, cmd):
        song.tempo = _get_number(cmd, "bpm", C.TEMPO_MIN, C.TEMPO_MAX)

    def _set_volume(self, song, cmd):
        track, t = self._track(song, cmd, allow_master=True)
        value = _get_number(cmd, "value", 0.0, 1.0)
        _set_param(track.mixer_device.volume, value)
        self._dirty_track(t)

    def _set_pan(self, song, cmd):
        track, t = self._track(song, cmd, allow_master=True)
        value = _get_number(cmd, "value", -1.0, 1.0)
        _set_param(track.mixer_device.panning, (value + 1.0) / 2.0)
        self._dirty_track(t)

    def _set_mute(self, song, cmd):
        track, t = self._track(song, cmd)
        track.mute = _get_bool(cmd, "on")
        self._dirty_track(t)

    def _set_solo(self, song, cmd):
        track, t = self._track(song, cmd)
        track.solo = _get_bool(cmd, "on")
        self._dirty_track(t)

    def _select_scene(self, song, cmd):
        scene, idx = self._scene(song, cmd)
        song.view.selected_scene = scene
