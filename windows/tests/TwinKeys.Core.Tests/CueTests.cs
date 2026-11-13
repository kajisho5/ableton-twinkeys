namespace TwinKeys.Core.Tests;

using Delivery = CueStatus.DeliveryKind;

/// <summary>Cue keys and the delivery check (port of CueTests.swift and the role tests in ReviewFixesTests.swift).</summary>
public class CueTests
{
    readonly TwoComputers t = new();
    const ushort Down = KeyIds.Down, Up = KeyIds.Up;

    [Fact]
    public void OnlyCueKeysAreSentAtFullVelocity()
    {
        t.Main.HandleKey(new(0x1E, true));    // A is not a cue key by default
        Assert.Empty(t.MainMidi.Sent);
        t.Main.HandleKey(new(Down, true));
        t.Main.HandleKey(new(Down, true, IsRepeat: true));
        t.Main.HandleKey(new(Down, false));
        Assert.Equal([[0x90, 37, 127], [0x80, 37, 0]], t.MainMidi.Sent);
    }

    [Fact]
    public void DefaultsMatchTheMacNotes()
    {
        Assert.Equal(new byte[] { 36, 37, 38, 39, 40, 41, 42 }, CueKey.Defaults.Select(k => k.Note));
        Assert.Equal(["↑", "↓", "←", "→", "Space", "Enter", "Esc"], CueKey.Defaults.Select(k => k.Label));
    }

    [Fact]
    public void AddingLettersAndDigitsKeepsExistingNotes()
    {
        var keys = CueKey.Adding(KeyIds.Alphanumeric, CueKey.Defaults);
        Assert.Equal(7 + 36, keys.Count);
        Assert.Equal(CueKey.Defaults, keys.Take(7));
        Assert.Equal(keys.Count, keys.Select(k => k.Note).Distinct().Count());
        Assert.Equal("A", keys.First(k => k.KeyCode == 0x1E).Label);
        Assert.Equal("0", keys.First(k => k.KeyCode == 0x0B).Label);
        Assert.Equal(43, keys.First(k => k.KeyCode == 0x1E).Note);
        Assert.Equal(keys, CueKey.Adding([0x1E], keys));
    }

    [Fact]
    public void FreeNoteAndSanitize()
    {
        Assert.Equal((byte)43, CueKey.FreeNote(CueKey.Defaults));
        var keys = CueKey.Sanitized([CueKey.Make(Down, 37), CueKey.Make(Down, 50), CueKey.Make(Up, 37), CueKey.Make(0x1D, 60)]);
        Assert.Equal(new byte[] { 37 }, keys.Select(k => k.Note));
        var cut = CueKey.Sanitized([new CueKey(Down, new string('あ', 20), new string('い', 40), 37)])[0];
        Assert.Equal("ああああ", cut.Label);
        Assert.Equal(20, cut.Memo.Length);
    }

    [Fact]
    public void KeyIdsRoundTripThroughSettings()
    {
        Assert.Equal("sc:0x48:e", KeyIds.ToSetting(KeyIds.Up));
        Assert.Equal("sc:0x39", KeyIds.ToSetting(KeyIds.Space));
        Assert.Equal(KeyIds.Up, KeyIds.FromSetting("sc:0x48:e"));
        Assert.Equal(KeyIds.Space, KeyIds.FromSetting("sc:0x39"));
        Assert.Null(KeyIds.FromSetting("sc:0x00"));
        Assert.Null(KeyIds.FromSetting("vk:0x26"));
        Assert.Null(KeyIds.FromSetting("sc:0x48:x"));
        Assert.True(KeyIds.IsModifier(0x2A));
        Assert.Equal("Key E07A", KeyIds.Label(0xE07A));
    }

    [Fact]
    public void KeyRemovedWhileHeldStillEndsItsNote()
    {
        t.Main.HandleKey(new(Down, true));
        t.Main.SetCueKeys([]);
        t.Main.HandleKey(new(Down, false));
        Assert.Equal([[0x90, 37, 127], [0x80, 37, 0]], t.MainMidi.Sent);
    }

    [Fact]
    public void CueWithModifierIsNotSentAndNotSwallowed()
    {
        Assert.False(t.Main.HandleKey(new(Down, true, Modifiers: Modifiers.Shift)));
        Assert.Empty(t.MainMidi.Sent);
    }

    [Fact]
    public void CueKeysAreSwallowedOnlyWhileCaptureIsOn()
    {
        Assert.True(t.Main.HandleKey(new(Down, true)));
        Assert.True(t.Main.HandleKey(new(Down, true, IsRepeat: true)));
        Assert.True(t.Main.HandleKey(new(Down, false)));
        Assert.False(t.Main.HandleKey(new(0x1E, true)));
        t.Main.SetKeyCapture(false);
        Assert.False(t.Main.HandleKey(new(Down, true)));
        t.Main.SetKeyCapture(true); t.Main.SetBlockCueKeys(false);
        Assert.False(t.Main.HandleKey(new(Up, true)));
    }

    [Fact]
    public void SwallowedKeyDownAlsoSwallowsItsKeyUpAfterCaptureTurnsOff()
    {
        Assert.True(t.Main.HandleKey(new(Down, true)));
        t.Main.SetKeyCapture(false);
        Assert.True(t.Main.HandleKey(new(Down, false)));
    }

    [Fact]
    public void DeliveredCueShowsTheSameCountAndNameOnBoth()
    {
        t.Main.SetCueKeys([CueKey.Make(Down, 37, "次のシーン")]);
        t.Connect();
        for (int i = 0; i < 3; i++) t.Press(Down);
        var m = t.Main.Snapshot().LastCue!;
        var b = t.Backup.Snapshot().LastCue!;
        Assert.Equal(3, m.Count); Assert.Equal(3, b.Count);
        Assert.Equal("↓", m.Label); Assert.Equal("↓", b.Label);
        Assert.Equal("次のシーン", b.Memo);
        Assert.Equal(Delivery.Received, b.Delivery);
        Assert.Equal(Delivery.Delivered, m.Delivery);
        Assert.Equal(3, t.CueOnsAtBackup(37));
    }

    [Fact]
    public void LostCueIsResentOnceAndPlayedOnce()
    {
        t.Connect(); t.Tick(1.1);
        t.MainToBackupUp = false;
        t.Press(Down);
        t.MainNet.Outbox.Clear();
        t.MainToBackupUp = true;
        t.Tick(0.25);
        Assert.Equal(1, t.CueOnsAtBackup(37));
        Assert.Equal(1, t.BackupMidi.Count(0x80, 37, 0));
        Assert.Equal(Delivery.Delivered, t.Main.Snapshot().LastCue!.Delivery);
        t.Tick(1);
        Assert.Equal(1, t.CueOnsAtBackup(37));
    }

    [Fact]
    public void LostAnswerDoesNotPlayTheCueTwice()
    {
        t.Connect(); t.Tick(1.1);
        t.BackupToMainUp = false;
        t.Main.HandleKey(new(Down, true)); t.Pump();
        t.BackupNet.Outbox.Clear();
        t.BackupToMainUp = true;
        t.Tick(0.25);
        Assert.Equal(1, t.CueOnsAtBackup(37));
        Assert.Equal(Delivery.Delivered, t.Main.Snapshot().LastCue!.Delivery);
    }

    [Fact]
    public void NoAnswerWithinTimeoutIsMissing()
    {
        t.Connect(); t.Tick(1.1);
        t.MainToBackupUp = false;
        t.Main.HandleKey(new(Down, true));
        t.Tick(0.4);
        Assert.Equal(Delivery.Missing, t.Main.Snapshot().LastCue!.Delivery);
        Assert.Equal(0, t.CueOnsAtBackup(37));
    }

    [Fact]
    public void OldPeerIsUnconfirmed()
    {
        t.DropFromBackup = x => x[3] is 0x13 or 0x14 or 0x15;
        t.Connect(); t.Tick(1.1);
        t.Main.HandleKey(new(Down, true)); t.Pump();
        t.Tick(0.4);
        Assert.Equal(Delivery.Unconfirmed, t.Main.Snapshot().LastCue!.Delivery);
        Assert.Equal(1, t.CueOnsAtBackup(37));
    }

    [Fact]
    public void CueWhileNotConnected()
    {
        t.Main.HandleKey(new(Down, true));
        Assert.Equal(Delivery.NotConnected, t.Main.Snapshot().LastCue!.Delivery);
        Assert.Equal([[0x90, 37, 127]], t.MainMidi.Sent);
    }

    [Fact]
    public void CountStartsAgainAfterReconnect()
    {
        t.Connect();
        t.Press(Down);
        t.Main.Disconnect(); t.Pump();
        t.Connect();
        Assert.Null(t.Main.Snapshot().LastCue);
        t.Main.HandleKey(new(Down, true)); t.Pump();
        Assert.Equal(1, t.Main.Snapshot().LastCue!.Count);
        Assert.Equal(1, t.Backup.Snapshot().LastCue!.Count);
    }

    [Fact]
    public void HeldCueKeyKeepsSoundingOnTheBackup()
    {
        t.Connect();
        t.Main.HandleKey(new(Down, true)); t.Pump();
        t.Tick(2.5);
        Assert.False(t.BackupMidi.Contains(0x80, 37, 0));
    }

    [Fact]
    public void OneSidedReconnectKeepsBothCountsAndNames()
    {
        t.Main.SetCueKeys([CueKey.Make(Down, 37, "Next")]);
        t.Connect(); t.Tick(1.1);
        for (int i = 0; i < 3; i++) t.Press(Down);
        t.BackupToMainUp = false;
        t.Tick(3.5);
        t.BackupToMainUp = true;
        t.Tick(2);
        Assert.Equal(new LinkStateMachine.State.Connected(t.BackupKey), t.Main.Snapshot().Link);
        t.Press(Down);
        Assert.Equal(t.Main.Snapshot().LastCue!.Count, t.Backup.Snapshot().LastCue!.Count);
        Assert.Equal("Next", t.Backup.Snapshot().LastCue!.Memo);
    }

    [Fact]
    public void LostFirstOfTwoQuickPressesIsResentAndBothArrive()
    {
        t.Connect(); t.Tick(1.1);
        bool dropping = true;
        t.DropMain = b => dropping && b[3] == 0x10;
        t.Main.HandleKey(new(Down, true)); t.Pump();
        dropping = false;
        t.Main.HandleKey(new(Down, false)); t.Pump();
        t.Now += 0.04;
        t.Press(Up);
        t.Tick(0.5);
        Assert.Equal(1, t.CueOnsAtBackup(37));
        Assert.Equal(1, t.CueOnsAtBackup(36));
        Assert.Equal(2, t.Backup.Snapshot().LastCue?.Count);
        Assert.Equal(2, t.Main.Snapshot().LastCue?.Count);
        Assert.Equal(Delivery.Delivered, t.Main.Snapshot().LastCue!.Delivery);
    }

    [Fact]
    public void MainRestartWhileLinkedStillReconnects()
    {
        t.Connect(); t.Tick(1.1);
        t.Press(Down);
        var newNet = new FakeNet();
        t.Main = t.Make(t.MainId, "Main", new AppSettings { ReceiveNotes = false }, t.MainMidi, newNet, 5);
        t.MainNet = newNet;
        t.Main.Connect(t.BackupKey);
        for (int i = 0; i < 40; i++) { t.Now += 0.05; t.Main.Tick(); t.Backup.Tick(); t.Pump(); }
        Assert.Equal(new LinkStateMachine.State.Connected(t.BackupKey), t.Main.Snapshot().Link);
        t.Press(Down);
        Assert.Equal(2, t.CueOnsAtBackup(37));
        Assert.Equal(t.Main.Snapshot().LastCue?.Count, t.Backup.Snapshot().LastCue?.Count);
    }

    [Fact]
    public void ReplayedOldHelloDoesNotBreakTheLink()
    {
        var oldNet = new FakeNet();
        var old = new Conductor(t.MainId, "Main", new AppSettings(), null, oldNet, () => t.Now, () => 0, session: 77);
        old.SetPairing(t.Secret);
        old.Connect(t.BackupKey);
        var captured = oldNet.Outbox.Select(x => x.Bytes).ToList();
        t.Connect(); t.Tick(1.1);
        foreach (var b in captured) Assert.Null(t.Backup.Receive(b, t.MainKey));
        foreach (var b in captured) Assert.Null(t.Backup.Receive(b, null));
        t.Tick(5);
        Assert.Equal(new LinkStateMachine.State.Connected(t.MainKey), t.Backup.Snapshot().Link);
        t.Press(Down);
        Assert.Equal(1, t.CueOnsAtBackup(37));
    }

    [Fact]
    public void ResentCueEndsWhenTheKeyWasReleasedByTheApp()
    {
        t.Connect(); t.Tick(1.1);
        t.DropMain = b => b[3] == 0x10;
        t.Main.HandleKey(new(Down, true)); t.Pump();
        t.DropMain = _ => false;
        t.Main.ReleaseHeldKeys();
        t.Tick(0.4);
        Assert.Equal(new byte[] { 0x80, 37, 0 }, t.BackupMidi.Sent.Where(b => b[1] == 37).Last());
    }

    // MARK: Main / backup role (2.3)

    [Fact]
    public void ReturnToMainIsRefusedWhileNotLinked()
    {
        t.Backup.ClaimMain();
        Assert.False(t.Backup.HandOverMain());
        Assert.True(t.Backup.Snapshot().SendKeys);
        Assert.True(t.Backup.ClaimsMain);
        t.Connect(); t.Tick(1.1);
        Assert.True(t.Backup.HandOverMain()); t.Pump();
        Assert.False(t.Backup.Snapshot().SendKeys);
    }

    [Fact]
    public void ALaterClaimWinsDespiteClockSkew()
    {
        t.Main.WallClock = () => 2_000_000_000;
        t.Backup.WallClock = () => 1_000_000;
        t.Connect(); t.Tick(1.1);
        t.Main.ClaimMain(); t.Tick(1.1);
        Assert.True(t.Main.ClaimsMain);
        t.Backup.ClaimMain(); t.Tick(1.1);
        Assert.True(t.Backup.ClaimsMain);
        Assert.True(t.Backup.Snapshot().SendKeys);
        Assert.False(t.Main.ClaimsMain);
        Assert.False(t.Main.Snapshot().SendKeys);
        t.Main.ClaimMain(); t.Tick(1.1);
        Assert.True(t.Main.ClaimsMain);
        Assert.False(t.Backup.ClaimsMain);
    }

    [Fact]
    public void AGoodbyeIsNotALoss()
    {
        t.Connect(); t.Tick(1.1);
        var w = new MainLossWatch();
        w.Update(t.Backup.Snapshot().Link, t.Now);
        t.Main.PrepareForQuit(); t.Pump();
        w.Update(t.Backup.Snapshot().Link, t.Now);
        Assert.Equal(new LinkStateMachine.State.Idle(), t.Backup.Snapshot().Link);
        Assert.False(w.IsLost(t.Now + 10));
    }
}
