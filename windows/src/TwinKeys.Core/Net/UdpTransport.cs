using System.Collections.Concurrent;
using System.Net;
using System.Net.Sockets;

namespace TwinKeys.Core;

/// <summary>
/// UDP send and receive for the link (the Windows counterpart of the Mac's NetworkService, without
/// mDNS, which is platform code). One dual-stack socket (IPv4 and IPv6) on the fixed port 47801; if
/// that port is taken, a free port is used and 47801 is tried again every 30 s (a second socket).
///
/// Routes work like on the Mac: a datagram whose hello names a peer binds the address it came from
/// to that peer, and answers go back to that exact address from the same socket (the Mac's
/// Network.framework connections only accept answers from the address they talk to).
/// Sending happens on a dedicated thread, so the keyboard hook never waits for the network.
/// </summary>
public sealed class UdpTransport : IPacketSink, IDisposable
{
    public const ushort FixedPort = ManualAddress.DefaultPort;

    private readonly object gate = new();
    private readonly List<Socket> sockets = [];
    private IPAddress bindAddress;
    private readonly ushort wantedPort;
    private readonly Dictionary<string, Route> routes = [];
    private readonly Dictionary<RouteKey, string> routePeer = [];
    private readonly Dictionary<string, IPEndPoint> discovered = [];
    private readonly Dictionary<string, IPEndPoint> manual = [];
    private readonly Dictionary<string, DateTime> lastReset = [];
    /// <summary>
    /// Packets for a peer without a route yet. The Conductor answers a hello (and sends its cue names)
    /// while the datagram is still being handled, before the address is bound to the peer; these go
    /// out as soon as it is (the Mac gets the same order from its serial network queue).
    /// </summary>
    private readonly Dictionary<string, List<(DateTime At, byte[] Bytes)>> pending = [];
    private readonly BlockingCollection<(Socket Socket, IPEndPoint To, byte[] Bytes)> outbox = new(boundedCapacity: 4096);
    private Timer? fixedPortRetry;
    private volatile bool disposed;

    private readonly record struct Route(Socket Socket, IPEndPoint EndPoint);
    private readonly record struct RouteKey(Socket Socket, IPEndPoint EndPoint);

    /// <summary>A datagram arrived: return the peer it belongs to (or null). Called on a receive thread.</summary>
    public Func<byte[], string?, string?>? OnDatagram { get; set; }
    /// <summary>A fresh outgoing route to a peer was opened (say hello on it). Called on the thread pool.</summary>
    public Action<string>? OnNewRoute { get; set; }
    public Action<string>? Log { get; set; }

    /// <summary>The port actually listened on (47801 unless it was taken).</summary>
    public ushort? ListenPort { get; private set; }

    public UdpTransport(ushort port = FixedPort, IPAddress? bindAddress = null)
    {
        wantedPort = port;
        this.bindAddress = bindAddress ?? IPAddress.IPv6Any;
    }

    public void Start()
    {
        // A computer without IPv6 (rare, but CI containers exist): IPv4 only.
        if (bindAddress.Equals(IPAddress.IPv6Any) && !Socket.OSSupportsIPv6) bindAddress = IPAddress.Any;
        var s = TryOpen(wantedPort);
        if (s is null)
        {
            Log?.Invoke($"UDP port {wantedPort} in use; using another port for now");
            s = TryOpen(0) ?? throw new SocketException((int)SocketError.AddressAlreadyInUse);
            fixedPortRetry = new Timer(_ => RetryFixedPort(), null, TimeSpan.FromSeconds(30), TimeSpan.FromSeconds(30));
        }
        ListenPort = (ushort)((IPEndPoint)s.LocalEndPoint!).Port;
        Log?.Invoke($"Listening on UDP port {ListenPort}");
        var sender = new Thread(SendLoop) { IsBackground = true, Name = "TwinKeys UDP send", Priority = ThreadPriority.AboveNormal };
        sender.Start();
    }

    private Socket? TryOpen(ushort port)
    {
        Socket s;
        try { s = new Socket(bindAddress.AddressFamily, SocketType.Dgram, ProtocolType.Udp); }
        catch (SocketException) when (bindAddress.Equals(IPAddress.IPv6Any))
        {
            bindAddress = IPAddress.Any;
            s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        }
        try
        {
            if (bindAddress.AddressFamily == AddressFamily.InterNetworkV6) s.DualMode = true;
            if (OperatingSystem.IsWindows())
            {
                // Without this, an ICMP "port unreachable" makes the next receive fail on Windows.
                const int SIO_UDP_CONNRESET = -1744830452;
                s.IOControl(SIO_UDP_CONNRESET, [0, 0, 0, 0], null);
            }
            s.Bind(new IPEndPoint(bindAddress, port));
        }
        catch (SocketException)
        {
            s.Dispose();
            return null;
        }
        lock (gate) sockets.Add(s);
        var t = new Thread(() => ReceiveLoop(s)) { IsBackground = true, Name = $"TwinKeys UDP receive {port}", Priority = ThreadPriority.AboveNormal };
        t.Start();
        return s;
    }

    private void RetryFixedPort()
    {
        if (disposed) return;
        var s = TryOpen(wantedPort);
        if (s is null) return;
        fixedPortRetry?.Dispose();
        fixedPortRetry = null;
        Log?.Invoke($"Got UDP port {wantedPort} back");
    }

    private static IPEndPoint Normalize(IPEndPoint ep) =>
        ep.Address.IsIPv4MappedToIPv6 ? new IPEndPoint(ep.Address.MapToIPv4(), ep.Port) : ep;

    // MARK: Peer addresses

    /// <summary>The address a peer advertises with mDNS (or null when it is no longer seen).</summary>
    public void SetDiscovered(string peer, IPEndPoint? ep)
    {
        lock (gate)
        {
            if (ep is null) discovered.Remove(peer);
            else discovered[peer] = Normalize(ep);
        }
    }

    /// <summary>A typed address ("Connect by IP Address") under a placeholder ID ("manual:…").</summary>
    public void SetManual(string placeholder, IPEndPoint ep)
    {
        lock (gate) manual[placeholder] = Normalize(ep);
    }

    public bool HasAddress(string peer)
    {
        lock (gate) return routes.ContainsKey(peer) || discovered.ContainsKey(peer) || manual.ContainsKey(peer);
    }

    // MARK: IPacketSink

    public void Send(byte[] bytes, string peer)
    {
        Route? r;
        bool fresh = false;
        lock (gate)
        {
            r = RouteTo(peer, out fresh);
            if (r is null)
            {
                if (!pending.TryGetValue(peer, out var list)) pending[peer] = list = [];
                var now = DateTime.UtcNow;
                list.RemoveAll(x => now - x.At > TimeSpan.FromSeconds(2));
                if (list.Count < 64) list.Add((now, bytes));
                if (pending.Count > 16) pending.Remove(pending.Keys.First(k => k != peer));
                return;
            }
        }
        if (r is not Route route) return;
        if (fresh) ThreadPool.QueueUserWorkItem(_ => OnNewRoute?.Invoke(peer));
        outbox.TryAdd((route.Socket, route.EndPoint, bytes));
    }

    public void ResetRoute(string peer)
    {
        lock (gate)
        {
            if (!routes.TryGetValue(peer, out _)) return;
            // Only when we know where else to send (otherwise keep the route the peer opened to us).
            if (!discovered.ContainsKey(peer) && !manual.ContainsKey(peer)) return;
            if (lastReset.TryGetValue(peer, out var t) && DateTime.UtcNow - t < TimeSpan.FromSeconds(1)) return;
            lastReset[peer] = DateTime.UtcNow;
            routes.Remove(peer);
        }
    }

    /// <summary>Call with the lock held.</summary>
    private Route? RouteTo(string peer, out bool fresh)
    {
        fresh = false;
        if (routes.TryGetValue(peer, out var r)) return r;
        if (sockets.Count == 0) return null;
        IPEndPoint? ep = discovered.GetValueOrDefault(peer) ?? manual.GetValueOrDefault(peer);
        if (ep is null) return null;
        // Send from the socket on the fixed port when there is one (answers come back to it).
        var s = sockets.FirstOrDefault(x => ((IPEndPoint)x.LocalEndPoint!).Port == wantedPort) ?? sockets[0];
        var route = new Route(s, ep);
        Bind(route, peer);
        fresh = true;
        return route;
    }

    private void Bind(Route route, string peer)
    {
        routes[peer] = route;
        routePeer[new RouteKey(route.Socket, route.EndPoint)] = peer;
        if (pending.Remove(peer, out var waiting))
        {
            var now = DateTime.UtcNow;
            foreach (var (at, bytes) in waiting)
                if (now - at <= TimeSpan.FromSeconds(2)) outbox.TryAdd((route.Socket, route.EndPoint, bytes));
        }
        if (routePeer.Count > 256)
        {
            // Forget bindings no route uses any more.
            var used = routes.Values.Select(x => new RouteKey(x.Socket, x.EndPoint)).ToHashSet();
            foreach (var k in routePeer.Keys.Where(k => !used.Contains(k)).ToList()) routePeer.Remove(k);
        }
    }

    private void ReceiveLoop(Socket s)
    {
        var buffer = new byte[2048];
        EndPoint any = new IPEndPoint(bindAddress, 0);
        while (!disposed)
        {
            int n;
            EndPoint from = any;
            try { n = s.ReceiveFrom(buffer, ref from); }
            catch (SocketException) { if (disposed) return; continue; }
            catch (ObjectDisposedException) { return; }
            if (n <= 0 || n > WireProtocol.MaxPacketSize) continue;
            var ep = Normalize((IPEndPoint)from);
            var bytes = buffer.AsSpan(0, n).ToArray();
            var key = new RouteKey(s, ep);
            string? known;
            lock (gate) known = routePeer.GetValueOrDefault(key);
            string? peer;
            try { peer = OnDatagram?.Invoke(bytes, known); }
            catch (Exception e) { Log?.Invoke($"Error handling a datagram: {e.Message}"); continue; }
            if (peer is null) continue;
            lock (gate)
            {
                bool sameRoute = routes.TryGetValue(peer, out var cur) && cur.Socket == s && cur.EndPoint.Equals(ep);
                if (peer == known && sameRoute) continue;
                // A hello told us who is on the other end. A route opened to a typed address keeps that address.
                if (known is not null && known.StartsWith(PeerInfo.ManualPrefix, StringComparison.Ordinal) && manual.TryGetValue(known, out var mep))
                {
                    manual[peer] = mep;
                    manual.Remove(known);
                    routes.Remove(known);
                }
                Bind(new Route(s, ep), peer);
            }
        }
    }

    private void SendLoop()
    {
        try
        {
            foreach (var (socket, to, bytes) in outbox.GetConsumingEnumerable())
            {
                try { socket.SendTo(bytes, to); }
                catch (SocketException e) { Log?.Invoke($"UDP send to {to} failed: {e.SocketErrorCode}"); }
                catch (ObjectDisposedException) { return; }
            }
        }
        catch (ObjectDisposedException) { }
    }

    /// <summary>Waits until everything queued has gone out (used before quitting, so the goodbye is sent).</summary>
    public void Flush(TimeSpan timeout)
    {
        var until = DateTime.UtcNow + timeout;
        while (outbox.Count > 0 && DateTime.UtcNow < until) Thread.Sleep(5);
        Thread.Sleep(20);
    }

    public void Dispose()
    {
        if (disposed) return;
        disposed = true;
        fixedPortRetry?.Dispose();
        outbox.CompleteAdding();
        lock (gate)
        {
            foreach (var s in sockets) s.Dispose();
            sockets.Clear();
        }
    }
}
