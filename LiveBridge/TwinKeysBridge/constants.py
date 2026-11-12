"""Constants shared by the TwinKeys Bridge modules.

Nothing in this module imports Live, so it can be used by the unit tests.
"""

# Version of this script, reported in the "song" message as "bridge_version". TwinKeys compares
# it with the copy inside the app and replaces an older installed copy (TwinKeys 2.2+).
# Keep the line exactly in this form: TwinKeys reads it from the installed file.
BRIDGE_VERSION = 3

# Security rule: the bridge only ever binds to, and sends to, the IPv4
# loopback address. Never change this to "0.0.0.0" or a LAN address.
LOOPBACK_HOST = "127.0.0.1"

# UDP port the script listens on for commands from TwinKeys.
COMMAND_PORT = 47811
# UDP port on 127.0.0.1 that TwinKeys listens on for state messages.
STATE_PORT = 47812

# Every datagram we send must be smaller than this many bytes.
# Kept under the macOS default UDP datagram limit (9216 bytes) so the receiving side never
# depends on a raised buffer.
MAX_DATAGRAM_BYTES = 8000
# Largest datagram we try to read (UDP maximum payload).
RECV_BUFFER_BYTES = 65535
# Socket send buffer. On macOS a UDP datagram larger than the socket's send
# buffer (default 9216 bytes, sysctl net.inet.udp.maxdgram) is rejected with
# EMSGSIZE, so we ask for a larger buffer.
SEND_BUFFER_BYTES = 1 << 20

# Most commands processed per update_display tick (flood protection).
MAX_COMMANDS_PER_TICK = 64

# Timing (seconds).
STATE_INTERVAL = 0.095          # state diffs at most every ~100 ms
FULL_RESEND_INTERVAL = 5.0      # full resend of the cached state
METER_INTERVAL = 1.0 / 15.0     # at most 15 meter messages per second
METER_TAIL = 2.0                # keep sending meters this long after stop
PROGRESS_INTERVAL = 0.2         # ~5 progress messages per second
STRUCTURE_CHECK_INTERVAL = 1.0  # fallback poll of the track/scene lists
BIND_RETRY_INTERVAL = 5.0       # retry binding the port if it was busy
ERROR_REPEAT_INTERVAL = 5.0     # identical error messages at most this often
ERROR_LOG_MAX = 20              # at most this many error lines per
                                # ERROR_REPEAT_INTERVAL, whatever the text
ERROR_KEYS_MAX = 200            # distinct error texts remembered (oldest go)
FULL_STATE_MIN_INTERVAL = 0.5   # "hello" full-state sends at most this often

# Per-tick work budgets (keep CPU low on big sets).
TRACK_BUDGET = 25               # track rows re-read per tick (round robin)
SCENE_BUDGET = 25               # scene rows re-read per tick (round robin)
SLOT_BUDGET = 2000              # clip slots re-read per tick (round robin)
BULK_BYTES_PER_TICK = 400000    # bytes of full-state clip data per tick
LISTENER_OPS_PER_TICK = 400     # Live add/remove listener calls per tick

METER_THRESHOLD = 0.01          # only send meter values that moved more
MAX_NAME_LENGTH = 200           # names are truncated to this many chars

TEMPO_MIN = 20.0
TEMPO_MAX = 999.0

# Sends reported per track ("sends" in the tracks message) and settable with
# set_send: Send A and Send B, i.e. mixer_device.sends[0] and [1].
MAX_SENDS = 2
