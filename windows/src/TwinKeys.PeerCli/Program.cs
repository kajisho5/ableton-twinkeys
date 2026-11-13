using System.Diagnostics;
using System.Net;
using TwinKeys.Core;

// A TwinKeys peer on the command line (TwinKeys.Core over real UDP, no MIDI port: notes are printed).
//
//   twinkeys-peer --code K7MQ2-WX9TP [--port 47801] [--name "CI Windows Peer"] [--connect 192.168.1.20[:47801]]
//                 [--script interop] [--timeout 90]
//
// Without --script it runs until stdin closes; type "cue up|down|left|right|space|enter|esc", "panic",
// "disconnect" or "quit". With --script interop it plays the backup for the macOS CI interop test
// (Tests/TwinKeysCoreTests/InteropPeerTests.swift): wait for a link, expect the cue ↓ (note 37) from the
// other side and answer it, then send the cue ↑ (note 36) and wait until it is confirmed. Exit code 0 = pass.

var opts = new Dictionary<string, string>();
for (int i = 0; i + 1 < args.Length; i += 2)
{
    if (!args[i].StartsWith("--")) { Console.Error.WriteLine($"Unexpected argument {args[i]}"); return 2; }
    opts[args[i][2..]] = args[i + 1];
}
if (!opts.TryGetValue("code", out var code) || PairingSecret.FromCode(code) is not PairingSecret secret)
{
    Console.Error.WriteLine("Usage: twinkeys-peer --code XXXXX-XXXXX [--port 47801] [--name NAME] [--connect HOST[:PORT]] [--script interop] [--timeout SECONDS]");
    return 2;
}
ushort port = opts.TryGetValue("port", out var ps) ? ushort.Parse(ps) : UdpTransport.FixedPort;
string name = opts.GetValueOrDefault("name") ?? "CI Windows Peer";
double timeout = opts.TryGetValue("timeout", out var ts) ? double.Parse(ts, System.Globalization.CultureInfo.InvariantCulture) : 90;
string script = opts.GetValueOrDefault("script") ?? "";

var clock = Stopwatch.StartNew();
void Say(string s) => Console.WriteLine($"[{clock.Elapsed.TotalSeconds,7:F3}] {s}");

var midi = new PrintingMidi(Say);
var settings = new AppSettings { SendKeys = true, ReceiveNotes = true };
using var net = new UdpTransport(port);
var conductor = new Conductor(settings.InstanceId, name, settings, midi, net,
    () => clock.Elapsed.TotalSeconds, () => (ulong)(clock.Elapsed.Ticks * 100));
conductor.Log = s => Say("log: " + s);
net.Log = s => Say("net: " + s);
net.OnDatagram = (b, known) => conductor.Receive(b, known);
net.OnNewRoute = conductor.NewRoute;
conductor.SetPairing(secret);
net.Start();
using var ticker = new Timer(_ => conductor.Tick(), null, 0, 50);
Say($"TwinKeys peer \"{name}\" ({GuidBytes.ToSwiftString(conductor.InstanceId)}) on UDP port {net.ListenPort}, key fingerprint {secret.Fingerprint}");

if (opts.TryGetValue("connect", out var target))
{
    if (ManualAddress.Parse(target) is not (string host, ushort p)) { Console.Error.WriteLine("Bad --connect address"); return 2; }
    var addr = IPAddress.TryParse(host, out var a) ? a : (await Dns.GetHostAddressesAsync(host))[0];
    var placeholder = PeerInfo.ManualPrefix + target;
    net.SetManual(placeholder, new IPEndPoint(addr, p));
    conductor.Connect(placeholder);
}

if (script == "interop")
{
    int exitCode = RunInterop();
    // Exit at once: on macOS, closing a socket another thread is blocked reading can wait (seen in CI).
    Console.Out.Flush();
    Environment.Exit(exitCode);
}

// Interactive.
string? line;
while ((line = Console.ReadLine()) is not null)
{
    var w = line.Trim().Split(' ', StringSplitOptions.RemoveEmptyEntries);
    if (w.Length == 0) continue;
    switch (w[0])
    {
        case "cue" when w.Length > 1 && KeyByName(w[1]) is ushort k: conductor.PressCue(k); break;
        case "panic": conductor.Panic(); break;
        case "disconnect": conductor.Disconnect(); break;
        case "quit": conductor.PrepareForQuit(); net.Flush(TimeSpan.FromSeconds(1)); return 0;
        default: Say("commands: cue up|down|left|right|space|enter|esc, panic, disconnect, quit"); break;
    }
    Say(Describe(conductor.Snapshot()));
}
conductor.PrepareForQuit();
net.Flush(TimeSpan.FromSeconds(1));
return 0;

int RunInterop()
{
    var deadline = clock.Elapsed.TotalSeconds + timeout;
    bool Wait(string what, Func<ConductorSnapshot, bool> ok)
    {
        while (clock.Elapsed.TotalSeconds < deadline)
        {
            if (ok(conductor.Snapshot())) { Say("PASS: " + what); return true; }
            Thread.Sleep(20);
        }
        Say("FAIL: " + what + " (timed out); state: " + Describe(conductor.Snapshot()));
        return false;
    }
    if (!Wait("linked", s => s.LinkedPeer is not null)) return 1;
    if (!Wait("received the cue ↓ (note 37) with its name and count 1",
            s => midi.Saw(0x90, 37, 127) && s.LastCue is { Delivery: CueStatus.DeliveryKind.Received, Label: "↓", Count: 1 })) return 1;
    Thread.Sleep(300);
    conductor.HandleKey(new KeyInput(KeyIds.Up, true));
    Thread.Sleep(30);
    conductor.HandleKey(new KeyInput(KeyIds.Up, false));
    if (!Wait("our cue ↑ (note 36) was confirmed by the other side",
            s => s.LastCue is { Delivery: CueStatus.DeliveryKind.Delivered, Note: 36 })) return 1;
    // The other side ends the link when it is done; staying until then keeps the answers flowing.
    var until = Math.Min(deadline, clock.Elapsed.TotalSeconds + 20);
    while (clock.Elapsed.TotalSeconds < until && conductor.Snapshot().Link is not LinkStateMachine.State.Idle) Thread.Sleep(50);
    Say(conductor.Snapshot().Link is LinkStateMachine.State.Idle ? "PASS: the other side said goodbye" : "note: the link is still up (no goodbye seen)");
    conductor.PrepareForQuit();
    net.Flush(TimeSpan.FromSeconds(1));
    return 0;
}

static ushort? KeyByName(string n) => n.ToLowerInvariant() switch
{
    "up" => KeyIds.Up, "down" => KeyIds.Down, "left" => KeyIds.Left, "right" => KeyIds.Right,
    "space" => KeyIds.Space, "enter" => KeyIds.Enter, "esc" => KeyIds.Escape, _ => null,
};

static string Describe(ConductorSnapshot s) =>
    $"link={s.Link} latency={s.LatencyMs?.ToString("F1") ?? "-"} ms lastCue={(s.LastCue is { } c ? $"{c.Label} #{c.Count} {c.Delivery}" : "-")}";

sealed class PrintingMidi(Action<string> say) : IMidiOutput
{
    private readonly List<byte[]> sent = [];
    public void Send(byte[] bytes)
    {
        lock (sent) sent.Add(bytes);
        say($"midi: {Convert.ToHexString(bytes)}");
    }
    public bool Saw(params byte[] m) { lock (sent) return sent.Any(b => b.SequenceEqual(m)); }
}
