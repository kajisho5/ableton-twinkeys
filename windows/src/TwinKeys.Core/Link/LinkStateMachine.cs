namespace TwinKeys.Core;

/// <summary>
/// Connection state for one peer, with heartbeat-based loss detection and automatic
/// reconnection (port of LinkStateMachine.swift). Pure logic: time comes in from the caller,
/// and the caller performs the returned actions.
/// </summary>
public sealed class LinkStateMachine
{
    public abstract record State
    {
        private State() { }
        public sealed record Idle : State;
        /// <summary><paramref name="Attempt"/> starts at 1. <paramref name="NextRetryAt"/> is when the next hello is due.</summary>
        public sealed record Connecting(string Peer, int Attempt, double NextRetryAt) : State;
        public sealed record Connected(string Peer) : State;
    }

    public abstract record Action
    {
        private Action() { }
        public sealed record SendHello(string Peer) : Action;
        public sealed record SendHelloAck(string Peer) : Action;
        public sealed record SendHeartbeat(string Peer) : Action;
        public sealed record SendHeartbeatAck(string Peer, ulong TimestampNanos) : Action;
        public sealed record SendBye(string Peer) : Action;
        /// <summary>Turn notes off as <see cref="Safety.Plan"/> says for this trigger.</summary>
        public sealed record DoSafety(SafetyTrigger Trigger, string Peer) : Action;
        public sealed record Log(string Message) : Action;
    }

    public const double HeartbeatInterval = 1.0;
    public const double Timeout = 3.0;
    public const double MinRetry = 1.0;
    public const double MaxRetry = 5.0;
    public const double DeclineMemory = 30.0;

    public State Current { get; private set; } = new State.Idle();
    public double LastHeard { get; private set; }
    private double lastHeartbeatSent = double.NegativeInfinity;
    private readonly List<double> rtts = [];
    /// <summary>Peers the person disconnected from; their hellos are answered with Bye (value: when their last hello came).</summary>
    private readonly Dictionary<string, double> declined = [];
    public IReadOnlyDictionary<string, double> Declined => declined;

    public string? Peer => Current switch
    {
        State.Connecting c => c.Peer,
        State.Connected c => c.Peer,
        _ => null,
    };

    public bool IsConnected => Current is State.Connected;

    /// <summary>Median of the last 5 heartbeat round trips, in milliseconds.</summary>
    public double? LatencyMs
    {
        get
        {
            if (rtts.Count == 0) return null;
            var s = rtts.Order().ToList();
            return s[s.Count / 2] * 1000;
        }
    }

    /// <summary>Retry delay after <paramref name="attempt"/> attempts: 1, 2, 4, 5, 5, ... seconds.</summary>
    public static double RetryDelay(int attempt) =>
        Math.Min(MaxRetry, MinRetry * (1 << Math.Min(Math.Max(attempt - 1, 0), 8)));

    /// <summary>A placeholder peer (for example "manual:192.168.1.20") turned out to be <paramref name="real"/>.</summary>
    public void RenamePeer(string old, string real)
    {
        Current = Current switch
        {
            State.Connecting c when c.Peer == old => c with { Peer = real },
            State.Connected c when c.Peer == old => new State.Connected(real),
            _ => Current,
        };
    }

    /// <summary>User pressed Connect.</summary>
    public List<Action> Connect(string peer, double now)
    {
        var actions = new List<Action>();
        if (Peer is string old && old != peer)
        {
            actions.AddRange(Leave(old));
            declined[old] = now;
        }
        declined.Remove(peer);
        Current = new State.Connecting(peer, 1, now + RetryDelay(1));
        rtts.Clear();
        actions.Add(new Action.SendHello(peer));
        return actions;
    }

    /// <summary>User pressed Disconnect.</summary>
    public List<Action> Disconnect(double? now = null)
    {
        if (Peer is not string p) return [];
        Current = new State.Idle();
        rtts.Clear();
        declined[p] = now ?? LastHeard;
        return [.. Leave(p), new Action.Log($"Disconnected from {p}")];
    }

    private static List<Action> Leave(string p) => [new Action.DoSafety(SafetyTrigger.ManualDisconnect, p), new Action.SendBye(p)];

    /// <summary>A hello arrived (the peer connects to us, or reconnects after a drop).</summary>
    public List<Action> ReceivedHello(string peer, double now)
    {
        if (declined.TryGetValue(peer, out var t) && now - t >= DeclineMemory) declined.Remove(peer);
        if (declined.ContainsKey(peer) && peer != Peer)
        {
            declined[peer] = now;
            return [new Action.SendBye(peer), new Action.Log($"Ignored hello from {peer} after a manual disconnect")];
        }
        switch (Current)
        {
            case State.Connected c when c.Peer == peer:
                LastHeard = now;
                return [new Action.SendHelloAck(peer)];
            case State.Connected c when c.Peer != peer:
                return [new Action.Log($"Ignored hello from {peer} while linked to {c.Peer}")];
            case State.Connecting c when c.Peer != peer:
                return [new Action.Log($"Ignored hello from {peer} while linked to {c.Peer}")];
        }
        LastHeard = now;
        Current = new State.Connected(peer);
        rtts.Clear();
        return [new Action.SendHelloAck(peer), new Action.Log($"Connected to {peer}")];
    }

    public List<Action> ReceivedHelloAck(string peer, double now)
    {
        if (Current is not State.Connecting c || c.Peer != peer)
        {
            if (Peer == peer) LastHeard = now;
            return [];
        }
        LastHeard = now;
        Current = new State.Connected(peer);
        return [new Action.Log($"Connected to {peer}")];
    }

    /// <summary>The peer said goodbye: stop and do not reconnect.</summary>
    public List<Action> ReceivedBye(string peer)
    {
        if (Peer != peer) return [];
        Current = new State.Idle();
        rtts.Clear();
        return [new Action.DoSafety(SafetyTrigger.PeerSaidBye, peer), new Action.Log($"{peer} disconnected")];
    }

    public List<Action> ReceivedHeartbeat(string peer, ulong timestampNanos, double now)
    {
        if (Peer != peer) return [];
        // The peer still thinks the link is up, but we timed out: a hello re-establishes it on both sides.
        if (Current is State.Connecting) return [new Action.SendHello(peer)];
        if (IsConnected) LastHeard = now;
        return [new Action.SendHeartbeatAck(peer, timestampNanos)];
    }

    /// <summary><paramref name="rtt"/> in seconds, measured by the caller from the echoed timestamp.</summary>
    public void ReceivedHeartbeatAck(string peer, double rtt, double now)
    {
        if (Peer != peer || !IsConnected) return;
        LastHeard = now;
        rtts.Add(rtt);
        if (rtts.Count > 5) rtts.RemoveRange(0, rtts.Count - 5);
    }

    /// <summary>Any other packet from the peer also proves it is alive.</summary>
    public void ReceivedOther(string peer, double now)
    {
        if (Peer == peer && IsConnected) LastHeard = now;
    }

    /// <summary>Call regularly (e.g. every 100-250 ms).</summary>
    public List<Action> Tick(double now)
    {
        switch (Current)
        {
            case State.Connected c:
                if (now - LastHeard >= Timeout)
                {
                    Current = new State.Connecting(c.Peer, 1, now + RetryDelay(1));
                    rtts.Clear();
                    return [new Action.DoSafety(SafetyTrigger.ConnectionLost, c.Peer), new Action.Log($"Lost connection to {c.Peer}; reconnecting"), new Action.SendHello(c.Peer)];
                }
                if (now - lastHeartbeatSent >= HeartbeatInterval)
                {
                    lastHeartbeatSent = now;
                    return [new Action.SendHeartbeat(c.Peer)];
                }
                return [];
            case State.Connecting c:
                if (now < c.NextRetryAt) return [];
                int a = c.Attempt + 1;
                Current = new State.Connecting(c.Peer, a, now + RetryDelay(a));
                return [new Action.SendHello(c.Peer)];
            default:
                return [];
        }
    }
}

/// <summary>
/// When the main computer was lost, for the "main stopped" banner (port of MainLossWatch). Only an
/// unexpected loss counts: the link timed out and is being retried.
/// </summary>
public sealed class MainLossWatch
{
    public double? LostSince { get; private set; }
    private bool wasConnected;

    public void Update(LinkStateMachine.State link, double now)
    {
        switch (link)
        {
            case LinkStateMachine.State.Connected: wasConnected = true; LostSince = null; break;
            case LinkStateMachine.State.Idle: wasConnected = false; LostSince = null; break;
            case LinkStateMachine.State.Connecting:
                if (wasConnected && LostSince is null) LostSince = now;
                break;
        }
    }

    public bool IsLost(double now, double after = 3) => LostSince is double t && now - t >= after;
}
