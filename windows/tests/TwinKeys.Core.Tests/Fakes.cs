namespace TwinKeys.Core.Tests;

public sealed class FakeMidi : IMidiOutput
{
    public readonly List<byte[]> Sent = [];
    public void Send(byte[] bytes) { lock (Sent) Sent.Add(bytes); }
    public List<byte[]> Notes { get { lock (Sent) return Sent.Where(b => (b[0] & 0xF0) != 0xB0).ToList(); } }
    public int AllNotesOffCount { get { lock (Sent) return Sent.Count(b => (b[0] & 0xF0) == 0xB0 && b[1] == 123); } }
    public bool Contains(params byte[] m) { lock (Sent) return Sent.Any(b => b.SequenceEqual(m)); }
    public int Count(params byte[] m) { lock (Sent) return Sent.Count(b => b.SequenceEqual(m)); }
}

public sealed class FakeNet : IPacketSink
{
    public List<(string Peer, byte[] Bytes)> Outbox = [];
    public readonly List<string> Resets = [];
    public void Send(byte[] bytes, string peer) => Outbox.Add((peer, bytes));
    public void ResetRoute(string peer) => Resets.Add(peer);
}

/// <summary>Two simulated computers ("main" and "backup") wired through a fake network (as in the Swift CueTests).</summary>
public sealed class TwoComputers
{
    public double Now;
    public readonly Guid MainId = Guid.NewGuid(), BackupId = Guid.NewGuid();
    public FakeMidi MainMidi = new(), BackupMidi = new();
    public FakeNet MainNet = new(), BackupNet = new();
    public Conductor Main, Backup;
    public bool MainToBackupUp = true, BackupToMainUp = true;
    public Func<byte[], bool> DropMain = _ => false;
    public Func<byte[], bool> DropFromBackup = _ => false;
    public readonly PairingSecret Secret = new(Enumerable.Repeat((byte)7, 32).ToArray());
    public string MainKey => GuidBytes.ToSwiftString(MainId);
    public string BackupKey => GuidBytes.ToSwiftString(BackupId);

    public TwoComputers(Action<AppSettings>? main = null, Action<AppSettings>? backup = null)
    {
        var m = new AppSettings { ReceiveNotes = false };
        main?.Invoke(m);
        var b = new AppSettings { SendKeys = false };
        backup?.Invoke(b);
        Main = Make(MainId, "Main", m, MainMidi, MainNet, 1);
        Backup = Make(BackupId, "Backup", b, BackupMidi, BackupNet, 2);
    }

    public Conductor Make(Guid id, string name, AppSettings s, FakeMidi midi, FakeNet net, uint session)
    {
        var c = new Conductor(id, name, s, midi, net, () => Now, () => (ulong)(Now * 1e9), session: session);
        c.SetPairing(Secret);
        return c;
    }

    public void Pump()
    {
        for (int i = 0; i < 10; i++)
        {
            var a = MainNet.Outbox; MainNet.Outbox = [];
            var b = BackupNet.Outbox; BackupNet.Outbox = [];
            if (a.Count == 0 && b.Count == 0) return;
            if (MainToBackupUp) foreach (var (_, x) in a) if (!DropMain(x)) Backup.Receive(x, MainKey);
            if (BackupToMainUp) foreach (var (_, x) in b) if (!DropFromBackup(x)) Main.Receive(x, BackupKey);
        }
    }

    public void Connect()
    {
        Main.Connect(BackupKey);
        Pump();
        Assert.Equal(new LinkStateMachine.State.Connected(BackupKey), Main.Snapshot().Link);
    }

    public void Tick(double seconds)
    {
        double end = Now + seconds;
        while (Now < end - 1e-9) { Now += 0.05; Main.Tick(); Backup.Tick(); Pump(); }
    }

    public void Press(ushort key)
    {
        Main.HandleKey(new KeyInput(key, true)); Pump();
        Main.HandleKey(new KeyInput(key, false)); Pump();
    }

    public int CueOnsAtBackup(byte note) => BackupMidi.Count(0x90, note, 127);
}
