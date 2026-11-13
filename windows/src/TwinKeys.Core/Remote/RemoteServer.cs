using System.Collections.Concurrent;
using System.Diagnostics;
using System.Net;
using System.Net.Sockets;

namespace TwinKeys.Core;

/// <summary>
/// Waits for TwinKeys Remote (iPhone / iPad) on TCP (port of Sources/TwinKeys/RemoteServer.swift).
/// Every connection must know the pairing code, prove its device key, and be approved on this
/// computer once (4-digit code). Uses System.Net.Sockets only, so it is in Core and its tests run
/// on Linux with a fake iPhone; the App advertises the port with DNS-SD (_twinkeys-remote._tcp).
/// </summary>
public sealed class RemoteServer : IDisposable
{
    /// <summary>An approved device that sends nothing for this long is gone (it pings every 2 s).</summary>
    public const double IdleLimit = 8;
    /// <summary>The handshake must be finished in this time.</summary>
    public const double HandshakeLimit = 10;
    /// <summary>Bytes queued to one device: above SlowLimit meters and clip progress are skipped, above DropLimit it is disconnected.</summary>
    public const int SlowLimit = 1 << 20, DropLimit = 8 << 20;
    public const int MaxClients = 8;
    /// <summary>The TCP port the Windows app asks for (the Mac lets the system choose; both are found with DNS-SD).</summary>
    public const ushort DefaultPort = 47803;

    private readonly object gate = new();
    private readonly string serverId;
    private string serverName;
    private PairingSecret? pairing;
    private Socket? listener;
    private Timer? sweeper;
    private readonly Dictionary<int, Client> clients = [];
    private int nextKey;
    private readonly RemoteApprovalGate approvals = new();
    private readonly Stopwatch clock = Stopwatch.StartNew();
    private readonly ushort wantedPort;
    private bool disposed;
    private double Now => clock.Elapsed.TotalSeconds;

    // Hooks (set by the App). Called on TwinKeys threads, never under this object's lock unless noted.
    /// <summary>Is this device approved?</summary>
    public Func<RemoteClientHello, bool> IsApproved { get; set; } = _ => false;
    /// <summary>Ask the person; call the answer with true to allow. <c>token</c> names this question.</summary>
    public Action<int, string, string, Action<bool>> AskApproval { get; set; } = (_, _, _, a) => a(false);
    /// <summary>The question is over without an answer (time limit, or the device left): close its dialog.</summary>
    public Action<int> CancelApproval { get; set; } = _ => { };
    /// <summary>Runs a command from the iPhone: done(ok, error, backupDelivery); late(ok) when Live answered after the 1 s limit.</summary>
    public Action<LiveCommand, Action<bool, string?, string>, Action<bool>> RunCommand { get; set; } = (_, d, _) => d(false, "not ready", "notSent");
    public Func<int?> CurrentStructure { get; set; } = () => null;
    public Func<int?> CurrentSceneCount { get; set; } = () => null;
    public Func<ushort, bool> PressCue { get; set; } = _ => false;
    public Action BecomeMain { get; set; } = () => { };
    public Action AllNotesOff { get; set; } = () => { };
    public Func<LiveState> Snapshot { get; set; } = () => new LiveState();
    public Func<RemoteStatus?> Status { get; set; } = () => null;
    public Action<string>? Log { get; set; }
    /// <summary>The approved devices connected now, and their watches combined.</summary>
    public Action<int, WatchLevel>? ClientsChanged { get; set; }
    /// <summary>A device was allowed: remember it.</summary>
    public Action<RemoteClientHello> OnApproved { get; set; } = _ => { };

    private sealed class Client
    {
        public required int Key;
        public required Socket Socket;
        public required RemoteSession Session;
        public RemoteClientHello? Hello;
        public string Code = "";
        public bool Proven, Approved;
        public int? ApprovalToken;
        public bool Locked;
        public LockScope LockScope = LockScope.Standard;
        public double LastHeard, Since;
        public int? SeenStructure;
        public RemoteWatchState? Watch;
        public readonly BlockingCollection<byte[]> Outbox = new();
        public int InFlight;
        public bool Closed;
        public string Who => Hello?.DeviceName ?? "?";
    }

    public RemoteServer(string serverId, string serverName, ushort port = 0)
    {
        this.serverId = serverId;
        this.serverName = serverName;
        wantedPort = port;
    }

    /// <summary>The TCP port listened on (null: not listening).</summary>
    public ushort? Port { get; private set; }
    public Action<ushort?>? PortChanged { get; set; }

    /// <summary>Starts (or restarts) with this pairing code. null stops it: nothing works without a code.</summary>
    public void Configure(PairingSecret? secret)
    {
        ushort? port;
        lock (gate)
        {
            if (disposed) return;
            pairing = secret;
            DropAllLocked();
            listener?.Dispose(); listener = null; Port = null;
            if (secret is not null) StartListenerLocked();
            port = Port;
            sweeper ??= new Timer(_ => Sweep(), null, 1000, 1000);
        }
        PortChanged?.Invoke(port);
    }

    public void SetName(string name) { lock (gate) serverName = name; }

    private void StartListenerLocked()
    {
        // The fixed port when it is free (a firewall rule can name it), else any port: the iPhone finds it with DNS-SD.
        Socket? s = TryListen(wantedPort) ?? (wantedPort != 0 ? TryListen(0) : null);
        if (s is null) return;
        listener = s;
        Port = (ushort)((IPEndPoint)s.LocalEndPoint!).Port;
        Log?.Invoke($"Remote: waiting for iPhones on TCP port {Port}");
        new Thread(() => AcceptLoop(s)) { IsBackground = true, Name = "TwinKeys Remote accept" }.Start();
    }

    private Socket? TryListen(ushort port)
    {
        var s = new Socket(Socket.OSSupportsIPv6 ? AddressFamily.InterNetworkV6 : AddressFamily.InterNetwork, SocketType.Stream, ProtocolType.Tcp);
        try
        {
            if (s.AddressFamily == AddressFamily.InterNetworkV6) s.DualMode = true;
            s.Bind(new IPEndPoint(s.AddressFamily == AddressFamily.InterNetworkV6 ? IPAddress.IPv6Any : IPAddress.Any, port));
            s.Listen(16);
            return s;
        }
        catch (SocketException e)
        {
            s.Dispose();
            Log?.Invoke($"Remote: cannot listen on TCP port {port} ({e.SocketErrorCode})");
            return null;
        }
    }

    private void AcceptLoop(Socket l)
    {
        while (true)
        {
            Socket c;
            try { c = l.Accept(); }
            catch (SocketException) { lock (gate) if (listener != l) return; continue; }
            catch (ObjectDisposedException) { return; }
            Accept(c);
        }
    }

    private void Accept(Socket s)
    {
        Client c;
        lock (gate)
        {
            if (pairing is null || clients.Count >= MaxClients || disposed) { s.Dispose(); return; }
            try
            {
                s.NoDelay = true;
                // Keepalive: a phone that vanished (Wi-Fi gone, battery) is noticed by TCP too.
                s.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.KeepAlive, true);
                s.SetSocketOption(SocketOptionLevel.Tcp, SocketOptionName.TcpKeepAliveTime, 5);
                s.SetSocketOption(SocketOptionLevel.Tcp, SocketOptionName.TcpKeepAliveInterval, 2);
                s.SetSocketOption(SocketOptionLevel.Tcp, SocketOptionName.TcpKeepAliveRetryCount, 3);
            }
            catch (SocketException) { }
            c = new Client { Key = ++nextKey, Socket = s, Session = RemoteSession.Server(pairing), LastHeard = Now, Since = Now };
            clients[c.Key] = c;
        }
        new Thread(() => ReceiveLoop(c)) { IsBackground = true, Name = "TwinKeys Remote receive" }.Start();
        new Thread(() => SendLoop(c)) { IsBackground = true, Name = "TwinKeys Remote send" }.Start();
    }

    private void ReceiveLoop(Client c)
    {
        var buf = new byte[65536];
        while (true)
        {
            int n;
            try { n = c.Socket.Receive(buf); }
            catch (Exception e) when (e is SocketException or ObjectDisposedException) { Close(c); return; }
            if (n <= 0) { Close(c); return; }
            List<RemoteSession.Event> events;
            lock (gate)
            {
                if (c.Closed) return;
                c.LastHeard = Now;
                try { events = c.Session.Receive(buf.AsSpan(0, n)); }
                catch (RemoteException e)
                {
                    Log?.Invoke($"Remote: closed a connection ({e.Reason})");
                    CloseLocked(c);
                    return;
                }
            }
            foreach (var e in events) Handle(e, c);
        }
    }

    private void SendLoop(Client c)
    {
        try
        {
            foreach (var bytes in c.Outbox.GetConsumingEnumerable())
            {
                try { c.Socket.Send(bytes); }
                catch (Exception e) when (e is SocketException or ObjectDisposedException) { Close(c); return; }
                Interlocked.Add(ref c.InFlight, -bytes.Length);
            }
        }
        catch (ObjectDisposedException) { }
    }

    private void Handle(RemoteSession.Event e, Client c)
    {
        switch (e)
        {
            case RemoteSession.Event.ClientHello ch:
                lock (gate)
                {
                    c.Hello = ch.Hello; c.Code = ch.ConfirmCode;
                    byte[] sh;
                    try { sh = c.Session.ServerHelloFrame(serverId, serverName); }
                    catch (RemoteException) { CloseLocked(c); return; }
                    Enqueue(c, sh);
                }
                break;
            case RemoteSession.Event.ServerHello:
                Close(c);   // only clients send this
                break;
            case RemoteSession.Event.Message m:
                if (!c.Proven)
                {
                    // The first sealed message proves the device holds its key.
                    c.Proven = true;
                    DecideApproval(c);
                }
                if (c.Approved) HandleMessage(m.Value, c);
                break;
            case RemoteSession.Event.Unknown:
                break;   // a kind this version does not know (from a newer iPhone): skipped, as on the Mac 2.4
        }
    }

    private void DecideApproval(Client c)
    {
        if (c.Hello is not RemoteClientHello hello) { Close(c); return; }
        if (IsApproved(hello)) { Welcome(c); return; }
        int token;
        string name = hello.DeviceName, code;
        lock (gate)
        {
            switch (approvals.Request(hello.DeviceId, Now))
            {
                case RemoteApprovalGate.Decision.Ask a: token = a.Token; break;
                case RemoteApprovalGate.Decision.Busy:
                    // Another device is being asked about: refuse quietly (no second dialog).
                    Log?.Invoke($"Remote: {name} refused (another device is waiting for approval)");
                    CloseLocked(c);
                    return;
                default:
                    CloseLocked(c);   // refused a moment ago: no new dialog
                    return;
            }
            c.ApprovalToken = token;
            code = c.Code;
            SendLocked(new RemoteMessage.WaitingForApproval(code), c);
        }
        Log?.Invoke($"Remote: {name} asks to connect (code {code})");
        AskApproval(token, name, code, allow => Answered(token, c, allow));
    }

    /// <summary>The approval question ended. Ignored unless it is still the open question.</summary>
    private void Answered(int token, Client c, bool allow)
    {
        lock (gate)
        {
            if (!approvals.Finish(token, allow, Now)) return;
            if (c.ApprovalToken != token || c.Closed) return;
            c.ApprovalToken = null;
            if (!allow) { SendLocked(new RemoteMessage.Denied(), c); CloseLocked(c); return; }
        }
        if (c.Hello is RemoteClientHello h) OnApproved(h);
        Welcome(c);
    }

    private void Welcome(Client c)
    {
        var updates = Snapshot().InitialUpdates();
        var status = Status();
        lock (gate)
        {
            if (c.Closed) return;
            c.Approved = true;
            c.LastHeard = Now;
            // What this computer understands, so a new iPhone never sends what an older Mac cannot read.
            SendLocked(new RemoteMessage.Welcome(serverName, RemoteFeature.All), c);
            // In pieces (one clip column per message): a big set in one message could pass the iPhone's limit.
            foreach (var u in updates) SendLocked(new RemoteMessage.Update(u), c);
            if (status is not null) SendLocked(new RemoteMessage.Status(status), c);
        }
        Log?.Invoke($"Remote: {c.Who} connected");
        NotifyCount();
    }

    private void HandleMessage(RemoteMessage m, Client c)
    {
        switch (m)
        {
            case RemoteMessage.Command cmd: RunFromPhone(cmd.Id, cmd.Cmd, c.SeenStructure, c); break;
            case RemoteMessage.CommandAt ca: RunFromPhone(ca.Id, ca.Cmd, ca.Structure ?? c.SeenStructure, c); break;
            case RemoteMessage.Go g:
                // GO is never stopped by the show lock: launch the scene, then select the next one.
                RunFromPhone(g.Id, new LiveCommand.FireScene(g.Scene), g.Structure ?? c.SeenStructure, c, isGo: true);
                if (g.Scene + 1 < (CurrentSceneCount() ?? int.MaxValue))
                    RunFromPhone(-1, new LiveCommand.SelectScene(g.Scene + 1), g.Structure ?? c.SeenStructure, c, isGo: true);
                break;
            case RemoteMessage.BecomeMain b:
                Log?.Invoke($"Remote: {c.Who}: make this computer the main");
                BecomeMain();
                Send(new RemoteMessage.Result(b.Id, true, null, "notSent"), c);
                break;
            case RemoteMessage.Cue cue:
                {
                    if (c.Locked && (c.LockScope & LockScope.Cues) != 0) { Send(new RemoteMessage.Result(cue.Id, false, "locked", "notSent"), c); return; }
                    bool ok = PressCue(cue.Keycode);
                    Log?.Invoke($"Remote: {c.Who}: cue key {cue.Keycode}{(ok ? "" : " (not a cue key)")}");
                    Send(new RemoteMessage.Result(cue.Id, ok, ok ? null : "not a cue key", "see status"), c);
                    break;
                }
            case RemoteMessage.AllNotesOff a:
                Log?.Invoke($"Remote: {c.Who}: All Notes Off");
                AllNotesOff();
                Send(new RemoteMessage.Result(a.Id, true, null, "sent"), c);
                break;
            case RemoteMessage.Ping p:
                Send(new RemoteMessage.Pong(p.Time), c);
                // The iPhone's Apple Watch comes with its pings.
                if (p.Watch is not null && p.Watch != c.Watch) { c.Watch = p.Watch; NotifyCount(); }
                break;
            case RemoteMessage.Lock l:
                if (c.Locked != l.On) Log?.Invoke($"Remote: {c.Who}: show lock {(l.On ? "on" : "off")}");
                c.Locked = l.On;
                c.LockScope = LockScope.Standard;
                break;
            case RemoteMessage.LockScopeMsg ls:
                if (c.Locked != ls.On) Log?.Invoke($"Remote: {c.Who}: show lock {(ls.On ? "on" : "off")}");
                c.Locked = ls.On;
                c.LockScope = (LockScope)ls.Scope;
                break;
        }
    }

    /// <summary>A Live command from an iPhone. <paramref name="seen"/>: the layout the iPhone was showing. Id -1: no answer.</summary>
    private void RunFromPhone(int id, LiveCommand cmd, int? seen, Client c, bool isGo = false)
    {
        if (!cmd.IsValid) { if (id >= 0) Send(new RemoteMessage.Result(id, false, "invalid", "notSent"), c); return; }
        // The show lock is enforced here too, not only on the iPhone.
        if (!isGo && c.Locked && c.LockScope.Blocks(cmd))
        {
            if (id >= 0) Send(new RemoteMessage.Result(id, false, "locked", "notSent"), c);
            return;
        }
        if (!cmd.IsContinuous) Log?.Invoke($"Remote: {c.Who}: {cmd}");
        // The iPhone was showing an older layout than Live has now: refuse before either Live runs it.
        if (cmd.TargetsLayout && seen is int s && CurrentStructure() is int now && s != now)
        {
            Log?.Invoke($"Remote: {c.Who}: {cmd} not run (Live's layout changed)");
            if (id >= 0) Send(new RemoteMessage.Result(id, false, "structure_changed", "notSent"), c);
            return;
        }
        RunCommand(cmd, (ok, err, backup) =>
        {
            if (!ok && !cmd.IsContinuous) Log?.Invoke($"Remote: {c.Who}: {cmd} not run ({err ?? "error"})");
            if (id >= 0) Send(new RemoteMessage.Result(id, ok, err, backup), c);
        }, ok =>
        {
            if (!ok || id < 0) return;
            // Live ran it after all: the iPhone must not think it failed (no second tap).
            Log?.Invoke($"Remote: {c.Who}: {cmd} ran late");
            Send(new RemoteMessage.Result(id, true, "late", "unknown"), c);
        });
    }

    /// <summary>Sends a Live change to every approved device.</summary>
    public void Broadcast(LiveUpdate u) => SendAll(new RemoteMessage.Update(u));

    public void BroadcastStatus()
    {
        if (Status() is RemoteStatus s) SendAll(new RemoteMessage.Status(s));
    }

    /// <summary>A device was removed from the approved list: disconnect it.</summary>
    public void Revoke(string deviceId)
    {
        lock (gate) foreach (var c in clients.Values.Where(c => c.Hello?.DeviceId == deviceId).ToList()) CloseLocked(c);
    }

    public int ApprovedCount { get { lock (gate) return clients.Values.Count(c => c.Approved); } }

    private void Send(RemoteMessage m, Client c) { lock (gate) SendLocked(m, c); }

    private void SendLocked(RemoteMessage m, Client c)
    {
        if (c.Closed || c.Outbox.IsAddingCompleted) return;
        byte[] bytes;
        try { bytes = c.Session.Seal(m); }
        catch (RemoteException) { return; }
        if (m is RemoteMessage.Update { Value: LiveUpdate.Song s }) c.SeenStructure = s.Value.Structure;
        if (m is RemoteMessage.Update { Value: LiveUpdate.Full f }) c.SeenStructure = f.State.Song.Structure;
        Enqueue(c, bytes);
    }

    private static void Enqueue(Client c, byte[] bytes)
    {
        Interlocked.Add(ref c.InFlight, bytes.Length);
        try { c.Outbox.Add(bytes); }
        catch (InvalidOperationException) { }
    }

    private void SendAll(RemoteMessage m)
    {
        bool skippable = m is RemoteMessage.Update { Value: LiveUpdate.Meters or LiveUpdate.Progress };
        lock (gate)
        {
            foreach (var c in clients.Values.Where(c => c.Approved).ToList())
            {
                if (c.InFlight > DropLimit)
                {
                    Log?.Invoke($"Remote: {c.Who} is not keeping up; disconnected");
                    CloseLocked(c);
                    continue;
                }
                // A slow device skips meters and clip progress (newer ones follow) until it catches up.
                if (skippable && c.InFlight > SlowLimit) continue;
                SendLocked(m, c);
            }
        }
    }

    /// <summary>Once a second: handshakes that take too long, quiet devices, approvals out of time.</summary>
    private void Sweep()
    {
        var cancel = new List<int>();
        lock (gate)
        {
            double now = Now;
            foreach (var c in clients.Values.ToList())
            {
                if (!c.Proven && now - c.Since > HandshakeLimit) { CloseLocked(c); continue; }
                if (c.Approved && now - c.LastHeard > IdleLimit)
                {
                    Log?.Invoke($"Remote: {c.Who} stopped answering; disconnected");
                    CloseLocked(c);
                    continue;
                }
                if (c.ApprovalToken is int t && approvals.IsExpired(t, now + 0.5))
                {
                    Log?.Invoke($"Remote: {c.Who} was not allowed in time");
                    approvals.Finish(t, false, now);
                    c.ApprovalToken = null;
                    cancel.Add(t);
                    SendLocked(new RemoteMessage.Denied(), c);
                    CloseLocked(c);
                }
            }
        }
        foreach (var t in cancel) CancelApproval(t);
    }

    private void Close(Client c) { lock (gate) CloseLocked(c); }

    private void CloseLocked(Client c)
    {
        if (c.Closed) return;
        c.Closed = true;
        clients.Remove(c.Key);
        // The connection is going away: an open question about it ends (refused) and its dialog closes.
        if (c.ApprovalToken is int t)
        {
            c.ApprovalToken = null;
            if (approvals.Finish(t, false, Now)) ThreadPool.QueueUserWorkItem(_ => CancelApproval(t));
        }
        c.Outbox.CompleteAdding();
        // Let the queued bytes (a "denied") go out, then close.
        ThreadPool.QueueUserWorkItem(_ =>
        {
            var until = DateTime.UtcNow.AddMilliseconds(500);
            while (c.Outbox.Count > 0 && DateTime.UtcNow < until) Thread.Sleep(10);
            try { c.Socket.Shutdown(SocketShutdown.Both); } catch (Exception e) when (e is SocketException or ObjectDisposedException) { }
            c.Socket.Dispose();
        });
        if (c.Approved) ThreadPool.QueueUserWorkItem(_ => NotifyCount());
    }

    private void DropAllLocked()
    {
        foreach (var c in clients.Values.ToList()) CloseLocked(c);
    }

    private void NotifyCount()
    {
        int n;
        WatchLevel w;
        lock (gate)
        {
            var approved = clients.Values.Where(c => c.Approved).ToList();
            n = approved.Count;
            w = approved.Select(c => c.Watch?.Level ?? WatchLevel.Absent).DefaultIfEmpty(WatchLevel.Absent).Max();
        }
        ClientsChanged?.Invoke(n, w);
    }

    public void Dispose()
    {
        lock (gate)
        {
            disposed = true;
            DropAllLocked();
            listener?.Dispose(); listener = null;
            sweeper?.Dispose();
        }
    }
}
