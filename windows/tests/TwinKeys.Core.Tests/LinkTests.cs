namespace TwinKeys.Core.Tests;

using S = LinkStateMachine.State;
using A = LinkStateMachine.Action;

public class LinkTests
{
    [Fact]
    public void RetryDelayGrowsToFiveSeconds() =>
        Assert.Equal(new double[] { 1, 2, 4, 5, 5, 5 }, Enumerable.Range(1, 6).Select(LinkStateMachine.RetryDelay));

    [Fact]
    public void ConnectHandshakeAndHeartbeat()
    {
        var l = new LinkStateMachine();
        Assert.Equal([new A.SendHello("B")], l.Connect("B", 0));
        Assert.Equal(new S.Connecting("B", 1, 1), l.Current);
        l.ReceivedHelloAck("B", 0.01);
        Assert.Equal(new S.Connected("B"), l.Current);
        Assert.Equal([new A.SendHeartbeat("B")], l.Tick(0.1));
        Assert.Empty(l.Tick(0.5));
        Assert.Equal([new A.SendHeartbeat("B")], l.Tick(1.1));
        l.ReceivedHeartbeatAck("B", 0.002, 1.11);
        l.ReceivedHeartbeatAck("B", 0.010, 1.12);
        l.ReceivedHeartbeatAck("B", 0.003, 1.13);
        Assert.Equal(3, l.LatencyMs!.Value, 4);
    }

    [Fact]
    public void RetriesWithBackoffUntilAnswered()
    {
        var l = new LinkStateMachine();
        l.Connect("B", 0);
        Assert.Empty(l.Tick(0.9));
        Assert.Equal([new A.SendHello("B")], l.Tick(1.0));
        Assert.Empty(l.Tick(2.9));
        Assert.Equal([new A.SendHello("B")], l.Tick(3.0));
        Assert.Empty(l.Tick(6.9));
        Assert.Equal([new A.SendHello("B")], l.Tick(7.0));
        Assert.Equal([new A.SendHello("B")], l.Tick(12.0));
        l.ReceivedHelloAck("B", 12.1);
        Assert.True(l.IsConnected);
    }

    [Fact]
    public void LossAfterThreeSecondsSilenceThenReconnect()
    {
        var l = new LinkStateMachine();
        l.Connect("B", 0); l.ReceivedHelloAck("B", 0); l.Tick(0);
        l.ReceivedHeartbeat("B", 1, 1.0);
        Assert.Equal([new A.SendHeartbeat("B")], l.Tick(3.9));
        Assert.Equal([new A.DoSafety(SafetyTrigger.ConnectionLost, "B"), new A.Log("Lost connection to B; reconnecting"), new A.SendHello("B")], l.Tick(4.0));
        Assert.Equal(new S.Connecting("B", 1, 5), l.Current);
        Assert.Null(l.LatencyMs);
        Assert.Equal([new A.SendHelloAck("B"), new A.Log("Connected to B")], l.ReceivedHello("B", 6));
    }

    [Fact]
    public void ManualDisconnectIsNotUndoneByLateHellos()
    {
        var l = new LinkStateMachine();
        l.Connect("B", 0); l.ReceivedHelloAck("B", 0);
        Assert.Equal([new A.DoSafety(SafetyTrigger.ManualDisconnect, "B"), new A.SendBye("B"), new A.Log("Disconnected from B")], l.Disconnect());
        Assert.Equal([new A.SendBye("B"), new A.Log("Ignored hello from B after a manual disconnect")], l.ReceivedHello("B", 5));
        Assert.Equal(new S.Idle(), l.Current);
        Assert.Equal([new A.SendHelloAck("C"), new A.Log("Connected to C")], l.ReceivedHello("C", 6));
        l.Disconnect();
        l.Connect("B", 7); l.ReceivedHelloAck("B", 7.1);
        Assert.True(l.IsConnected);
    }

    [Fact]
    public void HelloFromThirdPartyIsIgnored()
    {
        var l = new LinkStateMachine();
        l.ReceivedHello("A", 0);
        Assert.Equal([new A.Log("Ignored hello from C while linked to A")], l.ReceivedHello("C", 1));
        Assert.Equal("A", l.Peer);
    }

    [Fact]
    public void SwitchingPeerLeavesOldOneCleanly()
    {
        var l = new LinkStateMachine();
        l.Connect("B", 0); l.ReceivedHelloAck("B", 0);
        Assert.Equal([new A.DoSafety(SafetyTrigger.ManualDisconnect, "B"), new A.SendBye("B"), new A.SendHello("C")], l.Connect("C", 1));
    }

    [Fact]
    public void ByeStopsWithoutReconnect()
    {
        var l = new LinkStateMachine();
        l.ReceivedHello("A", 0);
        Assert.Equal([new A.DoSafety(SafetyTrigger.PeerSaidBye, "A"), new A.Log("A disconnected")], l.ReceivedBye("A"));
        Assert.Empty(l.Tick(10));
    }

    [Fact]
    public void OnlyATimedOutLinkIsALoss()
    {
        var w = new MainLossWatch();
        w.Update(new S.Connected("m"), 0);
        w.Update(new S.Connecting("m", 1, 2), 1);
        Assert.False(w.IsLost(3.9));
        Assert.True(w.IsLost(4));
        w.Update(new S.Idle(), 11);
        Assert.False(w.IsLost(20));
    }
}
