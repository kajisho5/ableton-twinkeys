using System.Globalization;
using System.Text;

namespace TwinKeys.Core;

/// <summary>Where MIDI goes on this computer (the loopback port "TwinKeys").</summary>
public interface IMidiOutput
{
    /// <summary>One complete MIDI 1.0 channel message (3 bytes).</summary>
    void Send(byte[] bytes);
}

/// <summary>Sends datagrams to a peer by instance ID.</summary>
public interface IPacketSink
{
    void Send(byte[] bytes, string peer);
    /// <summary>Forget any cached route to the peer so the next send looks it up again.</summary>
    void ResetRoute(string peer);
}

/// <summary>What the "last cue" panel shows.</summary>
public sealed record CueStatus(string Label, string Memo, byte Note, int Count, CueStatus.DeliveryKind Delivery, double? DeliveredMs, string? PeerName)
{
    public enum DeliveryKind
    {
        /// <summary>Sent, waiting for the other computer to answer.</summary>
        Waiting,
        /// <summary>The other computer answered (round trip in <see cref="DeliveredMs"/>).</summary>
        Delivered,
        /// <summary>No answer within <see cref="Conductor.CueAnswerTimeout"/>.</summary>
        Missing,
        /// <summary>The other computer runs a version without the delivery check.</summary>
        Unconfirmed,
        /// <summary>Not connected when the cue was sent.</summary>
        NotConnected,
        /// <summary>This computer received the cue (backup side).</summary>
        Received,
    }
}

public sealed record ConductorSnapshot(
    LinkStateMachine.State Link,
    double? LatencyMs,
    IReadOnlyDictionary<string, string> PeerNames,
    bool IsPaired,
    IReadOnlySet<string> MismatchedPeers,
    IReadOnlyList<byte> HeldNotes,
    bool SendKeys,
    bool ReceiveNotes,
    bool KeyCapture,
    CueStatus? LastCue,
    bool ClaimsMain)
{
    public string? LinkedPeer => Link switch
    {
        LinkStateMachine.State.Connected c => c.Peer,
        _ => null,
    };
}

/// <summary>
/// Connects key input, the local MIDI port and the network link. Port of
/// Sources/TwinKeysCore/Conductor.swift (phase 1: cues, notes, the delivery check, the link,
/// the main/backup role). Thread-safe: key events, network packets and timer ticks may arrive
/// on different threads; work is done on the calling thread under one lock.
/// Live commands, set check, iPhone and console packets (phases 2-3, and the Mac-only console)
/// are accepted as signs of life and otherwise ignored.
/// </summary>
public sealed class Conductor
{
    private readonly object gate = new();
    public Guid InstanceId { get; }
    public string DisplayName { get; }
    private readonly uint session;
    private uint seq;

    private readonly PerformanceEngine engine;
    private readonly LinkStateMachine link = new();
    private readonly NoteGuard keysGuard;
    private readonly NoteGuard peerGuard;
    private Dictionary<string, SequenceFilter> filters = [];
    private Dictionary<string, string> peerNames = [];
    private bool sendKeys;
    private bool receiveNotes;
    private bool keyCapture;

    /// <summary>Each note, All Notes Off and Bye is sent this many times with the same sequence number.</summary>
    public int Redundancy { get; }

    private readonly IMidiOutput? midi;
    private readonly IPacketSink net;
    private readonly Func<double> clock;
    private readonly Func<ulong> nanos;
    public Action<string> Log { get; set; } = _ => { };
    /// <summary>True if the peer is currently advertised on the network. Only used to label visible peers whose code does not match.</summary>
    public Func<string, bool> IsKnownPeer { get; set; } = _ => true;
    private SecureChannel? channel;
    private Dictionary<string, byte[]> peerNonces = [];
    private Dictionary<string, double> mismatchAt = [];
    private bool quitting;
    private readonly Dictionary<string, double> ignoredLogAt = [];

    /// <summary>Keys held longer than this are no longer protected from auto note-off.</summary>
    public const double MaxProtectedHold = 600.0;
    /// <summary>A cue is sent again every this many seconds while no answer comes…</summary>
    public const double CueResendInterval = 0.1;
    /// <summary>…and counts as missing after this long.</summary>
    public const double CueAnswerTimeout = 0.3;

    private bool blockCueKeys;
    /// <summary>Key codes whose key-down was swallowed: their key-up is swallowed too.</summary>
    private readonly HashSet<ushort> swallowed = [];

    private sealed class SentCue
    {
        public required CueKey Cue;
        public int Count;
        public uint Seq;
        public double SentAt;
        public int Resends;
        public CueStatus.DeliveryKind Delivery;
        public double? Ms;
        public bool KeyUp;
    }

    private List<SentCue> sentCues = [];
    private CueStatus? receivedCue;
    private bool lastCueWasReceived;
    private byte linkEpoch = (byte)Random.Shared.Next(256);
    private (uint Session, byte Epoch)? peerEpoch;
    private (string Peer, uint Session, uint Seq, byte[] Nonce, string Name)? pendingHello;
    private int cueCount;
    private bool peerAnswersCues;
    private bool wasConnected;
    private readonly Dictionary<NoteGuard.Key, (string Label, string Memo)> peerCueNames = [];
    private readonly record struct PlayedCue(uint Session, uint Seq);
    private readonly List<PlayedCue> playedCueSeqs = [];
    private int heartbeatsSinceNames;
    private bool countedSinceReset;
    private readonly Dictionary<PlayedCue, int> peerCounts = [];
    private PlayedCue? lastPlayed;

    // Main / backup role (2.3).
    private ulong mainClaim;
    private ulong seenClaim;
    /// <summary>Seconds since 1970 (both computers keep network time, so claims compare across them).</summary>
    public Func<double> WallClock { get; set; } = () => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;
    /// <summary>Called (with the lock held: hand the work to another thread) when this computer becomes the main (true) or stops being it (false).</summary>
    public Action<bool>? OnRoleChange { get; set; }

    public Conductor(Guid instanceId, string displayName, AppSettings settings, IMidiOutput? midi, IPacketSink net,
                     Func<double> clock, Func<ulong> nanos, int redundancy = 2, uint? session = null)
    {
        InstanceId = instanceId;
        DisplayName = displayName;
        engine = new PerformanceEngine(settings.CueKeys, (byte)(Math.Clamp(settings.MidiChannel, 1, 16) - 1));
        blockCueKeys = settings.BlockCueKeys;
        keysGuard = new NoteGuard(settings.AutoNoteOffSeconds);
        peerGuard = new NoteGuard(settings.AutoNoteOffSeconds, minimumTimeout: 3);
        sendKeys = settings.SendKeys;
        receiveNotes = settings.ReceiveNotes;
        keyCapture = settings.KeyCapture;
        this.midi = midi;
        this.net = net;
        Redundancy = Math.Max(1, redundancy);
        this.session = session ?? (uint)Random.Shared.NextInt64(1, (long)uint.MaxValue + 1);
        this.clock = clock;
        this.nanos = nanos;
    }

    private string MyId => GuidBytes.ToSwiftString(InstanceId);

    // MARK: Public inputs

    /// <summary>Handles a key event. Returns true when the key should be kept from other apps.</summary>
    public bool HandleKey(KeyInput input)
    {
        lock (gate)
        {
            bool swallow = false;
            if (input.IsDown && !input.IsRepeat) swallowed.Remove(input.KeyCode);
            if (!input.IsDown && swallowed.Remove(input.KeyCode)) swallow = true;
            if (input.IsDown && input.IsRepeat && swallowed.Contains(input.KeyCode)) return true;
            if (!keyCapture || !sendKeys || quitting) return swallow;
            if (input.IsDown && blockCueKeys && input.Modifiers == Modifiers.None && engine.IsCueKey(input.KeyCode))
            {
                swallowed.Add(input.KeyCode);
                swallow = true;
            }
            foreach (var (m, cue) in engine.HandleEvents(input))
            {
                EmitLocal(m, fromKeys: true);
                if (cue is not null && m.IsNoteOn) { SendCue(m, cue); continue; }
                if (!m.IsNoteOn)
                {
                    var i = sentCues.FindLastIndex(c => c.Cue.KeyCode == input.KeyCode);
                    if (i >= 0) sentCues[i].KeyUp = true;
                }
                SendRemote(m);
            }
            return swallow;
        }
    }

    /// <summary>Would this key-down be kept from other apps? (No state change; for the keyboard hook.)</summary>
    public bool IsCueKey(ushort keyCode)
    {
        lock (gate) return engine.IsCueKey(keyCode);
    }

    /// <summary>A cue fired from somewhere else (for example a test button): press and release. False if it is not a cue key.</summary>
    public bool PressCue(ushort keyCode)
    {
        lock (gate)
        {
            if (!sendKeys || quitting || !engine.IsCueKey(keyCode) || engine.Held.ContainsKey(keyCode)) return false;
            foreach (var input in new[] { new KeyInput(keyCode, true), new KeyInput(keyCode, false) })
            {
                foreach (var (m, cue) in engine.HandleEvents(input))
                {
                    EmitLocal(m, fromKeys: true);
                    if (cue is not null && m.IsNoteOn) { SendCue(m, cue); continue; }
                    if (!m.IsNoteOn)
                    {
                        var i = sentCues.FindLastIndex(c => c.Cue.KeyCode == keyCode);
                        if (i >= 0) sentCues[i].KeyUp = true;
                    }
                    SendRemote(m);
                }
            }
            return true;
        }
    }

    public IReadOnlyList<CueKey> CueKeys
    {
        get { lock (gate) return engine.CueKeys.Values.OrderBy(k => k.Note).ToList(); }
    }

    /// <summary>
    /// A datagram arrived. <paramref name="knownPeer"/> is the peer already bound to the route it came
    /// on, if any. Returns the peer ID the packet belongs to (so the transport can bind a new route
    /// after a hello), or null if it was not usable.
    /// </summary>
    public string? Receive(byte[] bytes, string? knownPeer)
    {
        bool isHello = SecureChannel.IsHello(bytes);
        if (!isHello && knownPeer is null) return null;
        lock (gate)
        {
            if (quitting) return null;
            double now = clock();
            if (channel is null) return null;   // no pairing code: nothing is trusted

            Packet packet;
            if (isHello)
            {
                try { packet = channel.OpenHello(bytes); }
                catch (SecureChannel.OpenException) { NoteMismatch(bytes, now); return null; }
            }
            else
            {
                var k = knownPeer!;
                Packet? opened = null;
                if (peerNonces.TryGetValue(k, out var nonce)) opened = TryOpen(bytes, nonce);
                if (opened is null && pendingHello is { } h && h.Peer == k && TryOpen(bytes, h.Nonce) is Packet p2)
                {
                    // The peer really restarted (an old capture cannot seal with our current nonce): take its new session.
                    pendingHello = null;
                    var f0 = filters.GetValueOrDefault(k) ?? new SequenceFilter();
                    f0.Accept(h.Session, h.Seq);
                    filters[k] = f0;
                    peerNonces[k] = h.Nonce;
                    SetName(h.Name, k);
                    Perform(link.ReceivedHello(k, now));
                    Log($"{NameOf(k)} restarted; continuing with its new session");
                    ResetCues();
                    peerEpoch = null;
                    opened = p2;
                }
                if (opened is null) return null;
                packet = opened;
            }

            string peer = packet.Body switch
            {
                PacketBody.Hello h => GuidBytes.ToSwiftString(h.InstanceId),
                PacketBody.HelloAck h => GuidBytes.ToSwiftString(h.InstanceId),
                _ => knownPeer!,
            };
            if (peer == MyId) return null;
            // A connection made by IP address: the first answer tells us who is on the other end.
            if (knownPeer is string kp && kp.StartsWith(PeerInfo.ManualPrefix, StringComparison.Ordinal) && link.Peer == kp && kp != peer)
            {
                link.RenamePeer(kp, peer);
                if (peerNames.TryGetValue(kp, out var n) && !peerNames.ContainsKey(peer)) peerNames[peer] = n;
            }
            if (packet.Body.IsHelloOrAck)
            {
                // A hello on a new route must not take over a link that is alive on its own route.
                if (knownPeer != peer && link.IsConnected && link.Peer == peer && now - link.LastHeard < 2
                    && filters.GetValueOrDefault(peer)?.CurrentSession != packet.Session)
                {
                    LogIgnored(peer, now, "on a second route while the link is alive");
                    return null;
                }
            }
            if (packet.Body is PacketBody.HelloAck && link.Peer != peer) return null;
            if (packet.Body is PacketBody.Hello hello0 && link.IsConnected && link.Peer == peer
                && filters.GetValueOrDefault(peer)?.CurrentSession is uint current && current != packet.Session)
            {
                if (filters[peer].IsRetired(packet.Session)) return null;
                // Another session while the link is up: answer it, but change nothing until the new session proves itself.
                pendingHello = (peer, packet.Session, packet.Seq, hello0.Nonce, hello0.Name);
                SendBody(new PacketBody.HelloAck(InstanceId, channel.MyNonce, DisplayName), peer);
                return null;
            }
            var f = filters.GetValueOrDefault(peer) ?? new SequenceFilter();
            bool orderFree = packet.Body switch
            {
                PacketBody.Heartbeat or PacketBody.HeartbeatAck or PacketBody.Held or PacketBody.Features or PacketBody.CueName
                    or PacketBody.NoteAck or PacketBody.CueCount or PacketBody.LiveAck or PacketBody.LiveStatus or PacketBody.SetSummary
                    or PacketBody.SetItem or PacketBody.LiveResult or PacketBody.RoleClaim or PacketBody.RemoteSummary or PacketBody.Desk => true,
                PacketBody.LiveCommandPacket lc => !lc.Command.IsContinuous,
                _ => false,
            };
            bool fresh = f.Accept(packet.Session, packet.Seq, orderFree);
            filters[peer] = f;
            if (!fresh) return packet.Body.IsHelloOrAck ? null : peer;

            switch (packet.Body)
            {
                case PacketBody.Hello h:
                    SetName(h.Name, peer);
                    peerNonces[peer] = h.Nonce;
                    mismatchAt.Remove(peer);
                    Perform(link.ReceivedHello(peer, now));
                    break;
                case PacketBody.HelloAck h:
                    SetName(h.Name, peer);
                    peerNonces[peer] = h.Nonce;
                    mismatchAt.Remove(peer);
                    Perform(link.ReceivedHelloAck(peer, now));
                    break;
                case PacketBody.Bye:
                    Perform(link.ReceivedBye(peer));
                    break;
                case PacketBody.Heartbeat hb:
                    Perform(link.ReceivedHeartbeat(peer, hb.TimestampNanos, now));
                    break;
                case PacketBody.HeartbeatAck ha:
                    {
                        ulong n = nanos();
                        double rtt = n >= ha.TimestampNanos ? (n - ha.TimestampNanos) / 1e9 : 0;
                        link.ReceivedHeartbeatAck(peer, rtt, now);
                        break;
                    }
                case PacketBody.NoteOn on:
                    if (link.Peer != peer || !link.IsConnected) return peer;
                    link.ReceivedOther(peer, now);
                    if (receiveNotes)
                    {
                        EmitLocal(MidiMessage.NoteOn(on.Channel, on.Note, on.Velocity), fromKeys: false);
                        PlayedCueFromPeer(packet.Session, packet.Seq, on.Channel, on.Note, peer);
                    }
                    break;
                case PacketBody.CueResend r:
                    if (link.Peer != peer || !link.IsConnected) return peer;
                    link.ReceivedOther(peer, now);
                    if (!receiveNotes) return peer;
                    if (playedCueSeqs.Contains(new PlayedCue(packet.Session, r.OriginalSeq)))
                    {
                        SendBody(new PacketBody.NoteAck(r.OriginalSeq), peer);   // our answer was lost: answer again
                    }
                    else
                    {
                        EmitLocal(MidiMessage.NoteOn(r.Channel, r.Note, r.Velocity), fromKeys: false);
                        if (r.Released) EmitLocal(MidiMessage.NoteOff(r.Channel, r.Note), fromKeys: false);
                        PlayedCueFromPeer(packet.Session, r.OriginalSeq, r.Channel, r.Note, peer);
                        Log($"Cue {MidiMessage.NoteName(r.Note)} arrived on a resend");
                    }
                    break;
                case PacketBody.NoteAck ack:
                    {
                        if (link.Peer != peer || !link.IsConnected) return peer;
                        link.ReceivedOther(peer, now);
                        var c = sentCues.Find(x => x.Seq == ack.Seq);
                        if (c is not null && c.Delivery is CueStatus.DeliveryKind.Waiting or CueStatus.DeliveryKind.Missing or CueStatus.DeliveryKind.Unconfirmed)
                        {
                            c.Delivery = CueStatus.DeliveryKind.Delivered;
                            c.Ms = Math.Max(0, now - c.SentAt) * 1000;
                        }
                        break;
                    }
                case PacketBody.Features fe:
                    {
                        if (link.Peer != peer) return peer;
                        peerAnswersCues = (fe.Flags & 1) != 0;
                        bool restarted;
                        if (fe.Epoch is byte e)
                        {
                            if (peerEpoch is { } old) restarted = old.Session != packet.Session || old.Epoch != e;
                            else restarted = (fe.Flags & 2) != 0 && countedSinceReset;
                            peerEpoch = (packet.Session, e);
                        }
                        else
                        {
                            restarted = (fe.Flags & 2) != 0;   // 1.0.0
                        }
                        if (restarted && link.IsConnected)
                        {
                            ResetCues();
                            SendBody(FeaturesBody(), peer);
                            SendCueNames(peer);
                        }
                        break;
                    }
                case PacketBody.RoleClaim rc:
                    {
                        if (link.Peer != peer || !link.IsConnected) return peer;
                        seenClaim = Math.Max(seenClaim, rc.Millis);
                        bool theirsNewer = rc.Millis > mainClaim || (rc.Millis == mainClaim && string.CompareOrdinal(peer, MyId) > 0);
                        if (theirsNewer)
                        {
                            if (sendKeys || mainClaim > 0) BecomeReceiver();
                        }
                        else if (mainClaim > 0)
                        {
                            SendBody(new PacketBody.RoleClaim(mainClaim), peer);   // ours is newer: tell them now
                        }
                        break;
                    }
                case PacketBody.RoleHandover:
                    if (link.Peer != peer || !link.IsConnected) return peer;
                    ClaimMainLocked();
                    break;
                case PacketBody.CueCount cc:
                    if (link.Peer != peer) return peer;
                    ApplyPeerCount(packet.Session, cc.Seq, (int)Math.Min(cc.Count, int.MaxValue));
                    break;
                case PacketBody.CueName cn:
                    if (link.Peer != peer) return peer;
                    peerCueNames[new NoteGuard.Key(cn.Channel, cn.Note)] = (Clean(cn.Label), Clean(cn.Memo));
                    if (peerCueNames.Count > 128) peerCueNames.Clear();
                    break;
                case PacketBody.NoteOff off:
                    if (link.Peer != peer || !link.IsConnected) return peer;
                    link.ReceivedOther(peer, now);
                    if (receiveNotes) EmitLocal(MidiMessage.NoteOff(off.Channel, off.Note), fromKeys: false);
                    break;
                case PacketBody.Held held:
                    {
                        if (link.Peer != peer || !link.IsConnected) return peer;
                        link.ReceivedOther(peer, now);
                        // The full list of keys the peer holds: any other note from the peer lost its note-off and ends now.
                        var listed = held.Notes.Select(n => new NoteGuard.Key(held.Channel, n)).ToHashSet();
                        foreach (var k in listed) peerGuard.Touch(k.Channel, k.Note, now);
                        foreach (var k in peerGuard.Active.Keys.Where(k => k.Channel == held.Channel && !listed.Contains(k)).ToList())
                            EmitLocal(MidiMessage.NoteOff(k.Channel, k.Note), fromKeys: false);
                        break;
                    }
                case PacketBody.AllNotesOff:
                    if (link.Peer != peer) return peer;
                    link.ReceivedOther(peer, now);
                    LocalAllNotesOff();
                    Log($"All Notes Off received from {NameOf(peer)}");
                    break;
                case PacketBody.LiveCommandPacket:
                case PacketBody.LiveAck:
                case PacketBody.LiveStatus:
                case PacketBody.SetSummary:
                case PacketBody.SetItem:
                case PacketBody.LiveResult:
                case PacketBody.RemoteSummary:
                case PacketBody.Desk:
                    // Phase 2-3 (Live, iPhone) and the Mac-only console: not handled yet. Still a sign of life.
                    if (link.Peer == peer && link.IsConnected) link.ReceivedOther(peer, now);
                    break;
            }
            LinkChanged();
            return peer;
        }
    }

    private Packet? TryOpen(byte[] bytes, byte[] nonce)
    {
        try { return channel!.Open(bytes, nonce); }
        catch (SecureChannel.OpenException) { return null; }
    }

    /// <summary>Call every ~100 ms.</summary>
    public void Tick()
    {
        lock (gate)
        {
            double now = clock();
            Perform(link.Tick(now));
            LinkChanged();
            CheckCue(now);
            // A key "held" longer than MaxProtectedHold probably lost its key-up: end it on both computers.
            foreach (var note in engine.HeldNotes)
            {
                var k = new NoteGuard.Key(engine.Channel, note);
                if (keysGuard.Active.TryGetValue(k, out var t) && now - t >= MaxProtectedHold)
                {
                    foreach (var m in engine.Release(note)) { EmitLocal(m, fromKeys: true); SendRemote(m); }
                    Log($"Released {MidiMessage.NoteName(note)} after {(int)MaxProtectedHold} s without a key-up");
                }
            }
            var down = engine.HeldNotes.Select(n => new NoteGuard.Key(engine.Channel, n)).ToHashSet();
            foreach (var m in keysGuard.Expire(now, down)) { midi?.Send(m.Bytes); Log($"Auto note-off {MidiMessage.NoteName(m.Note)}"); }
            foreach (var m in peerGuard.Expire(now)) { midi?.Send(m.Bytes); Log($"Auto note-off {MidiMessage.NoteName(m.Note)} (from peer)"); }
        }
    }

    public void Connect(string peer)
    {
        lock (gate)
        {
            if (channel is null) { Log("Cannot connect: no pairing code set"); return; }
            Perform(link.Connect(peer, clock()));
            LinkChanged();
        }
    }

    public void Disconnect()
    {
        lock (gate)
        {
            Perform(link.Disconnect(clock()));
            LinkChanged();
        }
    }

    public void Panic()
    {
        lock (gate)
        {
            Apply(SafetyTrigger.PanicButton, link.IsConnected ? link.Peer : null);
            Log("Panic: All Notes Off");
        }
    }

    /// <summary>The keyboard hook may have missed key-ups: end notes of keys we think are down, here and on the peer.</summary>
    public void ReleaseHeldKeys()
    {
        lock (gate)
        {
            swallowed.Clear();
            if (engine.HeldNotes.Count == 0) return;
            Apply(SafetyTrigger.KeyCaptureTurnedOff, link.IsConnected ? link.Peer : null);
            Log("Released held keys (key events may have been missed)");
        }
    }

    public void PrepareForQuit()
    {
        lock (gate)
        {
            quitting = true;
            if (link.Peer is not null) Perform(link.Disconnect(clock()));
            else Apply(SafetyTrigger.AppWillQuit, null);
        }
    }

    public void SetSendKeys(bool on)
    {
        lock (gate)
        {
            if (on == sendKeys) return;
            if (!on) Apply(SafetyTrigger.SendingTurnedOff, link.IsConnected ? link.Peer : null);
            sendKeys = on;
        }
    }

    public void SetKeyCapture(bool on)
    {
        lock (gate)
        {
            if (on == keyCapture) return;
            if (!on) Apply(SafetyTrigger.KeyCaptureTurnedOff, link.IsConnected ? link.Peer : null);
            keyCapture = on;
        }
    }

    public void SetReceiveNotes(bool on)
    {
        lock (gate)
        {
            receiveNotes = on;
            if (!on) foreach (var m in peerGuard.ReleaseAll()) midi?.Send(m.Bytes);
        }
    }

    public void SetAutoNoteOff(double seconds)
    {
        lock (gate) { keysGuard.Timeout = seconds; peerGuard.Timeout = seconds; }
    }

    /// <summary>Sets the cue keys and tells the other computer their names.</summary>
    public void SetCueKeys(IEnumerable<CueKey> keys)
    {
        lock (gate)
        {
            foreach (var off in engine.SetCueKeys(keys)) { EmitLocal(off, fromKeys: true); SendRemote(off); }
            if (link.IsConnected && link.Peer is string p) SendCueNames(p);
        }
    }

    public void SetBlockCueKeys(bool on)
    {
        lock (gate) blockCueKeys = on;
    }

    /// <summary>The transport opened a fresh route to the peer: say hello on it right away.</summary>
    public void NewRoute(string peer)
    {
        lock (gate)
        {
            if (link.Peer != peer || channel is null) return;
            SendBody(new PacketBody.Hello(InstanceId, channel.MyNonce, DisplayName), peer);
        }
    }

    /// <summary>Sets (or clears) the pairing code. Changing it ends the current link. <paramref name="nonce"/> is only for tests.</summary>
    public void SetPairing(PairingSecret? secret, byte[]? nonce = null)
    {
        lock (gate)
        {
            if (link.Peer is not null) Perform(link.Disconnect(clock()));
            channel = secret is null ? null : new SecureChannel(secret, nonce);
            peerNonces.Clear(); filters.Clear(); mismatchAt.Clear();
            Log(secret is null ? "Pairing code cleared" : $"Pairing code set (fingerprint {secret.Fingerprint})");
        }
    }

    /// <summary>Forget sequence state and names of peers that are neither linked nor listed.</summary>
    public void Prune(IReadOnlySet<string> visible)
    {
        lock (gate)
        {
            var keep = new HashSet<string>(visible);
            if (link.Peer is string p) keep.Add(p);
            filters = filters.Where(kv => keep.Contains(kv.Key)).ToDictionary();
            peerNames = peerNames.Where(kv => keep.Contains(kv.Key)).ToDictionary();
            peerNonces = peerNonces.Where(kv => keep.Contains(kv.Key)).ToDictionary();
            mismatchAt = mismatchAt.Where(kv => keep.Contains(kv.Key)).ToDictionary();
        }
    }

    public void SetPeerName(string name, string peer)
    {
        lock (gate) SetName(name, peer);
    }

    public ConductorSnapshot Snapshot()
    {
        lock (gate)
        {
            double now = clock();
            CueStatus? cue = lastCueWasReceived ? receivedCue : null;
            // A cue that was not confirmed stays on screen (in red) until the next press.
            var c = sentCues.LastOrDefault(x => x.Delivery == CueStatus.DeliveryKind.Missing) ?? (lastCueWasReceived ? null : sentCues.LastOrDefault());
            if (c is not null)
                cue = new CueStatus(c.Cue.Label, c.Cue.Memo, c.Cue.Note, c.Count, c.Delivery, c.Ms, link.Peer is string lp ? NameOf(lp) : null);
            return new ConductorSnapshot(link.Current, link.LatencyMs, new Dictionary<string, string>(peerNames), channel is not null,
                mismatchAt.Where(kv => now - kv.Value < 15).Select(kv => kv.Key).ToHashSet(),
                engine.HeldNotes, sendKeys, receiveNotes, keyCapture, cue, mainClaim > 0);
        }
    }

    // MARK: Main / backup role

    public bool ClaimsMain { get { lock (gate) return mainClaim > 0; } }

    /// <summary>"Make this computer the main": send keys, stop playing the other computer's notes, and tell it.</summary>
    public void ClaimMain()
    {
        lock (gate) ClaimMainLocked();
    }

    /// <summary>"Return to main": only while linked. Returns false and changes nothing when not linked.</summary>
    public bool HandOverMain()
    {
        lock (gate)
        {
            if (!link.IsConnected || link.Peer is not string p)
            {
                Log("Return to Main refused: not linked to the other computer");
                return false;
            }
            BecomeReceiver();
            SendBody(new PacketBody.RoleHandover(), p, Redundancy);
            return true;
        }
    }

    private void ClaimMainLocked()
    {
        ulong wall = (ulong)Math.Max(0, WallClock() * 1000);
        mainClaim = Math.Max(wall, Math.Max(mainClaim + 1, seenClaim + 1));
        sendKeys = true;
        receiveNotes = false;
        foreach (var m in peerGuard.ReleaseAll()) midi?.Send(m.Bytes);
        if (link.IsConnected && link.Peer is string p) SendBody(new PacketBody.RoleClaim(mainClaim), p, Redundancy);
        Log("This computer is now the main");
        OnRoleChange?.Invoke(true);
    }

    private void BecomeReceiver()
    {
        if (sendKeys) Apply(SafetyTrigger.SendingTurnedOff, link.IsConnected ? link.Peer : null);
        sendKeys = false;
        receiveNotes = true;
        mainClaim = 0;
        Log("The other computer is the main now: this computer only receives");
        OnRoleChange?.Invoke(false);
    }

    // MARK: Internals (call with the lock held)

    private void Apply(SafetyTrigger trigger, string? peer)
    {
        var plan = Safety.Plan(trigger, peer is not null);
        switch (plan.Local)
        {
            case SafetyLocal.All:
                LocalAllNotesOff();
                if (plan.Remote && peer is not null) SendBody(new PacketBody.AllNotesOff(), peer, Redundancy);
                break;
            case SafetyLocal.NotesFromKeys:
                foreach (var m in engine.ReleaseAll())
                {
                    EmitLocal(m, fromKeys: true);
                    if (plan.Remote && peer is not null) SendNote(m, peer);
                }
                break;
            case SafetyLocal.NotesFromPeer:
                foreach (var m in peerGuard.ReleaseAll()) midi?.Send(m.Bytes);
                break;
        }
    }

    private void LocalAllNotesOff()
    {
        engine.ReleaseAll();
        foreach (var b in MidiMessage.AllNotesOffBytes) midi?.Send(b);
        // Some instruments ignore CC 123, so also end every note we know is on.
        foreach (var m in keysGuard.ReleaseAll().Concat(peerGuard.ReleaseAll())) midi?.Send(m.Bytes);
    }

    private void EmitLocal(MidiMessage m, bool fromKeys)
    {
        midi?.Send(m.Bytes);
        (fromKeys ? keysGuard : peerGuard).Record(m, clock());
    }

    private void SendRemote(MidiMessage m)
    {
        if (!link.IsConnected || link.Peer is not string p) return;
        SendNote(m, p);
    }

    private void SendNote(MidiMessage m, string p)
    {
        PacketBody body = m.IsNoteOn ? new PacketBody.NoteOn(m.Channel, m.Note, m.Velocity) : new PacketBody.NoteOff(m.Channel, m.Note);
        SendBody(body, p, Redundancy);
    }

    /// <summary>Returns the sequence number used.</summary>
    private uint SendBody(PacketBody body, string peer, int copies = 1)
    {
        if (channel is null) return 0;
        seq = unchecked(seq + 1);
        // Without the peer's nonce (no handshake yet) only hello/helloAck can be sent.
        var bytes = channel.Seal(new Packet(session, seq, body), peerNonces.GetValueOrDefault(peer));
        if (bytes is null) return seq;
        for (int i = 0; i < copies; i++) net.Send(bytes, peer);
        return seq;
    }

    // MARK: Cues

    private void SendCue(MidiMessage m, CueKey cue)
    {
        double now = clock();
        cueCount += 1;
        countedSinceReset = true;
        lastCueWasReceived = false;
        sentCues.RemoveAll(c => c.Delivery != CueStatus.DeliveryKind.Waiting);
        if (sentCues.Count >= 16) sentCues.RemoveAt(0);
        if (!link.IsConnected || link.Peer is not string p || !m.IsNoteOn)
        {
            sentCues.Add(new SentCue { Cue = cue, Count = cueCount, Seq = 0, SentAt = now, Delivery = CueStatus.DeliveryKind.NotConnected });
            return;
        }
        uint s = SendBody(new PacketBody.NoteOn(m.Channel, m.Note, m.Velocity), p, Redundancy);
        SendBody(new PacketBody.CueCount(s, (uint)cueCount), p, Redundancy);
        sentCues.Add(new SentCue { Cue = cue, Count = cueCount, Seq = s, SentAt = now, Delivery = CueStatus.DeliveryKind.Waiting });
    }

    private void CheckCue(double now)
    {
        foreach (var c in sentCues.Where(c => c.Delivery == CueStatus.DeliveryKind.Waiting).ToList())
        {
            double age = now - c.SentAt;
            if (!link.IsConnected || link.Peer is not string p) { c.Delivery = CueStatus.DeliveryKind.Missing; continue; }
            if (age >= CueAnswerTimeout)
            {
                if (peerAnswersCues)
                {
                    c.Delivery = CueStatus.DeliveryKind.Missing;
                    Log($"Cue {c.Cue.Label} ({MidiMessage.NoteName(c.Cue.Note)}): no answer from {NameOf(p)} within {(int)(CueAnswerTimeout * 1000)} ms");
                }
                else
                {
                    c.Delivery = CueStatus.DeliveryKind.Unconfirmed;
                }
                continue;
            }
            if (!peerAnswersCues || age < CueResendInterval * (c.Resends + 1) || c.Resends >= 2) continue;
            c.Resends += 1;
            SendBody(new PacketBody.CueCount(c.Seq, (uint)c.Count), p);
            SendBody(new PacketBody.CueResend(c.Seq, engine.Channel, c.Cue.Note, CueKey.Velocity,
                c.KeyUp || !engine.HeldNotes.Contains(c.Cue.Note)), p);
        }
    }

    /// <summary>The backup played a note-on from the peer: answer it, and show it as the last cue.</summary>
    private void PlayedCueFromPeer(uint sess, uint s, byte ch, byte note, string peer)
    {
        SendBody(new PacketBody.NoteAck(s), peer);
        var played = new PlayedCue(sess, s);
        playedCueSeqs.Add(played);
        if (playedCueSeqs.Count > 64) playedCueSeqs.RemoveAt(0);
        peerCueNames.TryGetValue(new NoteGuard.Key(ch, note), out var named);
        bool hasName = peerCueNames.ContainsKey(new NoteGuard.Key(ch, note));
        // An older cue that arrived late: it plays, but the screen keeps showing the newest cue.
        if (lastPlayed is PlayedCue last && last.Session == sess && unchecked((int)(s - last.Seq)) < 0 && lastCueWasReceived)
        {
            peerCounts.Remove(played);
            return;
        }
        lastPlayed = played;
        if (peerCounts.Remove(played, out var n)) cueCount = n; else cueCount += 1;
        countedSinceReset = true;
        lastCueWasReceived = true;
        receivedCue = new CueStatus(hasName ? named.Label : MidiMessage.NoteName(note), hasName ? named.Memo : "", note, cueCount,
            CueStatus.DeliveryKind.Received, null, NameOf(peer));
    }

    private void SendCueNames(string p)
    {
        foreach (var k in engine.CueKeys.Values.OrderBy(k => k.Note))
            SendBody(new PacketBody.CueName(engine.Channel, k.Note, k.Label, k.Memo), p);
        heartbeatsSinceNames = 0;
    }

    /// <summary>Start counting again when the link comes up.</summary>
    private void LinkChanged()
    {
        bool up = link.IsConnected;
        if (up == wasConnected) return;
        wasConnected = up;
        if (!up) { pendingHello = null; return; }
        ResetCues();
        peerAnswersCues = false; peerCueNames.Clear(); peerEpoch = null; pendingHello = null;
        linkEpoch = unchecked((byte)(linkEpoch + 1));
        if (link.Peer is string p)
        {
            // Bit 2: "I start counting again" (for 1.0.0); the new epoch does the same for 1.0.1+.
            SendBody(new PacketBody.Features(3, linkEpoch), p, Redundancy);
            SendCueNames(p);
        }
    }

    private PacketBody FeaturesBody() => new PacketBody.Features(1, linkEpoch);

    private void ApplyPeerCount(uint sess, uint s, int count)
    {
        var key = new PlayedCue(sess, s);
        if (lastPlayed == key && receivedCue is not null)
        {
            receivedCue = receivedCue with { Count = count };
            cueCount = count;
        }
        else
        {
            peerCounts[key] = count;
            if (peerCounts.Count > 32) peerCounts.Clear();
        }
    }

    private void ResetCues()
    {
        countedSinceReset = false;
        cueCount = 0; receivedCue = null; lastCueWasReceived = false;
        sentCues = sentCues.Where(c => c.Delivery is CueStatus.DeliveryKind.Waiting or CueStatus.DeliveryKind.Missing).ToList();
        foreach (var c in sentCues) c.Delivery = CueStatus.DeliveryKind.Missing;
    }

    /// <summary>Keeps printable characters only (Swift: no control or format characters, trimmed).</summary>
    internal static string Clean(string raw)
    {
        var sb = new StringBuilder(raw.Length);
        foreach (var r in raw.EnumerateRunes())
        {
            var cat = Rune.GetUnicodeCategory(r);
            if (cat is UnicodeCategory.Control or UnicodeCategory.Format) continue;
            sb.Append(r.ToString());
        }
        return sb.ToString().Trim(' ', '\t', ' ', '　');
    }

    /// <summary>A hello that failed authentication: if it names a visible peer, remember it for "pairing code does not match".</summary>
    private void NoteMismatch(byte[] bytes, double now)
    {
        if (bytes.Length <= SecureChannel.TagSize) return;
        var p = Packet.TryDecode(bytes.AsSpan(0, bytes.Length - SecureChannel.TagSize));
        Guid? id = p?.Body switch
        {
            PacketBody.Hello h => h.InstanceId,
            PacketBody.HelloAck h => h.InstanceId,
            _ => null,
        };
        if (id is not Guid g) return;
        var peer = GuidBytes.ToSwiftString(g);
        if (peer == MyId || !IsKnownPeer(peer)) return;
        mismatchAt[peer] = now;
        if (mismatchAt.Count > 64) mismatchAt.Clear();
        LogIgnored(peer, now, "pairing code does not match");
    }

    private void Perform(List<LinkStateMachine.Action> actions)
    {
        foreach (var a in actions)
        {
            switch (a)
            {
                case LinkStateMachine.Action.SendHello h:
                    net.ResetRoute(h.Peer);
                    if (channel is not null) SendBody(new PacketBody.Hello(InstanceId, channel.MyNonce, DisplayName), h.Peer);
                    break;
                case LinkStateMachine.Action.SendHelloAck h:
                    if (channel is not null) SendBody(new PacketBody.HelloAck(InstanceId, channel.MyNonce, DisplayName), h.Peer);
                    break;
                case LinkStateMachine.Action.SendHeartbeat h:
                    {
                        var p = h.Peer;
                        SendBody(new PacketBody.Heartbeat(nanos()), p);
                        // Always send the full list (also when empty): the peer ends any of our notes not in it.
                        bool on = sendKeys && keyCapture;
                        SendBody(new PacketBody.Held(engine.Channel, on ? [.. engine.HeldNotes] : []), p);
                        SendBody(FeaturesBody(), p);
                        if (mainClaim > 0) SendBody(new PacketBody.RoleClaim(mainClaim), p);
                        heartbeatsSinceNames += 1;
                        if (heartbeatsSinceNames >= 10 && link.IsConnected) SendCueNames(p);
                        break;
                    }
                case LinkStateMachine.Action.SendHeartbeatAck h:
                    SendBody(new PacketBody.HeartbeatAck(h.TimestampNanos), h.Peer);
                    break;
                case LinkStateMachine.Action.SendBye b:
                    SendBody(new PacketBody.Bye(), b.Peer, Redundancy);
                    break;
                case LinkStateMachine.Action.DoSafety s:
                    Apply(s.Trigger, s.Peer);
                    break;
                case LinkStateMachine.Action.Log l when l.Message.StartsWith("Ignored hello", StringComparison.Ordinal):
                    {
                        // Repeated hellos can be a flood: log each kind at most once a minute.
                        double now = clock();
                        if (ignoredLogAt.TryGetValue(l.Message, out var t) && now - t < 60) continue;
                        ignoredLogAt[l.Message] = now;
                        if (ignoredLogAt.Count > 64) ignoredLogAt.Clear();
                        Log(WithNames(l.Message));
                        break;
                    }
                case LinkStateMachine.Action.Log l:
                    Log(WithNames(l.Message));
                    break;
            }
        }
    }

    private string WithNames(string s) => peerNames.Aggregate(s, (acc, kv) => acc.Replace(kv.Key, kv.Value, StringComparison.Ordinal));

    private string NameOf(string peer) => peerNames.GetValueOrDefault(peer) ?? peer;

    private void SetName(string raw, string peer)
    {
        var clean = Clean(raw);
        if (clean.Length > 0) peerNames[peer] = clean;
    }

    private void LogIgnored(string peer, double now, string why)
    {
        if (ignoredLogAt.TryGetValue(peer, out var t) && now - t < 60) return;
        ignoredLogAt[peer] = now;
        if (ignoredLogAt.Count > 64) ignoredLogAt.Clear();
        Log($"Ignored hello from {peer}: {why}");
    }
}
