"""Tests for scripts/fake-yamaha-desk.py (run: python3 -m unittest discover -s scripts -p 'test_*.py')."""

import asyncio
import importlib.util
import os
import struct
import unittest

_HERE = os.path.dirname(os.path.abspath(__file__))
_spec = importlib.util.spec_from_file_location("fake_yamaha_desk", os.path.join(_HERE, "fake-yamaha-desk.py"))
desk = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(desk)

IN = desk.INPUT
ST = desk.STEREO


def osc(address, value):
    """An OSC message with one int32 (the encoding TwinKeys sends)."""
    def pad(b):
        b += b"\0"
        return b + b"\0" * (-len(b) % 4)
    return pad(address.encode()) + pad(b",i") + struct.pack(">i", value)


class FakeDeskTests(unittest.TestCase):
    def test_get_and_set(self):
        d = desk.FakeDesk("ql5")
        self.assertEqual(d.handle("get %s 3 0" % IN), ('OK get %s 3 0 -32768 "-Inf"' % IN, None))
        answer, notify = d.handle("set %s 3 0 -500" % IN)
        self.assertEqual(answer, 'OK set %s 3 0 -500 "-5.00"' % IN)
        self.assertEqual(notify, 'NOTIFY set %s 3 0 -500 "-5.00"' % IN)
        self.assertEqual(d.handle("get %s 3 0\r" % IN)[0], 'OK get %s 3 0 -500 "-5.00"' % IN)
        # Clamped: OKm.
        self.assertEqual(d.handle("set %s 0 0 2000" % IN)[0], 'OKm set %s 0 0 1000 "10.00"' % IN)
        self.assertEqual(d.handle("set %s 1 0 -32768" % IN)[0], 'OK set %s 1 0 -32768 "-Inf"' % IN)

    def test_stereo_inputs_and_limits(self):
        d = desk.FakeDesk("dm3")
        self.assertTrue(d.handle("set %s 1 0 -1200" % ST)[0].startswith("OK set"))
        self.assertEqual(d.handle("get %s 2 0" % ST)[0], "ERROR get InvalidArgument")     # DM3: one ST IN (x 0, 1)
        self.assertEqual(d.handle("get %s 16 0" % IN)[0], "ERROR get InvalidArgument")    # 16 inputs (x 0-15)
        self.assertTrue(d.handle("get %s 15 0" % IN)[0].startswith("OK get"))
        self.assertEqual(desk.FakeDesk("dm7").handle("get %s 0 0" % ST)[0], "ERROR get UnknownAddress")
        self.assertTrue(desk.FakeDesk("dm7").handle("get %s 119 0" % IN)[0].startswith("OK get"))
        for model, (inputs, stereo) in desk.MODELS.items():
            d = desk.FakeDesk(model)
            self.assertEqual(d.limit(IN), inputs)
            self.assertEqual(d.limit(ST), 2 * stereo)

    def test_errors_and_other_commands(self):
        d = desk.FakeDesk("ql1")
        self.assertEqual(d.handle("get MIXER:Current/InCh/Fader/On 0 0")[0], "ERROR get UnknownAddress")
        self.assertEqual(d.handle("set %s 0 0" % IN)[0], "ERROR set WrongFormat")
        self.assertEqual(d.handle("set %s 0 1 0" % IN)[0], "ERROR set InvalidArgument")
        self.assertEqual(d.handle("set %s x 0 0" % IN)[0], "ERROR set WrongFormat")
        self.assertEqual(d.handle("scene recall 1")[0], "ERROR scene UnknownCommand")
        self.assertEqual(d.handle("scpmode keepalive 10000")[0], "OK scpmode keepalive 10000")
        self.assertEqual(d.handle("devstatus runmode")[0], 'OK devstatus runmode "normal"')
        self.assertEqual(d.handle("   "), (None, None))

    def test_no_read(self):
        d = desk.FakeDesk("dm5", can_read=False)
        self.assertEqual(d.handle("get %s 0 0" % IN)[0], "ERROR get UnknownAddress")
        self.assertTrue(d.handle("set %s 0 0 -600" % IN)[0].startswith("OK set"))   # writes still work
        self.assertEqual(d.level(IN, 0), -600)

    def test_osc_writes(self):
        d = desk.FakeDesk("dm3")
        text, notify = d.handle_osc(osc("/yosc:req/set/MIXER:Current/InCh/Fader/Level/9/1", -600))
        self.assertIn("InCh 9", text)
        self.assertEqual(notify, 'NOTIFY set %s 8 0 -600 "-6.00"' % IN)
        self.assertEqual(d.level(IN, 8), -600)
        d.handle_osc(osc("/yosc:req/set/MIXER:Current/StInCh/Fader/Level/2/1", -32768))
        self.assertEqual(d.level(ST, 1), -32768)
        d7 = desk.FakeDesk("dm7")
        d7.handle_osc(osc("/yosc:req/set/MIXER:Current/InCh/Fader/Level/120", 0))
        self.assertEqual(d7.level(IN, 119), 0)
        self.assertIn("no such channel", d7.handle_osc(osc("/yosc:req/set/MIXER:Current/InCh/Fader/Level/121", 0))[0])
        self.assertIn("unreadable", d7.handle_osc(b"/abc")[0])
        self.assertIn("unreadable", d7.handle_osc(b"garbage")[0])
        self.assertEqual(desk.decode_osc(osc("/a", -500)), ("/a", [-500]))

    def test_moves_on_the_console_and_starting_levels(self):
        d = desk.FakeDesk("ql5")
        self.assertEqual(d.move(IN, 0, -1000), 'NOTIFY set %s 0 0 -1000 "-10.00"' % IN)
        desk.initial_level(d, "2=-6")
        desk.initial_level(d, "st1=-12")
        self.assertEqual(d.level(IN, 1), -600)
        self.assertEqual((d.level(ST, 0), d.level(ST, 1)), (-1200, -1200))
        self.assertEqual(desk.parse_db("-inf"), -32768)
        self.assertEqual(desk.parse_db("+20"), 1000)
        with self.assertRaises(ValueError):
            desk.initial_level(d, "65=0")
        with self.assertRaises(ValueError):
            desk.FakeDesk("ql9")


class FakeDeskSocketTests(unittest.TestCase):
    """The real sockets on 127.0.0.1 with free ports."""

    def test_rcp_notify_and_osc(self):
        asyncio.run(self._run())

    async def _run(self):
        lines = []
        server = desk.Server(desk.FakeDesk("ql5"), out=lines.append)
        rcp, osc_port = await server.start("127.0.0.1", 0, 0)
        try:
            # Both Macs (and StageMix) can be connected at once.
            r1, w1 = await asyncio.open_connection("127.0.0.1", rcp)
            r2, w2 = await asyncio.open_connection("127.0.0.1", rcp)
            r3, w3 = await asyncio.open_connection("127.0.0.1", rcp)
            w1.write(("set %s 8 0 -600\n" % IN).encode())
            await w1.drain()
            self.assertEqual(await asyncio.wait_for(r1.readline(), 2), ('OK set %s 8 0 -600 "-6.00"\n' % IN).encode())
            # Every other client hears about it; the one that set it does not.
            for r in (r2, r3):
                self.assertEqual(await asyncio.wait_for(r.readline(), 2), ('NOTIFY set %s 8 0 -600 "-6.00"\n' % IN).encode())
            # A fader moved on the console itself reaches every client.
            self.assertTrue(desk.console_command(server, "in 2 -10"))
            for r in (r1, r2, r3):
                self.assertEqual(await asyncio.wait_for(r.readline(), 2), ('NOTIFY set %s 1 0 -1000 "-10.00"\n' % IN).encode())
            w3.close()
            w2.write(("get %s 8 0\n" % IN).encode())
            await w2.drain()
            self.assertEqual(await asyncio.wait_for(r2.readline(), 2), ('OK get %s 8 0 -600 "-6.00"\n' % IN).encode())

            loop = asyncio.get_running_loop()
            transport, _ = await loop.create_datagram_endpoint(asyncio.DatagramProtocol, remote_addr=("127.0.0.1", osc_port))
            transport.sendto(osc("/yosc:req/set/MIXER:Current/InCh/Fader/Level/1", -32768))
            # A QL has no OSC fader addresses of its own; the fake still applies them, and says so.
            got = await asyncio.wait_for(r1.readline(), 2)
            self.assertEqual(got, ('NOTIFY set %s 0 0 -32768 "-Inf"\n' % IN).encode())
            transport.close()
            self.assertTrue(any(l.startswith("OSC /yosc:req/set/") for l in lines))

            # "drop" closes every connection.
            self.assertTrue(desk.console_command(server, "drop"))
            self.assertEqual(await asyncio.wait_for(r1.read(), 2), b"")
            self.assertFalse(desk.console_command(server, "quit"))
            for w in (w1, w2):
                w.close()
        finally:
            server.close()


if __name__ == "__main__":
    unittest.main()
