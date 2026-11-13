#!/usr/bin/env python3
"""Runs the real TwinKeysBridge Remote Script (LiveBridge/TwinKeysBridge) against the fake Live of
its unit tests (LiveBridge/tests/fake_live.py), ticking it every 100 ms like Live's update_display.

Used by the Windows version's tests (windows/tests/TwinKeys.Core.Tests/RealBridgeTests.cs) to check
the C# Bridge client against the script itself, without Live:

    python3 scripts/fake-live-bridge.py --command-port 47911 --state-port 47912 --seconds 20

Only 127.0.0.1 is used (the script refuses anything else). Prints "ready" when listening, and the
fake song's calls (start_playing, ...) as "call <name>" lines.
"""

import argparse
import os
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "LiveBridge"))

from TwinKeysBridge.bridge import Bridge  # noqa: E402
from TwinKeysBridge.transport import UdpTransport  # noqa: E402
from tests.fake_live import FakeSong  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--command-port", type=int, required=True)
    ap.add_argument("--state-port", type=int, required=True)
    ap.add_argument("--tracks", type=int, default=3)
    ap.add_argument("--scenes", type=int, default=4)
    ap.add_argument("--seconds", type=float, default=30)
    a = ap.parse_args()

    song = FakeSong(n_tracks=a.tracks, n_scenes=a.scenes, n_returns=1)
    bridge = Bridge(lambda: song,
                    log=lambda m: print("log " + m, flush=True),
                    transport_factory=lambda: UdpTransport(listen_port=a.command_port, dest_port=a.state_port))
    end = time.monotonic() + a.seconds
    seen = 0
    ready = False
    while time.monotonic() < end:
        bridge.tick()
        if not ready and bridge.transport is not None:
            print("ready", flush=True)
            ready = True
        for c in song.calls[seen:]:
            print("call " + c, flush=True)
        seen = len(song.calls)
        time.sleep(0.1)
    bridge.shutdown()


if __name__ == "__main__":
    main()
