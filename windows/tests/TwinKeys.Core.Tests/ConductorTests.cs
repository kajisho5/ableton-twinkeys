namespace TwinKeys.Core.Tests;

using Connected = LinkStateMachine.State.Connected;

/// <summary>Port of Tests/TwinKeysCoreTests/ConductorTests.swift (keys A and D as cue keys on notes 60 and 64).</summary>
public class ConductorTests
{
    const ushort KeyA = 0x1E, KeyD = 0x20;
    static readonly List<CueKey> TestKeys = [CueKey.Make(KeyA, 60), CueKey.Make(KeyD, 64)];
    readonly TwoComputers t = new(m => { m.ReceiveNotes = true; m.CueKeys = [.. TestKeys]; }, b => { b.CueKeys = [.. TestKeys]; });

    void Step(double seconds)
    {
        for (int i = 0; i < (int)(seconds * 10); i++) { t.Now += 0.1; t.Main.Tick(); t.Backup.Tick(); t.Pump(); }
    }

    void Connect()
    {
        t.Connect();
        Assert.Equal(new Connected(t.MainKey), t.Backup.Snapshot().Link);
    }

    [Fact]
    public void KeyPressPlaysSameNoteOnBothComputers()
    {
        Connect();
        t.Main.HandleKey(new(KeyA, true)); t.Main.HandleKey(new(KeyD, true)); t.Pump();
        t.Main.HandleKey(new(KeyA, false)); t.Main.HandleKey(new(KeyD, false)); t.Pump();
        byte[][] expected = [[0x90, 60, 127], [0x90, 64, 127], [0x80, 60, 0], [0x80, 64, 0]];
        Assert.Equal(expected, t.MainMidi.Notes);
        Assert.Equal(expected, t.BackupMidi.Notes);   // each note was sent twice, but arrives once
        Assert.Equal("Main", t.Backup.Snapshot().PeerNames[t.MainKey]);
    }

    [Fact]
    public void ReceiverWithReceiveOffPlaysNothing()
    {
        Connect();
        t.Backup.SetReceiveNotes(false);
        t.Main.HandleKey(new(KeyA, true)); t.Pump();
        Assert.Empty(t.BackupMidi.Notes);
    }

    [Fact]
    public void TurningCaptureOffEndsHeldNotesOnBoth()
    {
        Connect();
        t.Main.HandleKey(new(KeyA, true)); t.Pump();
        t.Main.SetKeyCapture(false); t.Pump();
        Assert.Equal(new byte[] { 0x80, 60, 0 }, t.MainMidi.Notes[^1]);
        Assert.Equal(new byte[] { 0x80, 60, 0 }, t.BackupMidi.Notes[^1]);
    }

    [Fact]
    public void PanicSendsAllNotesOffToBoth()
    {
        Connect();
        t.Main.HandleKey(new(KeyA, true)); t.Pump();
        t.Main.Panic(); t.Pump();
        Assert.Equal(16, t.MainMidi.AllNotesOffCount);
        Assert.Equal(16, t.BackupMidi.AllNotesOffCount);
        Assert.True(t.BackupMidi.Contains(0x80, 60, 0));
    }

    [Fact]
    public void PanicWhenNotConnectedOnlyLocal()
    {
        t.Main.Panic();
        Assert.Equal(16, t.MainMidi.AllNotesOffCount);
        Assert.Empty(t.MainNet.Outbox);
    }

    [Fact]
    public void QuitSendsAllNotesOffAndBye()
    {
        Connect();
        t.Main.PrepareForQuit(); t.Pump();
        Assert.Equal(16, t.MainMidi.AllNotesOffCount);
        Assert.Equal(16, t.BackupMidi.AllNotesOffCount);
        Assert.Equal(new LinkStateMachine.State.Idle(), t.Backup.Snapshot().Link);
        Assert.Equal(new LinkStateMachine.State.Idle(), t.Main.Snapshot().Link);
    }

    [Fact]
    public void NetworkLossKeepsMainNotesButEndsBackupNotesThenReconnects()
    {
        Connect();
        t.Main.HandleKey(new(KeyA, true)); t.Pump();
        t.MainToBackupUp = false; t.BackupToMainUp = false;
        Step(4);
        Assert.IsType<LinkStateMachine.State.Connecting>(t.Backup.Snapshot().Link);
        Assert.Equal(new byte[] { 0x80, 60, 0 }, t.BackupMidi.Notes[^1]);
        Assert.Single(t.MainMidi.Notes);
        t.MainToBackupUp = true; t.BackupToMainUp = true;
        Step(6);
        Assert.Equal(new Connected(t.BackupKey), t.Main.Snapshot().Link);
        Assert.Equal(new Connected(t.MainKey), t.Backup.Snapshot().Link);
        Assert.NotNull(t.Main.Snapshot().LatencyMs);
    }

    [Fact]
    public void LongHeldNoteKeepsSoundingOnBoth()
    {
        Connect();
        t.Main.HandleKey(new(KeyA, true)); t.Pump();
        Step(15);
        Assert.False(t.MainMidi.Contains(0x80, 60, 0));
        Assert.False(t.BackupMidi.Contains(0x80, 60, 0));
        t.Main.HandleKey(new(KeyA, false)); t.Pump();
        Assert.Equal(new byte[] { 0x80, 60, 0 }, t.BackupMidi.Notes[^1]);
    }

    [Fact]
    public void AutoNoteOffOnReceiverWhenNoteOffIsLost()
    {
        Connect();
        t.Main.HandleKey(new(KeyA, true)); t.Pump();
        t.MainToBackupUp = false;
        t.Main.HandleKey(new(KeyA, false)); t.Pump();
        Step(1);
        t.MainToBackupUp = true;
        Assert.False(t.BackupMidi.Contains(0x80, 60, 0));
        Step(9.5);
        Assert.True(t.BackupMidi.Contains(0x80, 60, 0));
    }

    [Fact]
    public void ManualDisconnectStaysDisconnectedWhenByeIsLost()
    {
        Connect();
        t.MainToBackupUp = false;
        Step(4);
        t.Main.Disconnect(); t.Pump();
        t.MainToBackupUp = true;
        Step(10);
        Assert.Equal(new LinkStateMachine.State.Idle(), t.Main.Snapshot().Link);
        Assert.Equal(new LinkStateMachine.State.Idle(), t.Backup.Snapshot().Link);
    }

    [Fact]
    public void MachineWithAnotherPairingCodeCannotLink()
    {
        t.Backup.SetPairing(new PairingSecret(Enumerable.Repeat((byte)99, 32).ToArray()));
        t.Main.Connect(t.BackupKey); t.Pump();
        Assert.Equal(new LinkStateMachine.State.Idle(), t.Backup.Snapshot().Link);
        Assert.NotEqual<LinkStateMachine.State>(new Connected(t.BackupKey), t.Main.Snapshot().Link);
        Assert.Equal([t.MainKey], t.Backup.Snapshot().MismatchedPeers);
    }

    [Fact]
    public void WithoutPairingCodeNothingLinks()
    {
        t.Main.SetPairing(null);
        t.Main.Connect(t.BackupKey); t.Pump();
        Assert.Empty(t.MainNet.Outbox);
        Assert.False(t.Main.Snapshot().IsPaired);
    }

    [Fact]
    public void TamperedOrForgedNotesAreDropped()
    {
        Connect();
        var forged = new Packet(1, 999, new PacketBody.NoteOn(0, 61, 127)).Encode().Concat(new byte[16]).ToArray();
        t.Backup.Receive(forged, t.MainKey);
        t.Main.HandleKey(new(KeyA, true));
        var real = t.MainNet.Outbox[0].Bytes; t.MainNet.Outbox.RemoveAt(0);
        real[^20] ^= 1;
        t.Backup.Receive(real, t.MainKey);
        Assert.DoesNotContain(t.BackupMidi.Sent, b => b[0] == 0x90);
    }

    [Fact]
    public void TrafficFromAnEarlierRunCannotBeReplayed()
    {
        Connect();
        t.Main.HandleKey(new(KeyA, true));
        var captured = t.MainNet.Outbox.Select(x => x.Bytes).ToList();
        t.Pump();
        t.Main.HandleKey(new(KeyA, false)); t.Pump();
        t.Backup.SetPairing(t.Secret);   // the backup restarts (new nonce)
        int before = t.BackupMidi.Sent.Count;
        foreach (var b in captured) t.Backup.Receive(b, t.MainKey);
        Assert.Equal(before, t.BackupMidi.Sent.Count);
    }

    [Fact]
    public void ConnectByAddressLearnsTheRealPeer()
    {
        t.Main.Connect("manual:192.0.2.10");
        foreach (var (_, b) in t.MainNet.Outbox) t.Backup.Receive(b, null);
        t.MainNet.Outbox.Clear();
        var replies = t.BackupNet.Outbox.Select(x => x.Bytes).ToList(); t.BackupNet.Outbox.Clear();
        Assert.Equal(t.BackupKey, t.Main.Receive(replies[0], "manual:192.0.2.10"));
        foreach (var b in replies.Skip(1)) t.Main.Receive(b, t.BackupKey);
        Assert.Equal(new Connected(t.BackupKey), t.Main.Snapshot().Link);
        Assert.Equal("Backup", t.Main.Snapshot().PeerNames[t.BackupKey]);
    }

    [Fact]
    public void HelloOnSecondRouteCannotTakeOverLiveLink()
    {
        Connect();
        var signer = new SecureChannel(t.Secret);
        var fake = signer.Seal(new Packet(999, 1, new PacketBody.Hello(t.BackupId, signer.MyNonce, "Fake")), null)!;
        Assert.Null(t.Main.Receive(fake, null));
        Assert.Equal("Backup", t.Main.Snapshot().PeerNames[t.BackupKey]);
    }

    [Fact]
    public void KeyHeldBeyondProtectionEndsOnBoth()
    {
        Connect();
        t.Main.HandleKey(new(KeyA, true)); t.Pump();
        Step(Conductor.MaxProtectedHold + 1);
        Assert.Equal(new byte[] { 0x80, 60, 0 }, t.MainMidi.Notes[^1]);
        Assert.Equal(new byte[] { 0x80, 60, 0 }, t.BackupMidi.Notes[^1]);
        Assert.Empty(t.Main.Snapshot().HeldNotes);
    }

    [Fact]
    public void PeerNameControlCharactersAreRemoved()
    {
        var signer = new SecureChannel(t.Secret);
        var p = signer.Seal(new Packet(5, 1, new PacketBody.Hello(Guid.NewGuid(), signer.MyNonce, "Evil\nPC\u0007​")), null)!;
        var id = t.Backup.Receive(p, null)!;
        Assert.Equal("EvilPC", t.Backup.Snapshot().PeerNames[id]);
    }

    [Fact]
    public void PacketsFromUnknownRouteAreIgnoredUnlessHello()
    {
        var note = new Packet(9, 1, new PacketBody.NoteOn(0, 60, 1)).Encode();
        Assert.Null(t.Backup.Receive(note, null));
        Assert.Null(t.Backup.Receive(note, "stranger"));
        Assert.Empty(t.BackupMidi.Sent);
    }

    [Fact]
    public void HelloResetsRouteForReconnect()
    {
        t.Main.Connect(t.BackupKey);
        Assert.Equal([t.BackupKey], t.MainNet.Resets);
    }

    [Fact]
    public void LogUsesPeerNames()
    {
        var lines = new List<string>();
        t.Main.Log = lines.Add;
        Connect();
        t.Main.Disconnect();
        Assert.Contains("Disconnected from Backup", lines);
    }
}
