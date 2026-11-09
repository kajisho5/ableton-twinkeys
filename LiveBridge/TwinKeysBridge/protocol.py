"""JSON encoding, chunking and formatting helpers (no Live dependency)."""

import json
import math

from .constants import MAX_DATAGRAM_BYTES, MAX_NAME_LENGTH


def dumps(obj):
    """Compact JSON text. NaN/Infinity are not valid JSON and are rejected."""
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=False,
                      allow_nan=False)


def encode(obj):
    """Encode one message as UTF-8 JSON bytes."""
    return dumps(obj).encode("utf-8")


def finite(value, default=0.0):
    """Return value as a finite float, or default."""
    try:
        f = float(value)
    except (TypeError, ValueError):
        return default
    if math.isnan(f) or math.isinf(f):
        return default
    return f


def rnd(value, digits=4):
    return round(finite(value), digits)


def clean_name(value):
    """Live names as a bounded-length str."""
    if value is None:
        return ""
    try:
        text = str(value)
    except Exception:
        return ""
    if len(text) > MAX_NAME_LENGTH:
        text = text[:MAX_NAME_LENGTH]
    return text


def color_hex(value):
    """Live colors are 0x00RRGGBB integers -> "#RRGGBB" (None if unknown)."""
    if value is None or isinstance(value, bool):
        return None
    try:
        v = int(value)
    except (TypeError, ValueError):
        return None
    if v < 0:
        return None
    return "#%06X" % (v & 0xFFFFFF)


def format_beat(song_time, numerator, denominator):
    """Format a song position given in beats (quarter notes) as
    "bars.beats.sixteenths", all 1-based, like Live's transport display.

    A "beat" is one denominator note (a quarter note in 4/4, an eighth note
    in 6/8). The last field counts sixteenth notes inside that beat.
    """
    t = finite(song_time)
    if t < 0:
        t = 0.0
    try:
        num = int(numerator)
    except (TypeError, ValueError):
        num = 4
    try:
        den = int(denominator)
    except (TypeError, ValueError):
        den = 4
    if num < 1:
        num = 4
    if den < 1:
        den = 4
    eps = 1e-9
    beat_len = 4.0 / den            # in quarter notes
    bar_len = num * beat_len
    bar = int(math.floor(t / bar_len + eps))
    rem = max(0.0, t - bar * bar_len)
    beat = min(int(math.floor(rem / beat_len + eps)), num - 1)
    rem2 = max(0.0, rem - beat * beat_len)
    sixteenths_per_beat = max(1, int(math.ceil(16.0 / den)))
    six = min(int(math.floor(rem2 / 0.25 + eps)), sixteenths_per_beat - 1)
    return "%d.%d.%d" % (bar + 1, beat + 1, six + 1)


def pack_items(base, items, start_of=None, first_extra=None,
               limit=MAX_DATAGRAM_BYTES):
    """Split `items` over as many datagrams as needed, each < `limit` bytes.

    base:        dict of fields for every chunk (e.g. {"type": "tracks"}).
    start_of:    optional function(item) -> int stored as "start" per chunk.
    first_extra: optional dict merged into the first chunk only.
    Returns a list of bytes. An empty `items` list gives one chunk.
    """
    encoded = [encode(it) for it in items]
    chunks = []
    i = 0
    n = len(encoded)
    first = True
    while first or i < n:
        header = dict(base)
        if start_of is not None:
            header["start"] = start_of(items[i]) if i < n else 0
        if first and first_extra:
            header.update(first_extra)
        header["items"] = []
        text = encode(header)
        # The "items" key is last, so the encoding ends with b'[]}'.
        prefix = text[:-2]
        size = len(prefix) + 2
        j = i
        while j < n:
            add = len(encoded[j]) + (1 if j > i else 0)
            if size + add >= limit and j > i:
                break
            size += add
            j += 1
        if size >= limit:
            raise ValueError("single item does not fit in one datagram")
        chunks.append(prefix + b",".join(encoded[i:j]) + b"]}")
        i = j
        first = False
    return chunks


def contiguous_runs(indices):
    """[1,2,3,7,8] -> [[1,2,3],[7,8]] (input need not be sorted)."""
    runs = []
    for idx in sorted(set(indices)):
        if runs and runs[-1][-1] == idx - 1:
            runs[-1].append(idx)
        else:
            runs.append([idx])
    return runs
