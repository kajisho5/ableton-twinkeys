"""Loads the Live-facing ControlSurface against a stub _Framework module."""
import sys
import types
import unittest

from tests.fake_live import FakeSong


class StubControlSurface(object):
    def __init__(self, c_instance):
        self._c_instance = c_instance
        self.logs = []
        self.updates = 0
        self.disconnected = False

    def song(self):
        return self._c_instance.song()

    def log_message(self, *msg):
        self.logs.append(" ".join(str(m) for m in msg))

    def show_message(self, msg):
        pass

    def update_display(self):
        self.updates += 1

    def disconnect(self):
        self.disconnected = True


class FakeCInstance(object):
    def __init__(self):
        self._song = FakeSong(2, 2)

    def song(self):
        return self._song


class SurfaceTest(unittest.TestCase):

    def setUp(self):
        fw = types.ModuleType("_Framework")
        cs = types.ModuleType("_Framework.ControlSurface")
        cs.ControlSurface = StubControlSurface
        fw.ControlSurface = cs
        self._saved = {k: sys.modules.get(k) for k in
                       ("_Framework", "_Framework.ControlSurface")}
        sys.modules["_Framework"] = fw
        sys.modules["_Framework.ControlSurface"] = cs
        sys.modules.pop("TwinKeysBridge.surface", None)

    def tearDown(self):
        for k, v in self._saved.items():
            if v is None:
                sys.modules.pop(k, None)
            else:
                sys.modules[k] = v
        sys.modules.pop("TwinKeysBridge.surface", None)

    def test_create_instance_tick_disconnect(self):
        import TwinKeysBridge
        from TwinKeysBridge.bridge import Bridge
        calls = []
        orig_tick = Bridge.tick

        def tick(self):
            calls.append(1)
            raise RuntimeError("must be contained")
        Bridge.tick = tick
        try:
            surface = TwinKeysBridge.create_instance(FakeCInstance())
            surface._bridge._transport_factory = lambda: (_ for _ in ()).throw(
                OSError("no network in this test"))
            surface.update_display()          # must not raise
            self.assertEqual(surface.updates, 1)
            self.assertEqual(calls, [1])
        finally:
            Bridge.tick = orig_tick
        surface.update_display()              # real tick, bind fails safely
        surface.disconnect()
        self.assertTrue(surface.disconnected)
        self.assertIsNone(surface._bridge)


if __name__ == "__main__":
    unittest.main()
