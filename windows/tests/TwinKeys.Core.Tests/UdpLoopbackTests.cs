using System.Diagnostics;
using System.Net;

namespace TwinKeys.Core.Tests;

/// <summary>Two Conductors over real UDP sockets on 127.0.0.1 (the transport the Windows app uses).</summary>
public class UdpLoopbackTests
{
    sealed class Node : IDisposable
    {
        public readonly UdpTransport Net;
        public readonly Conductor Conductor;
        public readonly FakeMidi Midi = new();
        readonly Timer timer;

        public Node(string name, ushort port, AppSettings s, PairingSecret secret)
        {
            var clock = Stopwatch.StartNew();
            Net = new UdpTransport(port, IPAddress.Loopback);
            Conductor = new Conductor(s.InstanceId, name, s, Midi, Net, () => clock.Elapsed.TotalSeconds, () => (ulong)clock.Elapsed.Ticks * 100);
            Net.OnDatagram = (b, known) => Conductor.Receive(b, known);
            Net.OnNewRoute = Conductor.NewRoute;
            Conductor.SetPairing(secret);
            Net.Start();
            timer = new Timer(_ => Conductor.Tick(), null, 0, 50);
        }

        public void Dispose() { timer.Dispose(); Net.Dispose(); }
    }

    static bool WaitFor(Func<bool> ok, double seconds = 10)
    {
        var until = DateTime.UtcNow.AddSeconds(seconds);
        while (DateTime.UtcNow < until) { if (ok()) return true; Thread.Sleep(20); }
        return ok();
    }

    [Fact]
    public void CueTravelsBothWaysOverLocalhostByIpAddress()
    {
        var secret = new PairingSecret(Enumerable.Repeat((byte)3, 32).ToArray());
        ushort pa = (ushort)Random.Shared.Next(40000, 45000), pb = (ushort)(pa + 1);
        using var a = new Node("Stage PC", pa, new AppSettings { ReceiveNotes = false }, secret);
        using var b = new Node("Backup PC", pb, new AppSettings { SendKeys = false }, secret);
        // Connect by IP address: a placeholder ID until the first answer names the real peer.
        a.Net.SetManual("manual:127.0.0.1", new IPEndPoint(IPAddress.Loopback, pb));
        a.Conductor.Connect("manual:127.0.0.1");
        var bId = GuidBytes.ToSwiftString(b.Conductor.InstanceId);
        Assert.True(WaitFor(() => a.Conductor.Snapshot().LinkedPeer == bId), "A did not link");
        Assert.True(WaitFor(() => b.Conductor.Snapshot().LinkedPeer is not null), "B did not link");
        Assert.True(WaitFor(() => a.Conductor.Snapshot().LatencyMs is not null), "no heartbeat answer");

        a.Conductor.HandleKey(new KeyInput(KeyIds.Down, true));
        a.Conductor.HandleKey(new KeyInput(KeyIds.Down, false));
        Assert.True(WaitFor(() => b.Midi.Contains(0x90, 37, 127) && b.Midi.Contains(0x80, 37, 0)));
        Assert.True(WaitFor(() => a.Conductor.Snapshot().LastCue?.Delivery == CueStatus.DeliveryKind.Delivered));
        Assert.Equal("↓", b.Conductor.Snapshot().LastCue?.Label);
        Assert.Equal(1, b.Conductor.Snapshot().LastCue?.Count);

        a.Conductor.Disconnect();
        Assert.True(WaitFor(() => b.Conductor.Snapshot().Link is LinkStateMachine.State.Idle));
    }
}
