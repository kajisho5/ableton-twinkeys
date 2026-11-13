using System.Diagnostics;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json.Nodes;

namespace TwinKeys.Core.Tests;

/// <summary>
/// The Live Bridge client against a fake TwinKeysBridge on 127.0.0.1 (other ports than Live's, so a
/// running Live does not disturb the test), and the installer on temporary folders.
/// </summary>
public class BridgeClientTests
{
    /// <summary>Stands in for the Remote Script: listens for commands, answers to the client's state port.</summary>
    sealed class FakeBridge : IDisposable
    {
        public readonly Socket Socket = new(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        public readonly List<JsonObject> Received = [];
        public Func<JsonObject, string?> Answer = c => $$"""{"type":"ack","id":{{c["id"]}},"ok":true}""";
        readonly ushort statePort;
        readonly Thread thread;
        volatile bool stopped;

        public FakeBridge(ushort commandPort, ushort statePort)
        {
            this.statePort = statePort;
            Socket.Bind(new IPEndPoint(IPAddress.Loopback, commandPort));
            Socket.ReceiveTimeout = 200;
            thread = new Thread(Loop) { IsBackground = true };
            thread.Start();
        }

        void Loop()
        {
            var buf = new byte[65535];
            while (!stopped)
            {
                int n;
                try { n = Socket.Receive(buf); }
                catch (SocketException) { continue; }
                catch (ObjectDisposedException) { return; }
                var c = (JsonObject)JsonNode.Parse(buf.AsSpan(0, n))!;
                lock (Received) Received.Add(c);
                if (Answer(c) is string reply) Send(reply);
            }
        }

        public void Send(string json) => Socket.SendTo(Encoding.UTF8.GetBytes(json), new IPEndPoint(IPAddress.Loopback, statePort));

        public List<JsonObject> Commands(string cmd) { lock (Received) return Received.Where(c => (string?)c["cmd"] == cmd).ToList(); }

        public void Dispose() { stopped = true; Socket.Dispose(); }
    }

    internal static ushort FreePort()
    {
        using var s = new Socket(AddressFamily.InterNetwork, SocketType.Dgram, ProtocolType.Udp);
        s.Bind(new IPEndPoint(IPAddress.Loopback, 0));
        return (ushort)((IPEndPoint)s.LocalEndPoint!).Port;
    }

    internal static bool WaitFor(Func<bool> ok, double seconds = 5)
    {
        var sw = Stopwatch.StartNew();
        while (sw.Elapsed.TotalSeconds < seconds) { if (ok()) return true; Thread.Sleep(10); }
        return ok();
    }

    [Fact]
    public void SaysHelloRunsCommandsAndKeepsTheState()
    {
        ushort cmdPort = FreePort(), statePort = FreePort();
        using var bridge = new FakeBridge(cmdPort, statePort);
        bridge.Answer = c =>
        {
            if ((string?)c["cmd"] == "hello")
            {
                bridge.Send($$"""{"type":"ack","id":{{c["id"]}},"ok":true}""");
                bridge.Send("""{"type":"song","tempo":128.0,"playing":false,"beat":"1.1.1","tracks":2,"scenes":2,"structure":42,"bridge_version":3}""");
                bridge.Send("""{"type":"tracks","start":0,"items":[{"index":0,"name":"Music"},{"index":1,"name":"SE"}]}""");
                return """{"type":"scenes","start":0,"items":[{"index":0,"name":"1 Intro"},{"index":1,"name":"2 Main"}]}""";
            }
            return (string?)c["cmd"] == "fire_clip"
                ? $$"""{"type":"ack","id":{{c["id"]}},"ok":false,"error":"track 9 out of range (0..1)"}"""
                : $$"""{"type":"ack","id":{{c["id"]}},"ok":true}""";
        };
        var updates = new List<LiveUpdate>();
        using var client = new BridgeClient(cmdPort, statePort) { OnUpdate = u => { lock (updates) updates.Add(u); } };
        Assert.False(client.IsConnected);
        client.Start();
        Assert.True(WaitFor(() => client.IsConnected && client.Snapshot().Scenes.Count == 2));
        Assert.Single(bridge.Commands("hello"));   // no second hello while Live keeps talking
        var live = client.Snapshot();
        Assert.Equal(42, client.Structure);
        Assert.Equal(3, live.Song.BridgeVersion);
        Assert.Equal(new SetSummary(["Music", "SE"], ["1 Intro", "2 Main"]), SetSummary.Of(live));
        lock (updates) Assert.Contains(updates, u => u is LiveUpdate.Tracks);

        // A command from the main (no structure check) and one from the iPhone (with it).
        var results = new List<(bool, string?)>();
        var done = new ManualResetEventSlim();
        client.Run(new LiveCommand.FireScene(1), done: (ok, err) => { lock (results) results.Add((ok, err)); });
        client.Run(new LiveCommand.FireClip(9, 0), checkStructure: true, done: (ok, err) => { lock (results) results.Add((ok, err)); done.Set(); });
        Assert.True(done.Wait(3000, TestContext.Current.CancellationToken));
        Assert.True(WaitFor(() => { lock (results) return results.Count == 2; }));
        lock (results)
        {
            Assert.Contains((true, (string?)null), results);
            Assert.Contains((false, (string?)"track 9 out of range (0..1)"), results);
        }
        var fire = bridge.Commands("fire_scene").Single();
        Assert.Equal(1, (int)fire["scene"]!);
        Assert.False(fire.ContainsKey("structure"));
        Assert.Equal(42, (int)bridge.Commands("fire_clip").Single()["structure"]!);

        // An invalid command never leaves this computer.
        (bool, string?)? invalid = null;
        client.Run(new LiveCommand.SetTempo(5), done: (ok, err) => invalid = (ok, err));
        Assert.Equal((false, "invalid"), invalid);
    }

    [Fact]
    public void NoAnswerAfterOneSecondThenALateAnswer()
    {
        ushort cmdPort = FreePort(), statePort = FreePort();
        using var bridge = new FakeBridge(cmdPort, statePort);
        bridge.Answer = c => (string?)c["cmd"] == "hello" ? $$"""{"type":"ack","id":{{c["id"]}},"ok":true}""" : null;
        using var client = new BridgeClient(cmdPort, statePort);
        client.Start();
        Assert.True(WaitFor(() => client.IsConnected));
        string? first = null;
        (bool, string?)? late = null;
        var sw = Stopwatch.StartNew();
        client.Run(new LiveCommand.Play(), done: (ok, err) => first = $"{ok}/{err}@{sw.Elapsed.TotalSeconds:0.0}", late: (ok, err) => late = (ok, err));
        Assert.True(WaitFor(() => first is not null, 3));
        Assert.StartsWith("False/no_answer@1", first);
        // Live was slow: its answer still reaches "late".
        var id = (int)bridge.Commands("play").Single()["id"]!;
        bridge.Send($$"""{"type":"ack","id":{{id}},"ok":true}""");
        Assert.True(WaitFor(() => late is not null));
        Assert.Equal((true, (string?)null), late);
    }

    [Fact]
    public void LiveStartingLaterIsFoundAndBadDatagramsAreIgnored()
    {
        ushort cmdPort = FreePort(), statePort = FreePort();
        using var client = new BridgeClient(cmdPort, statePort);
        client.Start();
        Thread.Sleep(400);   // hellos go to a port nobody listens on (on Windows: ICMP "port unreachable")
        using var bridge = new FakeBridge(cmdPort, statePort);
        bridge.Answer = c => (string?)c["cmd"] == "hello" ? $$"""{"type":"ack","id":{{c["id"]}},"ok":true}""" : null;
        bridge.Send("not json");
        bridge.Send("[1,2,3]");
        Assert.True(WaitFor(() => client.IsConnected, 5));
    }

    [Fact]
    public void InstallerCopiesTheScriptAndUpdatesOnlyAnOlderCopy()
    {
        var root = Path.Combine(Path.GetTempPath(), "twinkeys-installer-" + Guid.NewGuid().ToString("N"));
        try
        {
            var bundled = Path.Combine(root, "app", BridgeInstaller.FolderName);
            Directory.CreateDirectory(bundled);
            File.WriteAllText(Path.Combine(bundled, "__init__.py"), "# init\n");
            File.WriteAllText(Path.Combine(bundled, "constants.py"), "# c\r\nBRIDGE_VERSION = 3\r\nCOMMAND_PORT = 47811\r\n");
            File.WriteAllText(Path.Combine(bundled, "notes.txt"), "not copied");
            var lib = BridgeInstaller.DefaultUserLibrary(Path.Combine(root, "Documents"));
            Assert.Equal(Path.Combine(root, "Documents", "Ableton", "User Library"), lib);
            var inst = new BridgeInstaller(bundled, lib);
            Assert.False(inst.UserLibraryExists);
            Assert.False(inst.IsInstalled);
            Assert.False(inst.UpdateIfOutdated());   // nothing installed: nothing is put there unasked
            Assert.False(inst.IsInstalled);
            Assert.Null(inst.Install());
            Assert.True(inst.IsInstalled);
            Assert.Equal(Path.Combine(lib, "Remote Scripts", "TwinKeysBridge"), inst.Installed);
            Assert.Equal(3, inst.InstalledVersion);
            Assert.False(File.Exists(Path.Combine(inst.Installed, "notes.txt")));
            Assert.False(inst.UpdateIfOutdated());   // same version
            File.WriteAllText(Path.Combine(inst.Installed, "constants.py"), "BRIDGE_VERSION = 2\n");
            File.WriteAllText(Path.Combine(inst.Installed, "old.py"), "");
            Assert.True(inst.UpdateIfOutdated());
            Assert.Equal(3, inst.InstalledVersion);
            Assert.False(File.Exists(Path.Combine(inst.Installed, "old.py")));
            Assert.Equal(0, BridgeInstaller.VersionOf(Path.Combine(root, "missing")));
            Assert.NotNull(new BridgeInstaller(Path.Combine(root, "none"), lib).Install());
        }
        finally
        {
            try { Directory.Delete(root, true); } catch (IOException) { }
        }
    }

    /// <summary>The Bridge files in this repository have a version the app can read.</summary>
    [Fact]
    public void RepositoryBridgeHasAVersion()
    {
        Assert.True(BridgeInstaller.VersionOf(RealBridgeTests.BridgeSource()) >= 3);
    }
}
