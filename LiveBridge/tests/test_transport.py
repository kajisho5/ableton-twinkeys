import json
import socket
import unittest

from TwinKeysBridge.transport import UdpTransport, LoopbackOnlyError
from TwinKeysBridge.constants import (LOOPBACK_HOST, COMMAND_PORT,
                                      STATE_PORT, MAX_DATAGRAM_BYTES)


class RecordingSocket(object):
    """Stands in for socket.socket and records how it is used."""
    instances = []

    def __init__(self, family, kind):
        self.family = family
        self.kind = kind
        self.bound = None
        self.blocking = None
        self.sent = []
        self.inbox = []
        self.closed = False
        RecordingSocket.instances.append(self)

    def setblocking(self, flag):
        self.blocking = flag

    def setsockopt(self, *a):
        pass

    def bind(self, addr):
        self.bound = addr

    def getsockname(self):
        return self.bound

    def sendto(self, data, addr):
        self.sent.append((data, addr))

    def recvfrom(self, n):
        if not self.inbox:
            raise BlockingIOError()
        return self.inbox.pop(0)

    def close(self):
        self.closed = True


class LoopbackBindingTest(unittest.TestCase):

    def setUp(self):
        RecordingSocket.instances = []

    def test_binds_only_127_0_0_1(self):
        t = UdpTransport(socket_factory=RecordingSocket)
        sock = RecordingSocket.instances[0]
        self.assertEqual(sock.bound, ("127.0.0.1", COMMAND_PORT))
        self.assertNotEqual(sock.bound[0], "0.0.0.0")
        self.assertIs(sock.blocking, False)
        self.assertEqual(sock.family, socket.AF_INET)
        self.assertEqual(sock.kind, socket.SOCK_DGRAM)
        t.send(b"{}")
        self.assertEqual(sock.sent[0][1], ("127.0.0.1", STATE_PORT))

    def test_refuses_other_hosts(self):
        for host in ("0.0.0.0", "", "localhost", "192.168.1.2", "::"):
            with self.assertRaises(LoopbackOnlyError):
                UdpTransport(host=host, socket_factory=RecordingSocket)
        self.assertEqual(RecordingSocket.instances, [])

    def test_drops_non_loopback_senders_and_oversize(self):
        t = UdpTransport(socket_factory=RecordingSocket)
        sock = RecordingSocket.instances[0]
        sock.inbox = [(b"a", ("10.0.0.5", 1)), (b"b", ("127.0.0.1", 2))]
        self.assertEqual(t.receive(10), [b"b"])
        self.assertFalse(t.send(b"x" * MAX_DATAGRAM_BYTES))
        self.assertEqual(sock.sent, [])

    def test_real_socket_round_trip(self):
        rx = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        rx.bind((LOOPBACK_HOST, 0))
        rx.settimeout(2)
        try:
            t = UdpTransport(listen_port=0, dest_port=rx.getsockname()[1])
            try:
                host, port = t.bound_address
                self.assertEqual(host, "127.0.0.1")
                big = json.dumps({"x": "y" * 50000}).encode()
                self.assertTrue(t.send(big))
                data, _ = rx.recvfrom(65535)
                self.assertEqual(data, big)
                rx.sendto(b'{"cmd":"hello","id":1}', (LOOPBACK_HOST, port))
                got = []
                for _ in range(200):
                    got = t.receive(4)
                    if got:
                        break
                    import time
                    time.sleep(0.01)
                self.assertEqual(got, [b'{"cmd":"hello","id":1}'])
            finally:
                t.close()
        finally:
            rx.close()


if __name__ == "__main__":
    unittest.main()
