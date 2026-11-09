"""The thin Live-facing part: a ControlSurface that drives Bridge.

Live calls update_display() on a control surface periodically; the _Framework
ControlSurface advances its scheduler by Defaults.TIMER_DELAY = 0.1 s per
call, i.e. Live calls it roughly every 100 ms. All real work lives in
bridge.py / state.py / commands.py, which are unit-tested without Live.
"""

from _Framework.ControlSurface import ControlSurface

from .bridge import Bridge


class TwinKeysBridge(ControlSurface):

    def __init__(self, c_instance):
        ControlSurface.__init__(self, c_instance)
        self._bridge = None
        try:
            self._bridge = Bridge(song_provider=self.song,
                                  log=self.log_message,
                                  show_message=self.show_message)
            self.log_message("TwinKeysBridge: started")
        except Exception as exc:
            self.log_message("TwinKeysBridge: failed to start: %s" % exc)

    def update_display(self):
        ControlSurface.update_display(self)
        bridge = self._bridge
        if bridge is not None:
            try:
                bridge.tick()
            except Exception as exc:  # Bridge.tick never raises; be safe
                self.log_message("TwinKeysBridge: tick failed: %s" % exc)

    def disconnect(self):
        bridge, self._bridge = self._bridge, None
        if bridge is not None:
            try:
                bridge.shutdown()
            except Exception as exc:
                self.log_message("TwinKeysBridge: shutdown failed: %s" % exc)
        ControlSurface.disconnect(self)
