"""Glue between the UDP transport, the command dispatcher and the state
tracker. Has no Live import: the ControlSurface in surface.py only calls
Bridge.tick() from update_display() and Bridge.shutdown() from disconnect().
"""

import time

from . import constants as C
from .commands import CommandDispatcher
from .listeners import LiveListenerBinder
from .protocol import encode
from .state import StateTracker
from .transport import UdpTransport


class Bridge(object):

    def __init__(self, song_provider, log=None, show_message=None,
                 transport_factory=UdpTransport, clock=time.monotonic,
                 use_listeners=True):
        self._log = log or (lambda msg: None)
        self._show = show_message or (lambda msg: None)
        self._clock = clock
        self._transport_factory = transport_factory
        self._transport = None
        self._next_bind = -1e9
        self._bind_failed_logged = False
        self._pending_errors = []
        self._last_error_at = {}
        self.tracker = StateTracker(
            song_provider, clock=clock, report_error=self._report_error,
            on_structure=self._on_structure)
        self._binder = None
        if use_listeners:
            self._binder = LiveListenerBinder(self.tracker, self._report_error)
        self.dispatcher = CommandDispatcher(song_provider, self.tracker)

    @property
    def transport(self):
        return self._transport

    # ------------------------------------------------------------ errors

    def _report_error(self, message):
        message = str(message)[:500]
        now = self._clock()
        last = self._last_error_at.get(message)
        if last is not None and now - last < C.ERROR_REPEAT_INTERVAL:
            return
        if len(self._last_error_at) > 200:
            self._last_error_at.clear()
        self._last_error_at[message] = now
        self._pending_errors.append(message)
        try:
            self._log("TwinKeysBridge error: %s" % message)
        except Exception:
            pass

    def _flush_errors(self):
        errors, self._pending_errors = self._pending_errors, []
        for message in errors:
            self._send(encode({"type": "error", "message": message}))

    def _on_structure(self, song, tracks, scenes, master):
        if self._binder is not None:
            self._binder.rebind(song, tracks, scenes, master)

    # ------------------------------------------------------------ transport

    def _ensure_transport(self, now):
        if self._transport is not None or now < self._next_bind:
            return self._transport is not None
        try:
            self._transport = self._transport_factory()
            self._log("TwinKeysBridge: listening on %s:%d, sending to %s:%d"
                      % (self._transport.listen_addr
                         + self._transport.dest_addr))
            self._show("TwinKeys Bridge: listening on 127.0.0.1:%d"
                       % self._transport.listen_addr[1])
            return True
        except Exception as exc:
            self._next_bind = now + C.BIND_RETRY_INTERVAL
            if not self._bind_failed_logged:
                self._bind_failed_logged = True
                self._log("TwinKeysBridge: cannot bind 127.0.0.1:%d (%s); "
                          "retrying every %ds"
                          % (C.COMMAND_PORT, exc, C.BIND_RETRY_INTERVAL))
                self._show("TwinKeys Bridge: port %d busy" % C.COMMAND_PORT)
            return False

    def _send(self, data):
        if self._transport is not None:
            self._transport.send(data)

    # ------------------------------------------------------------ main loop

    def tick(self):
        """Called from update_display (about every 100 ms). Never raises."""
        try:
            now = self._clock()
            if not self._ensure_transport(now):
                return
            for data in self._transport.receive(C.MAX_COMMANDS_PER_TICK):
                for reply in self.dispatcher.handle(data):
                    self._send(reply)
            for message in self.tracker.tick(now):
                self._send(message)
        except Exception as exc:
            self._report_error("tick: %s: %s" % (type(exc).__name__, exc))
        try:
            self._flush_errors()
        except Exception:
            pass

    def shutdown(self):
        try:
            if self._binder is not None:
                self._binder.disconnect()
        except Exception:
            pass
        if self._transport is not None:
            self._transport.close()
            self._transport = None
