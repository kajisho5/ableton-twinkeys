using System.Net;
using System.Net.Sockets;
using System.Text;

namespace TwinKeys.Core.Tests;

/// <summary>
/// The iPhone remote server (phase 3) over real TCP on 127.0.0.1, with a fake iPhone that speaks the
/// same protocol (RemoteSession as client). Ports of Tests/TwinKeysCoreTests/RemoteTests.swift and
/// RemoteApprovalTests.swift.
/// </summary>
public class RemoteServerTests
{
    static readonly PairingSecret Secret = new(Enumerable.Repeat((byte)9, 32).ToArray());

    /// <summary>A fake iPhone.</summary>
    sealed class Phone : IDisposable
    {
        public readonly TcpClient Tcp = new();
        public readonly RemoteSession Session;
        public readonly List<RemoteSession.Event> Events = [];
        public bool Closed;
        readonly Thread thread;
        public readonly byte[] Key = Curve25519.NewPrivateKey();

        public Phone(ushort port, PairingSecret secret, string id = "PHONE-1", string name = "Stage iPhone", byte[]? key = null)
        {
            if (key is not null) Key = key;
            Session = RemoteSession.Client(secret, Key);
            Tcp.Connect(IPAddress.Loopback, port);
            Tcp.GetStream().Write(Session.ClientHelloFrame(id, name));
            thread = new Thread(Loop) { IsBackground = true };
            thread.Start();
        }

        void Loop()
        {
            var buf = new byte[65536];
            try
            {
                while (true)
                {
                    int n = Tcp.GetStream().Read(buf);
                    if (n <= 0) break;
                    var ev = Session.Receive(buf.AsSpan(0, n));
                    lock (Events) Events.AddRange(ev);
                }
            }
            catch (Exception e) when (e is IOException or ObjectDisposedException or RemoteException) { }
            Closed = true;
        }

        public void Send(RemoteMessage m) => Tcp.GetStream().Write(Session.Seal(m));
        public List<RemoteMessage> Messages { get { lock (Events) return Events.OfType<RemoteSession.Event.Message>().Select(e => e.Value).ToList(); } }
        public T? Last<T>() where T : RemoteMessage => Messages.OfType<T>().LastOrDefault();
        /// <summary>Messages the C# reader does not decode (update, status: only the iPhone reads them), as JSON text.</summary>
        public List<string> Others { get { lock (Events) return Events.OfType<RemoteSession.Event.Unknown>().Select(e => e.Json).ToList(); } }
        public bool Got(string kind) => Others.Any(j => j.StartsWith("{\"" + kind + "\"", StringComparison.Ordinal));
        public void Dispose() => Tcp.Dispose();
    }

    sealed class Fixture : IDisposable
    {
        public readonly RemoteServer Server = new(GuidBytes.ToSwiftString(Guid.NewGuid()), "Stage PC");
        public readonly List<ApprovedDevice> Approved = [];
        public readonly List<(int Token, string Name, string Code, Action<bool> Answer)> Asked = [];
        public readonly List<int> Cancelled = [];
        public readonly List<LiveCommand> Ran = [];
        public readonly List<string> Logs = [];
        public int? Structure = 42;
        public ushort Port => Server.Port!.Value;

        public Fixture()
        {
            Server.IsApproved = h => { lock (Approved) return ApprovedDevice.IsApproved(h, Approved); };
            Server.OnApproved = h => { lock (Approved) Approved.Add(new ApprovedDevice(h.DeviceId, h.DeviceName, h.DevicePublicKey, DateTimeOffset.UtcNow)); };
            Server.AskApproval = (t, n, c, a) => { lock (Asked) Asked.Add((t, n, c, a)); };
            Server.CancelApproval = t => { lock (Cancelled) Cancelled.Add(t); };
            Server.RunCommand = (cmd, done, late) => { lock (Ran) Ran.Add(cmd); done(true, null, "delivered"); };
            Server.CurrentStructure = () => Structure;
            Server.CurrentSceneCount = () => 8;
            Server.PressCue = k => k == 336;
            Server.Log = s => { lock (Logs) Logs.Add(s); };
            Server.Snapshot = () =>
            {
                var s = new LiveState();
                s.Apply((System.Text.Json.Nodes.JsonObject)System.Text.Json.Nodes.JsonNode.Parse("""{"type":"song","tempo":120,"tracks":1,"scenes":1,"structure":42}""")!);
                return s;
            };
            Server.Status = () => new RemoteStatus("Stage PC", true, null, false, false, null, null, []);
            Server.Configure(Secret);
        }

        public void Dispose() => Server.Dispose();
    }

    static bool WaitFor(Func<bool> ok, double s = 5) => BridgeClientTests.WaitFor(ok, s);

    /// <summary>Connects, proves the key with a ping, and is allowed on this computer.</summary>
    static Phone Approve(Fixture f, string id = "PHONE-1")
    {
        var p = new Phone(f.Port, Secret, id);
        Assert.True(WaitFor(() => p.Session.IsReady));
        p.Send(new RemoteMessage.Ping(1));
        Assert.True(WaitFor(() => { lock (f.Asked) return f.Asked.Count > 0; }), string.Join("\n", f.Logs));
        var ask = f.Asked[^1];
        Assert.Equal("Stage iPhone", ask.Name);
        Assert.True(WaitFor(() => p.Last<RemoteMessage.WaitingForApproval>() is not null));
        // The iPhone shows the same 4 digits as the dialog.
        Assert.Equal(ask.Code, p.Last<RemoteMessage.WaitingForApproval>()!.Code);
        var serverHello = p.Events.OfType<RemoteSession.Event.ServerHello>().Single();
        Assert.Equal(ask.Code, serverHello.ConfirmCode);
        Assert.Equal("Stage PC", serverHello.Hello.ServerName);
        ask.Answer(true);
        Assert.True(WaitFor(() => p.Got("status")));
        return p;
    }

    [Fact]
    public void ApprovedPhoneGetsTheStateAndRunsCommands()
    {
        using var f = new Fixture();
        using var p = Approve(f);
        var welcome = p.Last<RemoteMessage.Welcome>()!;
        Assert.Equal("Stage PC", welcome.MacName);
        Assert.Equal(RemoteFeature.All, welcome.Features);
        Assert.StartsWith("{\"update\":{\"_0\":{\"full\"", p.Others.First());
        Assert.True(WaitFor(() => f.Server.ApprovedCount == 1));

        p.Send(new RemoteMessage.CommandAt(5, new LiveCommand.FireClip(0, 1), 42));
        Assert.True(WaitFor(() => p.Messages.OfType<RemoteMessage.Result>().Any(r => r.Id == 5)));
        Assert.Equal(new RemoteMessage.Result(5, true, null, "delivered"), p.Messages.OfType<RemoteMessage.Result>().Single(r => r.Id == 5));
        // An older layout than Live has now: refused before either computer's Live runs it.
        p.Send(new RemoteMessage.CommandAt(6, new LiveCommand.FireClip(0, 1), 41));
        Assert.True(WaitFor(() => p.Messages.OfType<RemoteMessage.Result>().Any(r => r.Id == 6)));
        Assert.Equal("structure_changed", p.Messages.OfType<RemoteMessage.Result>().Single(r => r.Id == 6).Error);
        // GO: launch the scene and select the next one.
        p.Send(new RemoteMessage.Go(7, 2, 42));
        Assert.True(WaitFor(() => { lock (f.Ran) return f.Ran.Contains(new LiveCommand.SelectScene(3)); }));
        lock (f.Ran) Assert.Equal([new LiveCommand.FireClip(0, 1), new LiveCommand.FireScene(2), new LiveCommand.SelectScene(3)], f.Ran);
        // The show lock (standard: tempo and mixer).
        p.Send(new RemoteMessage.Lock(true));
        p.Send(new RemoteMessage.Command(8, new LiveCommand.SetTempo(130)));
        p.Send(new RemoteMessage.Command(9, new LiveCommand.FireScene(1)));
        Assert.True(WaitFor(() => p.Messages.OfType<RemoteMessage.Result>().Any(r => r.Id == 9)));
        Assert.Equal("locked", p.Messages.OfType<RemoteMessage.Result>().Single(r => r.Id == 8).Error);
        Assert.True(p.Messages.OfType<RemoteMessage.Result>().Single(r => r.Id == 9).Ok);
        // Cue buttons and pings.
        p.Send(new RemoteMessage.Cue(10, 336));
        p.Send(new RemoteMessage.Cue(11, 1));
        p.Send(new RemoteMessage.Ping(77, new RemoteWatchState(true, true, true)));
        Assert.True(WaitFor(() => p.Messages.OfType<RemoteMessage.Pong>().Any(x => x.Time == 77)));
        Assert.True(p.Messages.OfType<RemoteMessage.Result>().Single(r => r.Id == 10).Ok);
        Assert.Equal("not a cue key", p.Messages.OfType<RemoteMessage.Result>().Single(r => r.Id == 11).Error);
        // A message kind this version does not know is skipped; the connection stays.
        p.Tcp.GetStream().Write(p.Session.SealJson(Encoding.UTF8.GetBytes("""{"fromTheFuture":{"x":1}}""")));
        p.Send(new RemoteMessage.Ping(78));
        Assert.True(WaitFor(() => p.Messages.OfType<RemoteMessage.Pong>().Any(x => x.Time == 78)));
        Assert.False(p.Closed);
        // Live changes reach the phone.
        f.Server.Broadcast(new LiveUpdate.Song(new LiveSong { Tempo = 99, Structure = 43 }));
        Assert.True(WaitFor(() => p.Others.Any(j => j.Contains("\"song\":{\"_0\":{\"tempo\":99", StringComparison.Ordinal))));

        // Next time the same device (id and key) is let in without asking.
        var key = p.Key;
        p.Dispose();
        using var again = new Phone(f.Port, Secret, key: key);
        Assert.True(WaitFor(() => again.Session.IsReady));
        again.Send(new RemoteMessage.Ping(2));
        Assert.True(WaitFor(() => again.Last<RemoteMessage.Welcome>() is not null));
        lock (f.Asked) Assert.Single(f.Asked);
        // Another key with the same id is not that device.
        using var impostor = new Phone(f.Port, Secret);
        Assert.True(WaitFor(() => impostor.Session.IsReady));
        impostor.Send(new RemoteMessage.Ping(3));
        Assert.True(WaitFor(() => impostor.Last<RemoteMessage.WaitingForApproval>() is not null));
        Assert.Null(impostor.Last<RemoteMessage.Welcome>());
    }

    [Fact]
    public void RefusedDeviceCoolsDownAndOnlyOneQuestionAtATime()
    {
        using var f = new Fixture();
        using var a = new Phone(f.Port, Secret, "A");
        Assert.True(WaitFor(() => a.Session.IsReady));
        a.Send(new RemoteMessage.Ping(1));
        Assert.True(WaitFor(() => { lock (f.Asked) return f.Asked.Count == 1; }));
        // A second device while the first is being asked: refused without a second dialog.
        using var b = new Phone(f.Port, Secret, "B");
        Assert.True(WaitFor(() => b.Session.IsReady));
        b.Send(new RemoteMessage.Ping(1));
        Assert.True(WaitFor(() => b.Closed));
        lock (f.Asked) Assert.Single(f.Asked);
        f.Asked[0].Answer(false);
        Assert.True(WaitFor(() => a.Last<RemoteMessage.Denied>() is not null && a.Closed));
        // Refused a moment ago: no new dialog.
        using var a2 = new Phone(f.Port, Secret, "A");
        Assert.True(WaitFor(() => a2.Session.IsReady));
        a2.Send(new RemoteMessage.Ping(1));
        Assert.True(WaitFor(() => a2.Closed));
        lock (f.Asked) Assert.Single(f.Asked);
    }

    [Fact]
    public void WrongPairingCodeIsClosed()
    {
        using var f = new Fixture();
        using var p = new Phone(f.Port, new PairingSecret(Enumerable.Repeat((byte)1, 32).ToArray()));
        Assert.True(WaitFor(() => p.Closed));
        Assert.False(p.Session.IsReady);
        lock (f.Asked) Assert.Empty(f.Asked);
    }

    [Fact]
    public void ApprovalGateRules()
    {
        var g = new RemoteApprovalGate();
        var a = Assert.IsType<RemoteApprovalGate.Decision.Ask>(g.Request("A", 0));
        Assert.IsType<RemoteApprovalGate.Decision.Busy>(g.Request("B", 1));
        Assert.True(g.Finish(a.Token, false, 2));
        Assert.False(g.Finish(a.Token, true, 2));   // an old answer is ignored
        Assert.IsType<RemoteApprovalGate.Decision.CoolingDown>(g.Request("A", 30));
        var b = Assert.IsType<RemoteApprovalGate.Decision.Ask>(g.Request("A", 63));
        Assert.True(g.IsExpired(b.Token, 63 + RemoteApprovalGate.Timeout));
        // A question past its time limit does not block the next device.
        Assert.IsType<RemoteApprovalGate.Decision.Ask>(g.Request("C", 63 + RemoteApprovalGate.Timeout + 1));
    }

    [Fact]
    public void DeviceNamesAreCleaned()
    {
        Assert.Equal("Lighting iPhone", RemoteClientHello.SanitizedName(" Lighting‮ iPhone\n "));
        Assert.Equal("iPhone", RemoteClientHello.SanitizedName("​\u0007"));
        Assert.Equal(64, RemoteClientHello.SanitizedName(new string('x', 100)).Length);
        Assert.Equal("👨‍👩‍👧", RemoteClientHello.SanitizedName("👨‍👩‍👧"));   // the zero-width joiner stays
    }

    [Fact]
    public void LockScopeRules()
    {
        Assert.True(LockScope.Standard.Blocks(new LiveCommand.SetTempo(120)));
        Assert.True(LockScope.Standard.Blocks(new LiveCommand.SetSend(0, 0, 0.2)));
        Assert.False(LockScope.Standard.Blocks(new LiveCommand.FireClip(0, 0)));
        var all = LockScope.Tempo | LockScope.Mixer | LockScope.Launches | LockScope.Stops | LockScope.Cues;
        Assert.True(all.Blocks(new LiveCommand.Stop()));
        Assert.False(all.Blocks(new LiveCommand.SelectScene(3)));
    }
}
