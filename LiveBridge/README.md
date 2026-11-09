# TwinKeys Bridge (Ableton Live Remote Script)

TwinKeys Bridge is a MIDI Remote Script for Ableton Live 11 and 12, written in
Python 3. It lets the TwinKeys Mac app, running on the same Mac, control Live
(launch scenes and clips, transport, tempo, mixer) and read Live's state
(tracks, scenes, clips, meters, play position).

It talks JSON over UDP **on 127.0.0.1 only**:

| Direction          | Address           |
|--------------------|-------------------|
| TwinKeys → Live    | `127.0.0.1:47811` (the script binds here) |
| Live → TwinKeys    | `127.0.0.1:47812` (the script sends here) |

```
LiveBridge/
  TwinKeysBridge/      <- the Remote Script folder you copy into Live
    __init__.py        create_instance(c_instance), imports Live code lazily
    surface.py         thin ControlSurface: update_display() -> Bridge.tick()
    bridge.py          glue: transport + commands + state, error reporting
    commands.py        command parsing, validation, dispatch
    state.py           reads Live, caches, diffs, chunks state messages
    listeners.py       Live listeners that only mark state "dirty"
    protocol.py        JSON encoding, chunking, beat/colour formatting
    transport.py       non-blocking UDP socket, 127.0.0.1 only
    constants.py       ports, limits, intervals, budgets
  tests/               unittest suite with a fake Live object model
  THIRD_PARTY.md
```

Only `surface.py` imports Live's `_Framework`. Everything else runs against any
object that looks like Live's `Song`, and the unit tests use a fake one.

## Install

1. Quit Live.
2. Copy the `TwinKeysBridge` folder (not `LiveBridge`) into the User Library
   "Remote Scripts" folder. On macOS that is
   `~/Music/Ableton/User Library/Remote Scripts/`. Create the folder if it does
   not exist. The result is
   `~/Music/Ableton/User Library/Remote Scripts/TwinKeysBridge/__init__.py`.
3. Start Live. Open **Settings > Link, Tempo & MIDI** (called **Preferences >
   Link / Tempo / MIDI** in Live 11). In a free **Control Surface** slot choose
   **TwinKeysBridge**. Leave Input and Output at "None"; the script uses no MIDI
   ports.
4. Live's status bar shows "TwinKeys Bridge: listening on 127.0.0.1:47811".
   If the port is in use you see "TwinKeys Bridge: port 47811 busy". The script
   then tries to bind again every 5 seconds.

Sources for these steps: the AbletonOSC README install section
(https://github.com/ideoforms/AbletonOSC#installation), which follows Ableton's
article "Installing third-party remote scripts"
(https://help.ableton.com/hc/en-us/articles/209072009-Installing-third-party-remote-scripts).
That article could not be fetched from this environment (HTTP 403), so it was
not read directly. **Unverified:** the exact Live 12 menu label "Settings > Link,
Tempo & MIDI". AbletonOSC documents the Live 11 label "Preferences > Link /
Tempo / MIDI".

Logs: the script writes through the Remote Script's `log_message`, so lines
starting with `TwinKeysBridge` appear in Live's `Log.txt`. On macOS that file is
under `~/Library/Preferences/Ableton/Live <version>/` (**unverified** path).

## Security

- The socket binds to `127.0.0.1` only, never `0.0.0.0` or a LAN address.
  `transport.py` raises `LoopbackOnlyError` for any other host, and the
  destination is hard-coded to `127.0.0.1:47812`. Datagrams whose source is not
  `127.0.0.1` are dropped (a second check; a loopback-bound socket cannot
  receive them anyway). `SO_REUSEADDR` is not set, so the port is not shared.
- Other Macs on the network therefore cannot reach the script. AbletonOSC binds
  `0.0.0.0` with no authentication, and this script does not.
- There is **no authentication** between local processes. Any program running on
  the same Mac can send commands to `127.0.0.1:47811`, the same trust level as
  any app the user runs. The commands only launch, stop, select and change
  mixer and tempo values; none of them read or write files.
- Input is validated: integer indices are range-checked, numbers must be finite
  and within range, booleans must be JSON `true`/`false`. At most 64 commands
  are handled per tick. No exception from bad input or from Live leaves the
  script.

## Protocol

One JSON object (UTF-8) per UDP datagram. Every datagram the script sends is
**under 60 000 bytes**; large lists are split into several messages (chunks).
Names longer than 200 characters are cut to 200.

TwinKeys should give its receiving socket a large `SO_RCVBUF` (for example
1–4 MB). macOS also rejects outgoing UDP datagrams larger than the socket send
buffer (default `net.inet.udp.maxdgram` = 9216). The script therefore sets its
own `SO_SNDBUF` to 1 MB, and the TwinKeys side needs the same setting if it
ever sends large datagrams.

### Commands (TwinKeys → Live)

Every command has `"cmd"` (string) and an integer `"id"`. Every command,
including `hello`, gets exactly one reply:

```json
{"type":"ack","id":7,"ok":true}
{"type":"ack","id":7,"ok":false,"error":"track 12 out of range (0..7)"}
```

`"error"` appears only when `ok` is false. If the datagram is not valid JSON or
has no integer `id`, the reply is `{"type":"ack","id":null,"ok":false,...}`.

| cmd            | fields                     | Live call |
|----------------|----------------------------|-----------|
| `hello`        | –                          | ack, then the full state (see below) |
| `fire_scene`   | `scene`                    | `song.scenes[scene].fire()` |
| `fire_clip`    | `track`, `scene`           | `track.clip_slots[scene].fire()`. On an empty slot Live fires that slot's stop button, if it has one. |
| `stop_track`   | `track`                    | `track.stop_all_clips()` |
| `stop_all`     | –                          | `song.stop_all_clips()` (the transport keeps running) |
| `play`         | –                          | `song.start_playing()` |
| `stop`         | –                          | `song.stop_playing()` |
| `continue`     | –                          | `song.continue_playing()` |
| `set_tempo`    | `bpm` (20–999)             | `song.tempo = bpm` |
| `set_volume`   | `track`, `value` (0..1)    | `mixer_device.volume.value = min + value*(max-min)` |
| `set_pan`      | `track`, `value` (-1..1)   | `mixer_device.panning.value` mapped to the parameter's `min..max` |
| `set_mute`     | `track`, `on` (bool)       | `track.mute = on` |
| `set_solo`     | `track`, `on` (bool)       | `track.solo = on` (not exclusive, as in Live's API) |
| `select_scene` | `scene`                    | `song.view.selected_scene = scene` |

`track` is an index into `song.tracks` (return tracks are not included).
`track: -1` means the master track and is accepted only by `set_volume` and
`set_pan`. Volume `value` is the parameter's normalised position, not dB. On
Live's volume parameter, 0.85 is about 0 dB and 1.0 is +6 dB (**unverified**,
from general Live knowledge).

### State messages (Live → TwinKeys)

State is checked from `update_display()` (about every 100 ms) and sent **only
when something changed**, at most once per 95 ms. Every 5 seconds the cached
state is sent again in full, which repairs lost datagrams.

**song**

```json
{"type":"song","tempo":120.0,"playing":true,"beat":"17.3.1","sig":[4,4],
 "selected_track":2,"selected_scene":0,"set_name":"","tracks":8,"scenes":16}
```

- `beat` is `bars.beats.sixteenths`, all 1-based, computed from
  `current_song_time` (in beats) and the time signature. A "beat" is one
  denominator note: a quarter note in x/4, an eighth note in x/8.
- `selected_track`: the index in `tracks`, `-1` if the master track is
  selected, `-2` for a return track. `selected_scene`: the index, or `-1`.
- `set_name` is `""` because the Live API does not expose the Set's name. The
  script does read `song.name` if it exists.

**tracks**

```json
{"type":"tracks","start":0,"master":{"volume":0.85,"pan":0.0},
 "items":[{"index":0,"name":"Drums","color":"#FF3A34","volume":0.85,"pan":0.0,
           "mute":false,"solo":false,"playing_slot":-1,"fired_slot":-1,
           "stop_fired":false,"is_group":false,"is_foldable":false,"is_grouped":false}]}
```

- `start` is the index of the first item. Items are contiguous runs. An update
  holds only the tracks that changed, so it can have `start` > 0.
- `master` appears in the first chunk of every tracks update. If only the master
  changed, the message is `start:0, items:[]` plus `master`.
- `is_group` = `is_foldable` (the track is a group track). `is_grouped` is an
  extra field: the track is inside a group.
- `fired_slot` is `-1` or a slot index. Live reports `-2` when the track's stop
  button was fired; the script sends that as `fired_slot:-1` with
  `"stop_fired":true` (extra field).
- `volume` is 0..1 and `pan` is -1..1, normalised from each parameter's
  `min`/`max`.

**scenes**

```json
{"type":"scenes","start":0,"items":[{"index":0,"name":"Intro","color":"#1A2B3C",
 "triggered":false,"playing":true}]}
```

`playing` is **true if at least one track is playing a clip in this scene row**
(that is, some track's `playing_slot_index` equals the scene index). We did not
use "every track's playing slot is in this scene", because tracks without
clips, or tracks playing another row, would make it almost never true.

**clips**: one message per track, split further if needed

```json
{"type":"clips","track":3,"items":[{"scene":0,"has_clip":true,"name":"Bass",
 "color":"#FFA500","is_playing":true,"is_triggered":false,
 "length_beats":16.0,"position_beats":3.25}]}
```

- Every item has its `scene` index, so chunks and partial updates stand alone.
  The full state has every slot of the track. An update has only the slots that
  changed.
- `is_playing` / `is_triggered` come from the track's `playing_slot_index` /
  `fired_slot_index`. This is one read per track, not two per slot, so an empty
  slot whose stop button blinks has `is_triggered:true`.
- `position_beats` is the value when the slot was read. A position change alone
  does **not** produce a clips update; use `progress` for live positions.
- `length_beats` is `clip.length`. Per the API this is in seconds for unwarped
  audio clips.
- An empty slot is `{"has_clip":false,"name":"","color":null,...}`.

**meters**

```json
{"type":"meters","items":[[0,0.52,0.48],[3,0.10,0.12]],"master":[0.61,0.60]}
```

- Sent while the transport plays, and for 2 s after it stops so the meters
  fall. At most 15 per second; in practice about 10, because
  `update_display` runs about every 100 ms.
- `items` holds only tracks whose left or right value moved by more than 0.01
  since the last value sent. `master` is always included.
- Only tracks with `has_audio_output` are read.

**progress**

```json
{"type":"progress","items":[[3,5.25,16.0],[7,0.5,4.0]]}
```

`[track, position_beats, length_beats]` for each track with a playing clip,
about 5 per second while playing and only when values changed. When playback
stops, one message with empty `items` is sent.

**error**

```json
{"type":"error","message":"tracks: RuntimeError: ..."}
```

Internal errors are also written to Live's log via `log_message`. The same
message is repeated at most every 5 s.

### `hello` and full state

On `hello` the script sends the ack, then re-reads all of Live's state. It then
sends `song`, `tracks` (with `master`), `scenes`, `meters` (every audio track,
even if unchanged) and `progress` right away. The per-track `clips` messages
start in the same tick but are streamed under a budget of about 400 kB per
tick. A 200 × 200 set is roughly 6 MB of JSON, and a single burst would overflow
TwinKeys' receive buffer. The periodic 5-second resend uses the same queue.
Each queued track is encoded from the newest cache when it is sent, so a queued
full message can never overwrite a newer update.

## How it keeps CPU low

- **Listeners** (`listeners.py`): `Song.tracks` and `Song.scenes` mark a
  structure change. Each track's `name`, `color`, `mute`, `solo`,
  `playing_slot_index` and `fired_slot_index`, plus its mixer volume/panning
  `value`, mark that track dirty. Each scene's `name`, `color` and
  `is_triggered` mark that scene dirty. Listeners only set flags and never
  touch Live.
- **Polling with budgets** (`state.py`): every tick reads the song row (a few
  attributes), the master mixer, the dirty items, and a round-robin slice: 25
  track rows, 25 scene rows, and about 2000 clip slots. Clip slots have no
  listeners; 40 000 of them would cost more than polling. A 200 × 200 set is
  fully re-read about every 2 s, and a small set every tick.
- Structure is re-checked every 1 s by comparing the cached track and scene
  lists, as a fallback if a listener is missed.
- Results are cached and compared. Encoded clip columns are cached and reused
  for full resends.

## Tests

```sh
cd LiveBridge && python3 -m unittest -v
```

56 tests, no Live needed. `tests/fake_live.py` is a fake Live object model
(Song, View, Track, MixerDevice, DeviceParameter with value/min/max, Scene,
ClipSlot, Clip, listener methods). The tests cover:

- command dispatch and validation, malformed input, and Live exceptions
  becoming `ok:false`
- diffing: no message when nothing changed, partial track/scene/clip updates,
  the 5 s resend, and the 100 ms rate limit
- chunking with 200 tracks × 200 scenes: every datagram < 60 000 bytes, all
  40 000 slots present, UTF-8 counted in bytes
- beat formatting in 4/4, 3/4 and 6/8, and bad input
- binding to `127.0.0.1` only: the bind address is asserted, other hosts are
  refused, plus a real loopback round trip
- error isolation in the tracker, the bridge and `update_display`
- listener binding and unbinding, and port-busy retry

## Live API facts relied on, and sources

Sources:

- [LOM] Unofficial Live API docs, Live 11.0.0:
  https://nsuspray.github.io/Live_API_Doc/11.0.0.xml (index:
  https://nsuspray.github.io/Live_API_Doc/)
- [AOSC] AbletonOSC, commit `0ca6821` (2025-11-19):
  https://github.com/ideoforms/AbletonOSC
- [FW] Decompiled Live 11 `_Framework`:
  https://github.com/gluon/AbletonLive11_MIDIRemoteScripts/blob/master/_Framework/ControlSurface.py
  and `.../_Framework/Defaults.py`

| Fact | Source |
|------|--------|
| Live calls `create_instance(c_instance)` in the script package's `__init__.py` | [AOSC] `__init__.py` |
| `_Framework.ControlSurface.ControlSurface` has `update_display()`, `disconnect()`, `song()`, `log_message()`, `show_message()` | [FW] ControlSurface.py |
| `update_display()` advances the scheduler by `TIMER_DELAY = 0.1` s, so Live calls it about every 100 ms | [FW] ControlSurface.py, Defaults.py; [AOSC] `manager.py` ("Called once per 100ms tick") |
| Live's Python cannot use threads well, so poll a non-blocking socket from the timer | [AOSC] `manager.py`, `abletonosc/osc_server.py` |
| `Song.tempo`, `is_playing`, `signature_numerator/denominator`, `tracks` (excludes return/master), `scenes`, `master_track`, `view` | [LOM] Live.Song.Song |
| `Song.start_playing()`, `stop_playing()`, `continue_playing()`, `stop_all_clips()` | [LOM]; [AOSC] `song.py` |
| `Song.add_tracks_listener` / `add_scenes_listener`; the generic `add_/remove_<prop>_listener`, `<prop>_has_listener` pattern | [LOM]; [AOSC] `handler.py` |
| `Song.View.selected_track` / `selected_scene` are get/set | [LOM] Live.Song.Song.View; [AOSC] `view.py` |
| `Track.name`, `color` (RGB int), `mute`, `solo` (not exclusive), `mixer_device`, `clip_slots`, `stop_all_clips()`, `is_foldable`, `is_grouped`, `has_audio_output` | [LOM] Live.Track.Track |
| `Track.playing_slot_index` is -1 when nothing plays; `fired_slot_index` is -1 when none and -2 when the stop button is fired | [LOM] |
| `Track.output_meter_left/right` are 0.0–1.0, audio-output tracks only | [LOM] |
| `MixerDevice.volume` / `panning` are DeviceParameters with `value` / `min` / `max` and `add_value_listener` | [LOM]; [AOSC] `track.py` |
| `Scene.name`, `color`, `is_triggered`, `fire()` | [LOM]; [AOSC] `scene.py` |
| `ClipSlot.has_clip`, `clip`, `fire()` (fires the stop button on an empty slot) | [LOM]; [AOSC] `clip_slot.py` |
| `Clip.name`, `color`, `length` (beats, or seconds if unwarped), `playing_position` (beats, or seconds for unwarped audio, 0 when stopped) | [LOM]; [AOSC] `clip.py` |
| Live wrappers for the same object compare equal with `==` (used to find the selected track/scene index) | [AOSC] `view.py` uses `list(song.tracks).index(song.view.selected_track)` |
| `Song` has no `name` property (Live 11.0 API) | [LOM]: no such property listed |

### Unverified (Live was not available for testing)

- **Nothing has been run inside Live.** All behaviour was tested only against
  the fake object model.
- `Song.current_song_time` is treated as **beats**. The [LOM] text says "in
  ms", but [AOSC] uses it as beats (`int(current_song_time)` drives its beat
  listener). We did not use
  `get_current_beats_song_time()` (BeatTime), because its fields are not
  documented in [LOM].
- The API docs are for Live 11.0. That every attribute above behaves the same in
  Live 11.3 and Live 12 is assumed. AbletonOSC targets both.
- The exact `update_display` rate depends on Live. The ~100 ms figure comes
  from `TIMER_DELAY`, not from a measurement.
- Live rejects state changes made inside listener callbacks ("Changes cannot be
  triggered by notifications"). This is community knowledge, not documented in
  [LOM]. The script never changes state inside a listener.
- The Live 12 menu label, the `Log.txt` location, and the volume dB mapping
  (see above).
- The macOS UDP behaviour (`SO_SNDBUF` needed for datagrams larger than 9216
  bytes, `ENOBUFS` on bursts) is from general macOS knowledge. It was not
  tested on macOS here; the tests ran on Linux.
- CPU cost in a real 200 × 200 set. With the fake model, an incremental tick
  takes about 2 ms (median) to 15 ms (worst), and `hello` takes about 50 ms.
  Real Live objects are slower to read.
