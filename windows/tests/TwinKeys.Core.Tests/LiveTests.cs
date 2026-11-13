using System.Text.Json.Nodes;

namespace TwinKeys.Core.Tests;

/// <summary>
/// Phase 2: Live commands forwarded from the main to the backup, the backup's Live status, the set
/// check, and the Bridge state. Ports of Tests/TwinKeysCoreTests/RemoteTests.swift,
/// ReviewFixesTests.swift and SetCheckTests.swift (the parts that do not need the iPhone).
/// </summary>
public class LiveTests
{
    readonly TwoComputers t = new();
    readonly List<Action> deferred = [];

    public LiveTests()
    {
        // The backup's answer goes out from another thread in the app; here it runs when the test says.
        t.Backup.Defer = a => deferred.Add(a);
    }

    void RunDeferred() { var d = deferred.ToList(); deferred.Clear(); foreach (var a in d) a(); t.Pump(); }

    static JsonObject J(string json) => (JsonObject)JsonNode.Parse(json)!;

    [Fact]
    public void BackupRunsAForwardedCommandOnceEvenIfResent()
    {
        var ran = new List<LiveCommand>();
        t.Backup.OnLiveCommand = ran.Add;
        t.Connect(); t.Tick(1.1);
        bool dropping = true;
        // Lose the backup's answer once so the main resends.
        t.DropFromBackup = b => { if (dropping && b[3] == 0x19) { dropping = false; return true; } return false; };
        var id = t.Main.ForwardLive(new LiveCommand.FireScene(4));
        Assert.NotNull(id);
        t.Pump(); t.Tick(0.4);
        Assert.Equal([new LiveCommand.FireScene(4)], ran);
        Assert.Equal("delivered", t.Main.LiveDelivery(id!.Value));
    }

    [Fact]
    public void BackupReportsWhatItsLiveDid()
    {
        var answers = new List<(LiveCommand Cmd, Action<Conductor.LiveRun> Answer)>();
        t.Backup.OnLiveCommandRun = (cmd, answer) => answers.Add((cmd, answer));
        t.Connect(); t.Tick(1.1);
        var a = t.Main.ForwardLive(new LiveCommand.FireScene(1))!.Value;
        var b = t.Main.ForwardLive(new LiveCommand.FireScene(2))!.Value;
        var c = t.Main.ForwardLive(new LiveCommand.SetMute(3, true))!.Value;
        t.Pump();
        Assert.Equal(3, answers.Count);
        Assert.Equal("delivered", t.Main.LiveDelivery(a));
        Assert.False(Conductor.IsSettledLiveDelivery("delivered"));   // a liveResult is still to come
        answers[0].Answer(Conductor.LiveRun.Ran);
        answers[1].Answer(Conductor.LiveRun.NoAnswer);
        answers[2].Answer(Conductor.LiveRun.Refused);
        RunDeferred();
        Assert.Equal("ran", t.Main.LiveDelivery(a));
        Assert.Equal("noLive", t.Main.LiveDelivery(b));
        Assert.Equal("failedLive", t.Main.LiveDelivery(c));
        Assert.True(Conductor.IsSettledLiveDelivery("ran"));
        Assert.True(Conductor.IsSettledLiveDelivery("unknown"));
    }

    [Fact]
    public void ARepeatedAckDoesNotOverwriteTheLiveResult()
    {
        t.Backup.OnLiveCommandRun = (_, answer) => answer(Conductor.LiveRun.Ran);
        t.Connect(); t.Tick(1.1);
        var held = new List<byte[]>();
        t.DropFromBackup = x => { if (x[3] != 0x19) return false; held.Add(x); return true; };   // hold liveAck back
        var id = t.Main.ForwardLive(new LiveCommand.Play())!.Value;
        t.Pump();
        RunDeferred();
        Assert.Equal("ran", t.Main.LiveDelivery(id));
        Assert.NotEmpty(held);
        foreach (var x in held) t.Main.Receive(x, t.BackupKey);   // the late ack
        Assert.Equal("ran", t.Main.LiveDelivery(id));
    }

    [Fact]
    public void CommandWithoutAnswerIsMissing()
    {
        t.Backup.OnLiveCommand = _ => { };
        t.Connect(); t.Tick(1.1);
        t.MainToBackupUp = false;
        var id = t.Main.ForwardLive(new LiveCommand.StopAll())!.Value;
        t.Tick(0.4);
        Assert.Equal("missing", t.Main.LiveDelivery(id));
    }

    [Fact]
    public void NotLinkedReturnsNullAndInvalidIsRefused()
    {
        Assert.Null(t.Main.ForwardLive(new LiveCommand.Play()));
        t.Connect();
        Assert.Null(t.Main.ForwardLive(new LiveCommand.FireScene(10_000)));
    }

    [Fact]
    public void BackupTellsWhetherItsLiveAnswers()
    {
        t.Connect(); t.Tick(1.1);
        Assert.Null(t.Main.PeerLiveConnected);   // not told yet
        t.Backup.SetLiveConnected(true); t.Tick(1.1);
        Assert.True(t.Main.PeerLiveConnected);
        t.Backup.SetLiveConnected(false); t.Tick(1.1);
        Assert.False(t.Main.PeerLiveConnected);
    }

    [Fact]
    public void MixerChangesMadeWhileUnlinkedReachTheBackupLater()
    {
        var ran = new List<LiveCommand>();
        t.Backup.OnLiveCommand = ran.Add;
        t.Connect(); t.Tick(1.1);
        t.MainToBackupUp = false; t.BackupToMainUp = false;
        t.Tick(8);
        Assert.Null(t.Main.PeerLiveConnected);
        Assert.Null(t.Main.ForwardLive(new LiveCommand.SetVolume(1, 0.5)));
        Assert.Null(t.Main.ForwardLive(new LiveCommand.SetVolume(1, 0.6)));   // only the newest counts
        Assert.Null(t.Main.ForwardLive(new LiveCommand.SetTempo(128)));
        Assert.Null(t.Main.ForwardLive(new LiveCommand.FireScene(3)));        // never launched late
        t.MainToBackupUp = true; t.BackupToMainUp = true;
        t.Tick(8);
        Assert.Equal(new HashSet<LiveCommand> { new LiveCommand.SetVolume(1, 0.6), new LiveCommand.SetTempo(128) }, ran.ToHashSet());
    }

    [Fact]
    public void BackupLearnsTheMainsIPhones()
    {
        t.Connect(); t.Tick(1.1);
        Assert.Null(t.Backup.PeerRemoteSummary);
        t.Main.SetRemoteSummary(new RemoteSummary(2, WatchLevel.Reachable)); t.Pump();
        Assert.Equal(new RemoteSummary(2, WatchLevel.Reachable), t.Backup.PeerRemoteSummary);
        t.Main.SetRemoteSummary(new RemoteSummary(0, WatchLevel.Absent)); t.Tick(1.1);
        Assert.Equal(new RemoteSummary(0, WatchLevel.Absent), t.Backup.PeerRemoteSummary);
    }

    [Fact]
    public void ComputersCompareTheirSets()
    {
        t.Main.SetLocalSet(new SetSummary(Enumerable.Range(0, 12).Select(i => $"T{i}"), Enumerable.Range(0, 10).Select(i => $"S{i}")));
        t.Backup.SetLocalSet(new SetSummary(Enumerable.Range(0, 11).Select(i => $"T{i}"), Enumerable.Range(0, 10).Select(i => i == 6 ? "S6 v2" : $"S{i}")));
        t.Connect();
        t.Tick(6);   // enough heartbeats for 21 names at 8 per heartbeat
        var d = t.Main.SetDifference;
        Assert.NotNull(d);
        Assert.True(d.Complete);
        Assert.Equal(2, d.Differences);   // track 11 missing on the backup, scene 6 renamed
        Assert.Equal(11, d.BackupTracks);
        Assert.Equal(2, t.Backup.SetDifference?.Differences);
        t.Backup.SetLocalSet(new SetSummary(Enumerable.Range(0, 12).Select(i => $"T{i}"), Enumerable.Range(0, 10).Select(i => $"S{i}")));
        t.Tick(2);
        Assert.Null(t.Main.SetDifference);
    }

    [Fact]
    public void SetDiffRules()
    {
        var a = new SetSummary(["Music", "SE"], ["1 Intro", "2 Main"]);
        var p = new PeerSet();
        p.Summary(2, 2, a.Hash);
        Assert.Null(SetDiff.Compare(a, p));
        Assert.Null(SetDiff.Compare(a, null));

        var main = new SetSummary(["Music", "SE", "FX"], ["1 Intro", "2 Main"]);
        var backup = new SetSummary(["Music", "SE"], ["1 Intro", "2 Main v2"]);
        var q = new PeerSet();
        q.Summary(2, 2, backup.Hash);
        for (int i = 0; i < backup.Tracks.Count; i++) q.Item(SetItemKind.Track, i, backup.Tracks[i]);
        for (int i = 0; i < backup.Scenes.Count; i++) q.Item(SetItemKind.Scene, i, backup.Scenes[i]);
        var d = SetDiff.Compare(main, q)!;
        Assert.True(d.Complete);
        Assert.Equal(2, d.Differences);
        Assert.Equal([new SetDiff.Row("track", 2, "FX", null), new SetDiff.Row("scene", 1, "2 Main", "2 Main v2")], d.Rows);

        // Names still arriving are not counted as different.
        var r = new PeerSet();
        r.Summary(2, 1, 12345);
        var e = SetDiff.Compare(new SetSummary(["A", "B"], ["S"]), r)!;
        Assert.False(e.Complete);
        Assert.Equal(0, e.Differences);

        // Long names are cut the same way on both sides.
        var longName = new string('あ', 40);   // 120 bytes
        var l = new SetSummary([longName], []);
        Assert.True(System.Text.Encoding.UTF8.GetByteCount(l.Tracks[0]) <= SetSummary.MaxNameBytes);
        Assert.Equal(l.Hash, new SetSummary([longName + "x"], []).Hash);
    }

    [Fact]
    public void BridgeMessagesBuildTheState()
    {
        var s = new LiveState();
        s.Apply(J("""{"type":"song","tempo":124.0,"playing":true,"beat":"17.3.1","selected_scene":2,"tracks":2,"scenes":3,"bridge_version":3}"""));
        s.Apply(J("""{"type":"scenes","start":0,"items":[{"index":0,"name":"Intro","color":"#FF0000"},{"index":2,"name":"M1","playing":true}]}"""));
        s.Apply(J("""{"type":"tracks","start":0,"master":{"volume":0.8},"items":[{"index":1,"name":"SE","volume":0.6,"mute":true,"sends":[0.2,"x",0.5]}]}"""));
        s.Apply(J("""{"type":"clips","track":1,"items":[{"scene":2,"has_clip":true,"name":"Applause","is_playing":true,"length_beats":16.0}]}"""));
        s.Apply(J("""{"type":"progress","items":[[1,10.0,16.0]]}"""));
        Assert.Equal(124, s.Song.Tempo);
        Assert.True(s.Song.Playing);
        Assert.Equal("17.3.1", s.Song.Beat);
        Assert.Equal(3, s.Song.BridgeVersion);
        Assert.Equal(["Intro", "", "M1"], s.Scenes.Select(x => x.Name));
        Assert.Equal(2, s.Tracks.Count);
        Assert.True(s.Tracks[1].Mute);
        Assert.Equal([0.2], s.Tracks[1].SendList);   // stops at the first entry that is not a number
        Assert.Equal(0.8, s.Master.Volume);
        Assert.Equal("Applause", s.Clips[1][2].Name);
        Assert.False(s.Clips[1][0].HasClip);
        Assert.Null(s.Apply(J("""{"type":"bogus"}""")));
        Assert.Null(s.Apply(J("""{"type":"clips","track":-5,"items":[]}""")));
        // A track and a scene are deleted in Live: the next song message carries the new counts.
        var u = s.Apply(J("""{"type":"song","tempo":120,"tracks":1,"scenes":2,"structure":7}"""));
        Assert.IsType<LiveUpdate.Song>(u);
        Assert.Equal(7, s.Song.Structure);
        Assert.Single(s.Tracks);
        Assert.Equal(2, s.Scenes.Count);
        Assert.Equal(["Intro", ""], SetSummary.Of(s).Scenes);
    }

    [Fact]
    public void BridgeJsonCarriesStructure()
    {
        var a = JsonNode.Parse(new LiveCommand.FireClip(1, 2).BridgeJsonBytes(3, 9))!;
        Assert.Equal("fire_clip", (string)a["cmd"]!);
        Assert.Equal(9, (int)a["structure"]!);
        Assert.Equal(3, (int)a["id"]!);
        var b = JsonNode.Parse(new LiveCommand.Play().BridgeJsonBytes(3))!.AsObject();
        Assert.False(b.ContainsKey("structure"));
        var c = JsonNode.Parse(new LiveCommand.SetMute(2, true).BridgeJsonBytes(4))!;
        Assert.True((bool)c["on"]!);
        Assert.False(new LiveCommand.SetTempo(120).TargetsLayout);
        Assert.True(new LiveCommand.SelectScene(1).TargetsLayout);
    }
}
