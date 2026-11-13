using System.Net;
using System.Net.Sockets;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace TwinKeys.Core;

/// <summary>
/// Talks to the TwinKeysBridge Remote Script inside Live, on this computer only (127.0.0.1). Port of
/// Sources/TwinKeys/LiveBridgeClient.swift. Commands go to UDP 47811; the script sends state and
/// answers to UDP 47812 (LiveBridge/README.md). Uses only System.Net.Sockets, so it is in Core and
/// its tests run on Linux against a fake bridge and against the real script with a fake Live.
/// Thread-safe.
/// </summary>
public sealed class BridgeClient : IDisposable
{
    public const ushort DefaultCommandPort = 47811;
    public const ushort DefaultStatePort = 47812;
    /// <summary>Live answered within this many seconds: "connected".</summary>
    public const double ConnectedWindow = 6;
    /// <summary>A command without an answer after this long is reported as "no_answer".</summary>
    public const double AnswerTimeout = 1;
    /// <summary>…but a late answer is still reported (to <c>late</c>) for this long after that.</summary>
    public const double LateWindow = 10;

    private readonly object gate = new();
    private readonly ushort commandPort, statePort;
    private readonly Func<double> clock;
    private Socket? socket;
    private Timer? timer;
    private volatile bool stopped;
    private int nextId;
    private double lastHeard = double.NegativeInfinity;
    private double lastHello = double.NegativeInfinity;
    private double nextBind;
    private bool bindFailedLogged;
    private readonly LiveState state = new();

    private sealed record Pending(Action<bool, string?>? Done, Action<bool, string?>? Late, double SentAt);
    private readonly Dictionary<int, Pending> pending = [];
    private readonly Dictionary<int, (Action<bool, string?> Late, double Until)> latePending = [];

    /// <summary>Each change of Live's state (called on the receive thread; phase 3 sends it to the iPhones).</summary>
    public Action<LiveUpdate>? OnUpdate { get; set; }
    public Action<string>? Log { get; set; }

    public BridgeClient(ushort commandPort = DefaultCommandPort, ushort statePort = DefaultStatePort, Func<double>? clock = null)
    {
        this.commandPort = commandPort;
        this.statePort = statePort;
        var sw = System.Diagnostics.Stopwatch.StartNew();
        this.clock = clock ?? (() => sw.Elapsed.TotalSeconds);
    }

    /// <summary>Live answered within the last 6 s.</summary>
    public bool IsConnected { get { lock (gate) return clock() - lastHeard < ConnectedWindow; } }

    /// <summary>A copy of everything known about Live.</summary>
    public LiveState Snapshot() { lock (gate) return state.Copy(); }

    /// <summary>The track/scene layout counter of the latest "song" message (null: unknown).</summary>
    public int? Structure { get { lock (gate) return state.Song.Structure; } }

    public void Start()
    {
        lock (gate)
        {
            if (timer is not null) return;
            // Say hello every 2 s until Live answers (Live may start after TwinKeys), then whenever it is quiet for 5 s.
            timer = new Timer(_ => Tick(), null, TimeSpan.FromMilliseconds(200), TimeSpan.FromMilliseconds(100));
        }
    }

    /// <summary>
    /// Runs a command on this computer's Live. <paramref name="done"/> gets the script's answer, or
    /// (false, "no_answer") after 1 s. <paramref name="checkStructure"/>: send the layout this computer
    /// knows, so the script refuses the command ("structure_changed") if Live's layout changed since.
    /// <paramref name="late"/>: called if the script answers after <paramref name="done"/> reported "no_answer".
    /// Callbacks run on a TwinKeys thread, never under this object's lock.
    /// </summary>
    public void Run(LiveCommand cmd, bool checkStructure = false, Action<bool, string?>? done = null, Action<bool, string?>? late = null)
    {
        if (!cmd.IsValid) { done?.Invoke(false, "invalid"); return; }
        byte[] json;
        lock (gate)
        {
            int id = ++nextId;
            if (done is not null) pending[id] = new Pending(done, late, clock());
            json = cmd.BridgeJsonBytes(id, checkStructure ? state.Song.Structure : null);
        }
        Send(json);
    }

    private void Tick()
    {
        if (stopped) return;
        var fire = new List<Action>();
        bool hello = false;
        lock (gate)
        {
            double now = clock();
            if (socket is null && now >= nextBind) TryBind(now);
            if (now - lastHeard > 5 && now - lastHello >= 2)
            {
                lastHello = now;
                hello = true;
            }
            foreach (var (id, p) in pending.Where(kv => now - kv.Value.SentAt >= AnswerTimeout).ToList())
            {
                pending.Remove(id);
                if (p.Done is { } d) fire.Add(() => d(false, "no_answer"));
                if (p.Late is { } l) latePending[id] = (l, now + LateWindow);
            }
            foreach (var id in latePending.Where(kv => now >= kv.Value.Until).Select(kv => kv.Key).ToList()) latePending.Remove(id);
        }
        if (hello) SendHello();
        foreach (var f in fire) Safe(f);
    }

    private void SendHello()
    {
        int id;
        lock (gate) id = ++nextId;
        var b = new System.Buffers.ArrayBufferWriter<byte>();
        using (var w = new Utf8JsonWriter(b))
        {
            w.WriteStartObject();
            w.WriteString("cmd", "hello");
            w.WriteNumber("id", id);
            w.WriteEndObject();
        }
        Send(b.WrittenSpan.ToArray());
    }

    private void TryBind(double now)
    {
        Socket s = new(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        try
        {
            if (OperatingSystem.IsWindows())
            {
                // Without this, an ICMP "port unreachable" (Live not running) makes the next receive fail on Windows.
                const int SIO_UDP_CONNRESET = -1744830452;
                s.IOControl(SIO_UDP_CONNRESET, [0, 0, 0, 0], null);
                // Nobody else may take over the port (README: the script's side does not share it either).
                s.ExclusiveAddressUse = true;
            }
            // Large state bursts (a 200 x 200 set) must not overflow the receive buffer (LiveBridge/README.md).
            s.ReceiveBufferSize = 4 << 20;
            s.SendBufferSize = 1 << 20;
            // Only this computer: never reachable from the network.
            s.Bind(new IPEndPoint(IPAddress.Loopback, statePort));
        }
        catch (SocketException e)
        {
            s.Dispose();
            nextBind = now + 5;
            if (!bindFailedLogged) Log?.Invoke($"Live Bridge: cannot listen on 127.0.0.1:{statePort} ({e.SocketErrorCode}); retrying every 5 s");
            bindFailedLogged = true;
            return;
        }
        bindFailedLogged = false;
        socket = s;
        new Thread(() => ReceiveLoop(s)) { IsBackground = true, Name = "TwinKeys Live Bridge receive" }.Start();
    }

    private void Send(byte[] json)
    {
        Socket? s;
        lock (gate) s = socket;
        if (s is null) return;
        try { s.SendTo(json, new IPEndPoint(IPAddress.Loopback, commandPort)); }
        catch (SocketException) { }   // Live not running: the hello timer tries again
        catch (ObjectDisposedException) { }
    }

    private void ReceiveLoop(Socket s)
    {
        var buffer = new byte[65535];
        EndPoint any = new IPEndPoint(IPAddress.Any, 0);
        int errors = 0;
        while (!stopped)
        {
            int n;
            EndPoint from = any;
            try { n = s.ReceiveFrom(buffer, ref from); errors = 0; }
            catch (SocketException)
            {
                if (stopped) return;
                // A persistent error must not spin.
                if (++errors > 3) Thread.Sleep(50);
                continue;
            }
            catch (ObjectDisposedException) { return; }
            // Only the script on this computer (a loopback-bound socket cannot get others anyway).
            if (from is not IPEndPoint ep || !IPAddress.IsLoopback(ep.Address) || n <= 0) continue;
            JsonObject? obj;
            try { obj = JsonNode.Parse(buffer.AsSpan(0, n)) as JsonObject; }
            catch (JsonException) { continue; }
            if (obj is not null) Handle(obj);
        }
    }

    private void Handle(JsonObject m)
    {
        Action? fire = null;
        LiveUpdate? update = null;
        string? log = null;
        lock (gate)
        {
            double now = clock();
            if (now - lastHeard >= ConnectedWindow) log = "Live Bridge connected";
            lastHeard = now;
            string? type = m["type"] is JsonValue tv && tv.TryGetValue(out string? tx) ? tx : null;
            if (type == "ack")
            {
                if (m["id"] is JsonValue iv && iv.TryGetValue(out int id))
                {
                    bool ok = m["ok"] is JsonValue ov && ov.TryGetValue(out bool b) && b;
                    string? err = m["error"] is JsonValue ev && ev.TryGetValue(out string? e) ? e : null;
                    if (pending.Remove(id, out var p)) { if (p.Done is { } d) fire = () => d(ok, err); }
                    else if (latePending.Remove(id, out var lp)) fire = () => lp.Late(ok, err);
                }
            }
            else if (type == "error")
            {
                var msg = m["message"] is JsonValue mv && mv.TryGetValue(out string? x) ? x : "?";
                log = (log is null ? "" : log + "; ") + "Live Bridge: " + msg;
            }
            else
            {
                update = state.Apply(m);
            }
        }
        if (log is not null) Log?.Invoke(log);
        if (fire is not null) Safe(fire);
        if (update is not null && OnUpdate is { } u) Safe(() => u(update));
    }

    private void Safe(Action a)
    {
        try { a(); }
        catch (Exception e) { Log?.Invoke("Live Bridge: callback failed: " + e.Message); }
    }

    public void Dispose()
    {
        stopped = true;
        lock (gate)
        {
            timer?.Dispose();
            socket?.Dispose();
            socket = null;
        }
    }
}
