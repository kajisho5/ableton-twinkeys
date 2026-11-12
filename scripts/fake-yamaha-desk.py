#!/usr/bin/env python3
"""A small fake Yamaha console for trying TwinKeys' console takeover (2.4, experimental)
without a real QL / DM console. Standard library only.

It speaks the subset of RCP that TwinKeys uses, on TCP 49280:

    get MIXER:Current/InCh/Fader/Level 3 0        -> OK get MIXER:Current/InCh/Fader/Level 3 0 -1000 "-10.00"
    set MIXER:Current/InCh/Fader/Level 3 0 -500   -> OK set MIXER:Current/InCh/Fader/Level 3 0 -500 "-5.00"
                                                     (OKm when the value had to be changed)
                                                     and NOTIFY set ... to every other client
    MIXER:Current/StInCh/Fader/Level              (stereo inputs: X = 2n for L, 2n+1 for R)
    scpmode keepalive 10000                       -> OK scpmode keepalive 10000
    devstatus runmode                             -> OK devstatus runmode "normal"

Levels are dB x 100; -32768 is -inf; finite levels are -13800 ... 1000.
It also listens for OSC on UDP 49900 (the DM consoles' documented fader writes), prints every
message and applies fader levels, so the RCP side and the other clients see them.

This is not Yamaha's software and does not behave like a console in every detail (for example,
the text after the value and the answer to devstatus are made up).

Usage:
    python3 scripts/fake-yamaha-desk.py --model ql5 --set 1=-6 --set 2=-6 --set st1=-12
    python3 scripts/fake-yamaha-desk.py --model dm5 --no-read      # answers get with ERROR

While it runs, type on its terminal:
    in 1 -6      move input channel 1 to -6 dB (as if moved on the console; NOTIFY to everyone)
    st 1 -12     move stereo input 1 (both halves)
    in 9 -inf    down to -inf
    show         print the levels that are not -inf
    drop         close every TCP connection (like pulling the cable for a moment)
    mute         stop answering anything (like a console that hangs); again to answer again
    quit
"""

import argparse
import asyncio
import struct
import sys
import threading

MINUS_INF = -32768
LOWEST = -13800
HIGHEST = 1000

INPUT = "MIXER:Current/InCh/Fader/Level"
STEREO = "MIXER:Current/StInCh/Fader/Level"

# Input channels and stereo inputs of each model (Yamaha's spec pages).
MODELS = {
    "ql1": (32, 8),
    "ql5": (64, 8),
    "dm3": (16, 1),
    "dm7": (120, 0),
    "dm7compact": (72, 0),
    "dm5": (60, 0),
    "dm5compact": (48, 0),
}


def level_text(v):
    """The text a console adds after the value (made up here): "-5.00", "-Inf"."""
    if v <= MINUS_INF:
        return "-Inf"
    return "%.2f" % (v / 100.0)


def clamp(v):
    if v <= MINUS_INF:
        return MINUS_INF
    return max(LOWEST, min(HIGHEST, v))


def parse_db(text):
    """"-6", "-6.5", "+3", "-inf" -> dB x 100."""
    t = text.strip().lower()
    if t in ("-inf", "inf", "-oo"):
        return MINUS_INF
    return clamp(int(round(float(t) * 100)))


class FakeDesk(object):
    """The console's state and its answers, without sockets (so it can be tested)."""

    def __init__(self, model="ql5", can_read=True):
        if model not in MODELS:
            raise ValueError("unknown model %r (choose from %s)" % (model, ", ".join(sorted(MODELS))))
        self.model = model
        self.inputs, self.stereo = MODELS[model]
        self.can_read = can_read
        self.levels = {}          # (parameter, x) -> value
        self.log = []

    def limit(self, parameter):
        if parameter == INPUT:
            return self.inputs
        if parameter == STEREO:
            return 2 * self.stereo
        return 0

    def level(self, parameter, x):
        return self.levels.get((parameter, x), MINUS_INF)

    def move(self, parameter, x, value):
        """A fader moved on the console itself. Returns the NOTIFY line for every client."""
        value = clamp(value)
        self.levels[(parameter, x)] = value
        return 'NOTIFY set %s %d 0 %d "%s"' % (parameter, x, value, level_text(value))

    def handle(self, line):
        """One line from a client. Returns (answer to that client or None, NOTIFY for the
        others or None)."""
        tokens = line.strip().split()
        if not tokens:
            return None, None
        command = tokens[0]
        if command == "scpmode":
            return "OK " + " ".join(tokens), None
        if command == "devstatus":
            if len(tokens) >= 2 and tokens[1] == "runmode":
                return 'OK devstatus runmode "normal"', None
            return "ERROR devstatus UnknownAddress", None
        if command not in ("get", "set"):
            return "ERROR %s UnknownCommand" % command, None
        if len(tokens) < 4 or (command == "set" and len(tokens) < 5):
            return "ERROR %s WrongFormat" % command, None
        parameter = tokens[1]
        if parameter not in (INPUT, STEREO) or self.limit(parameter) == 0:
            return "ERROR %s UnknownAddress" % command, None
        try:
            x = int(tokens[2])
            y = int(tokens[3])
        except ValueError:
            return "ERROR %s WrongFormat" % command, None
        if not (0 <= x < self.limit(parameter)) or y != 0:
            return "ERROR %s InvalidArgument" % command, None
        if command == "get":
            if not self.can_read:
                return "ERROR get UnknownAddress", None
            v = self.level(parameter, x)
            return 'OK get %s %d 0 %d "%s"' % (parameter, x, v, level_text(v)), None
        try:
            asked = int(tokens[4])
        except ValueError:
            return "ERROR set WrongFormat", None
        value = clamp(asked)
        self.levels[(parameter, x)] = value
        head = "OK" if value == asked else "OKm"
        answer = '%s set %s %d 0 %d "%s"' % (head, parameter, x, value, level_text(value))
        notify = 'NOTIFY set %s %d 0 %d "%s"' % (parameter, x, value, level_text(value))
        return answer, notify

    def handle_osc(self, data):
        """One OSC datagram. Returns (printable text, NOTIFY line or None)."""
        try:
            address, args = decode_osc(data)
        except (ValueError, struct.error) as e:
            return "OSC (unreadable: %s) %r" % (e, data[:64]), None
        text = "OSC %s %s" % (address, " ".join(repr(a) for a in args))
        parts = address.split("/")
        # /yosc:req/set/MIXER:Current/InCh/Fader/Level/<n>[/<y>]
        if len(parts) >= 8 and parts[1] == "yosc:req" and parts[2] == "set" and args and isinstance(args[0], int):
            parameter = "/".join(parts[3:7])
            try:
                n = int(parts[7])
            except ValueError:
                return text + "  (not a channel number)", None
            if parameter in (INPUT, STEREO) and 1 <= n <= self.limit(parameter):
                value = clamp(args[0])
                text += "  -> %s %d = %s dB" % ("InCh" if parameter == INPUT else "StInCh", n, level_text(value))
                return text, self.move(parameter, n - 1, value)
            return text + "  (no such channel on %s)" % self.model, None
        return text, None


def _osc_string(data, i):
    end = data.index(b"\0", i)
    s = data[i:end].decode("utf-8")
    return s, (end + 4) & ~3


def decode_osc(data):
    """Address and arguments of an OSC 1.0 message (int32, float32 and string arguments)."""
    if not data.startswith(b"/"):
        raise ValueError("not an OSC message")
    try:
        address, i = _osc_string(data, 0)
        tags, i = _osc_string(data, i)
    except ValueError:
        raise ValueError("unterminated string")
    if not tags.startswith(","):
        raise ValueError("no type tags")
    args = []
    for tag in tags[1:]:
        if tag == "i":
            args.append(struct.unpack(">i", data[i:i + 4])[0])
            i += 4
        elif tag == "f":
            args.append(struct.unpack(">f", data[i:i + 4])[0])
            i += 4
        elif tag == "s":
            s, i = _osc_string(data, i)
            args.append(s)
        else:
            raise ValueError("type %r not supported" % tag)
    return address, args


class Server(object):
    """The sockets: RCP over TCP, OSC over UDP."""

    def __init__(self, desk, out=print):
        self.desk = desk
        self.out = out
        self.clients = set()
        self.muted = False
        self.tcp = None
        self.udp = None

    def broadcast(self, line, skip=None):
        if self.muted:
            return
        for w in list(self.clients):
            if w is not skip:
                w.write((line + "\n").encode())

    async def client(self, reader, writer):
        peer = writer.get_extra_info("peername")
        self.out("RCP client connected: %s" % (peer,))
        self.clients.add(writer)
        try:
            while True:
                raw = await reader.readline()
                if not raw:
                    break
                line = raw.decode("utf-8", "replace").rstrip("\r\n")
                if self.muted:
                    continue
                answer, notify = self.desk.handle(line)
                if answer:
                    writer.write((answer + "\n").encode())
                if notify:
                    self.out("%s  (from %s)" % (notify, peer[0] if peer else "?"))
                    self.broadcast(notify, skip=writer)
                await writer.drain()
        except (ConnectionError, OSError):
            pass
        finally:
            self.clients.discard(writer)
            writer.close()
            self.out("RCP client left: %s" % (peer,))

    def drop_all(self):
        for w in list(self.clients):
            w.close()

    async def start(self, host, rcp_port, osc_port):
        loop = asyncio.get_running_loop()
        self.tcp = await asyncio.start_server(self.client, host, rcp_port)
        server = self

        class OSCProtocol(asyncio.DatagramProtocol):
            def datagram_received(self, data, addr):
                text, notify = server.desk.handle_osc(data)
                server.out("%s  (from %s:%d)" % (text, addr[0], addr[1]))
                if notify:
                    server.broadcast(notify)

        self.udp, _ = await loop.create_datagram_endpoint(OSCProtocol, local_addr=(host, osc_port))
        return self.tcp.sockets[0].getsockname()[1], self.udp.get_extra_info("sockname")[1]

    def close(self):
        if self.tcp:
            self.tcp.close()
        if self.udp:
            self.udp.close()
        self.drop_all()


def console_command(server, line):
    """A line typed on the fake console's terminal. Returns False to quit."""
    t = line.split()
    if not t:
        return True
    if t[0] in ("quit", "exit"):
        return False
    if t[0] == "show":
        shown = sorted((k, v) for k, v in server.desk.levels.items() if v > MINUS_INF)
        for (parameter, x), v in shown:
            name = "InCh %d" % (x + 1) if parameter == INPUT else "StInCh %d (%s)" % (x // 2 + 1, "L" if x % 2 == 0 else "R")
            server.out("%-18s %s dB" % (name, level_text(v)))
        if not shown:
            server.out("every fader is at -inf")
        return True
    if t[0] == "drop":
        server.out("closing %d connection(s)" % len(server.clients))
        server.drop_all()
        return True
    if t[0] == "mute":
        server.muted = not server.muted
        server.out("not answering" if server.muted else "answering again")
        return True
    if t[0] in ("in", "st") and len(t) == 3:
        try:
            n = int(t[1])
            value = parse_db(t[2])
        except ValueError:
            server.out("usage: in <channel> <dB>   or   st <stereo input> <dB>")
            return True
        if t[0] == "in" and 1 <= n <= server.desk.inputs:
            server.broadcast(server.desk.move(INPUT, n - 1, value))
        elif t[0] == "st" and 1 <= n <= server.desk.stereo:
            server.broadcast(server.desk.move(STEREO, 2 * (n - 1), value))
            server.broadcast(server.desk.move(STEREO, 2 * (n - 1) + 1, value))
        else:
            server.out("no such channel on %s" % server.desk.model)
            return True
        server.out("moved %s %d to %s dB" % ("InCh" if t[0] == "in" else "ST IN", n, level_text(value)))
        return True
    server.out("commands: in <ch> <dB>, st <n> <dB>, show, drop, mute, quit")
    return True


def initial_level(desk, spec):
    """--set 1=-6 (input 1) or --set st1=-12 (stereo input 1, both halves)."""
    name, _, db = spec.partition("=")
    value = parse_db(db)
    if name.lower().startswith("st"):
        n = int(name[2:])
        if not 1 <= n <= desk.stereo:
            raise ValueError("no stereo input %d on %s" % (n, desk.model))
        desk.levels[(STEREO, 2 * (n - 1))] = value
        desk.levels[(STEREO, 2 * (n - 1) + 1)] = value
    else:
        n = int(name)
        if not 1 <= n <= desk.inputs:
            raise ValueError("no input %d on %s" % (n, desk.model))
        desk.levels[(INPUT, n - 1)] = value


async def main(argv=None):
    p = argparse.ArgumentParser(description="Fake Yamaha console (RCP on TCP, OSC on UDP) for testing TwinKeys.")
    p.add_argument("--model", default="ql5", choices=sorted(MODELS))
    p.add_argument("--no-read", action="store_true", help="answer every get with ERROR (as a console that cannot be read)")
    p.add_argument("--host", default="0.0.0.0", help="address to listen on (default: all)")
    p.add_argument("--rcp-port", type=int, default=49280)
    p.add_argument("--osc-port", type=int, default=49900)
    p.add_argument("--set", action="append", default=[], metavar="CH=DB", help="starting level, e.g. 1=-6 or st1=-12")
    args = p.parse_args(argv)

    desk = FakeDesk(args.model, can_read=not args.no_read)
    for spec in args.set:
        try:
            initial_level(desk, spec)
        except ValueError as e:
            p.error("--set %s: %s" % (spec, e))
    server = Server(desk)
    rcp, osc = await server.start(args.host, args.rcp_port, args.osc_port)
    print("Fake %s: RCP on TCP %d, OSC on UDP %d%s. Type 'help' for commands."
          % (args.model.upper(), rcp, osc, " (levels cannot be read)" if args.no_read else ""))

    loop = asyncio.get_running_loop()
    done = loop.create_future()

    def read_stdin():
        for line in sys.stdin:
            keep = asyncio.run_coroutine_threadsafe(_command(server, line), loop).result()
            if not keep:
                break
        loop.call_soon_threadsafe(lambda: done.done() or done.set_result(None))

    if sys.stdin and sys.stdin.isatty():
        threading.Thread(target=read_stdin, daemon=True).start()
    try:
        await done
    finally:
        server.close()


async def _command(server, line):
    return console_command(server, line)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        pass
