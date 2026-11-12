"""Non-blocking UDP transport, restricted to 127.0.0.1 (no Live dependency).

Live's embedded Python runs Remote Scripts on its main thread, so this
module never blocks: the socket is non-blocking and is polled from
update_display().
"""

import errno
import socket

from .constants import (LOOPBACK_HOST, COMMAND_PORT, STATE_PORT,
                        MAX_DATAGRAM_BYTES, RECV_BUFFER_BYTES,
                        SEND_BUFFER_BYTES)


class LoopbackOnlyError(ValueError):
    pass


def _require_loopback(host):
    if host != LOOPBACK_HOST:
        raise LoopbackOnlyError(
            "TwinKeys Bridge only binds/sends to %s, not %r"
            % (LOOPBACK_HOST, host))


class UdpTransport(object):
    """Listens on 127.0.0.1:listen_port and sends to 127.0.0.1:dest_port."""

    def __init__(self, listen_port=COMMAND_PORT, dest_port=STATE_PORT,
                 host=LOOPBACK_HOST, socket_factory=socket.socket):
        _require_loopback(host)
        self.listen_addr = (host, int(listen_port))
        self.dest_addr = (LOOPBACK_HOST, int(dest_port))
        _require_loopback(self.dest_addr[0])
        self.sent = 0
        self.dropped = 0
        self.recv_errors = 0
        sock = socket_factory(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            sock.setblocking(False)
            try:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF,
                                SEND_BUFFER_BYTES)
            except (OSError, AttributeError):
                pass
            # No SO_REUSEADDR: we do not want to share the port.
            sock.bind(self.listen_addr)
        except Exception:
            try:
                sock.close()
            except Exception:
                pass
            raise
        self._sock = sock

    @property
    def bound_address(self):
        try:
            return self._sock.getsockname()
        except (OSError, AttributeError):
            return self.listen_addr

    def receive(self, max_count):
        """Return up to max_count datagrams (bytes) that came from 127.0.0.1."""
        out = []
        # Every recvfrom() counts, errors and dropped datagrams included, so
        # a persistent error (e.g. EBADF) cannot spin here forever.
        for _ in range(max(0, int(max_count)) * 2):
            if len(out) >= max_count:
                break
            try:
                data, addr = self._sock.recvfrom(RECV_BUFFER_BYTES)
            except (BlockingIOError, InterruptedError):
                break
            except OSError as exc:
                if exc.errno in (errno.EAGAIN, errno.EWOULDBLOCK):
                    break
                # E.g. ECONNREFUSED reported for an earlier send: try again
                # (within the bound above).
                self.recv_errors += 1
                if exc.errno in (errno.EBADF, errno.ENOTSOCK, errno.EINVAL):
                    break   # the socket itself is unusable
                continue
            if not addr or addr[0] != LOOPBACK_HOST:
                continue  # defence in depth; cannot happen on a loopback bind
            out.append(data)
        return out

    def send(self, data):
        """Send one datagram to 127.0.0.1:dest_port. Returns True if sent."""
        if len(data) >= MAX_DATAGRAM_BYTES:
            self.dropped += 1
            return False
        try:
            self._sock.sendto(data, self.dest_addr)
        except OSError:
            # Would block / no buffer space / nobody listening: drop it. The
            # periodic full resend repairs any lost state.
            self.dropped += 1
            return False
        self.sent += 1
        return True

    def close(self):
        try:
            self._sock.close()
        except Exception:
            pass
