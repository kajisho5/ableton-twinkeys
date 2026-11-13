using System.Text;
using System.Text.Json.Nodes;

namespace TwinKeys.Interop.Tests;

/// <summary>shared/test-vectors/remote.json (phase 3): the iPhone link, as the Mac's Swift code makes it.</summary>
public class RemoteVectorTests
{
    static JsonObject F => SharedVectorTests.LoadFile("remote.json");
    static byte[] H(JsonNode? n) => Convert.FromHexString((string)n!);
    static string Hex(byte[] b) => Convert.ToHexStringLower(b);

    [Fact]
    public void KeysTagsAndCodeMatch()
    {
        var f = F;
        var secret = PairingSecret.FromCode((string)f["pairing_code"]!)!;
        var dev = H(f["device_private"]);
        var eph = H(f["ephemeral_private"]);
        Assert.Equal((string)f["device_public"]!, Hex(Curve25519.PublicKey(dev)));
        Assert.Equal((string)f["ephemeral_public"]!, Hex(Curve25519.PublicKey(eph)));
        Assert.Equal((string)f["shared"]!, Hex(Curve25519.Shared(eph, Curve25519.PublicKey(dev))));
        Assert.Equal((string)f["shared"]!, Hex(Curve25519.Shared(dev, Curve25519.PublicKey(eph))));

        // The computer's side: the iPhone's hello is accepted and gives the same 4 digits.
        var server = RemoteSession.Server(secret, eph);
        var events = server.Receive(H(f["client_hello_frame"]));
        var hello = Assert.IsType<RemoteSession.Event.ClientHello>(Assert.Single(events));
        Assert.Equal((string)f["confirm_code"]!, hello.ConfirmCode);
        Assert.Equal("Stage iPhone", hello.Hello.DeviceName);
        Assert.Equal(H(f["device_public"]), hello.Hello.DevicePublicKey);
        var chb = Encoding.UTF8.GetBytes((string)f["client_hello_json"]!);
        Assert.Equal((string)f["client_tag"]!, Hex(server.Tag(chb)));
        Assert.Equal((string)f["server_tag"]!, Hex(server.Tag([.. chb, .. Encoding.UTF8.GetBytes((string)f["server_hello_json"]!)])));
        Assert.Equal((string)f["confirm_code"]!, RemoteSession.ConfirmCode(chb));

        // The iPhone's side (the tests' fake iPhone) with the Mac's server hello: the same session keys.
        var client = RemoteSession.Client(secret, dev);
        client.UseClientHello(chb);
        var ev = client.Receive(H(f["server_hello_frame"]));
        Assert.IsType<RemoteSession.Event.ServerHello>(Assert.Single(ev));
        Assert.Equal((string)f["key_c2s"]!, Hex(client.Keys!.Value.C2S));
        Assert.Equal((string)f["key_s2c"]!, Hex(client.Keys!.Value.S2C));

        // Sealed frames: the client seals what the Mac would open, and opens what the Mac sealed.
        foreach (var s in f["sealed"]!.AsArray())
        {
            var plain = Encoding.UTF8.GetBytes((string)s!["plain"]!);
            if ((string)s["direction"]! == "c2s")
                Assert.Equal((string)s["frame"]!, Hex(client.SealJson(plain)));
            else
                Assert.IsType<RemoteSession.Event.Message>(Assert.Single(client.Receive(H(s["frame"]))));
        }
        // A wrong pairing code is refused at the first frame.
        var wrong = RemoteSession.Server(PairingSecret.FromCode("Z3H8N-RT4QW")!);
        Assert.Equal("wrongPairingCode", Assert.Throws<RemoteException>(() => wrong.Receive(H(f["client_hello_frame"]))).Reason);
    }

    /// <summary>What the computer sends is what the Mac sends; what the iPhone sends is read.</summary>
    [Fact]
    public void MessagesHaveTheSwiftShape()
    {
        var expected = new Dictionary<string, RemoteMessage>
        {
            ["command"] = new RemoteMessage.Command(1, new LiveCommand.FireScene(3)),
            ["command_fireClip"] = new RemoteMessage.Command(2, new LiveCommand.FireClip(1, 2)),
            ["commandAt"] = new RemoteMessage.CommandAt(3, new LiveCommand.SetVolume(-1, 0.5), 42),
            ["commandAt_no_structure"] = new RemoteMessage.CommandAt(4, new LiveCommand.StopAll(), null),
            ["commandAt_setSend"] = new RemoteMessage.CommandAt(5, new LiveCommand.SetSend(2, 1, 0.25), 7),
            ["command_setMute"] = new RemoteMessage.Command(6, new LiveCommand.SetMute(0, true)),
            ["command_setTempo"] = new RemoteMessage.Command(7, new LiveCommand.SetTempo(128.5)),
            ["command_continuePlaying"] = new RemoteMessage.Command(8, new LiveCommand.ContinuePlaying()),
            ["go"] = new RemoteMessage.Go(9, 4, 42),
            ["lockScope"] = new RemoteMessage.LockScopeMsg(true, 19),
            ["becomeMain"] = new RemoteMessage.BecomeMain(10),
            ["cue"] = new RemoteMessage.Cue(11, 336),
            ["allNotesOff"] = new RemoteMessage.AllNotesOff(12),
            ["ping"] = new RemoteMessage.Ping(12.5),
            ["ping_watch"] = new RemoteMessage.Ping(13.25, new RemoteWatchState(true, true, false)),
            ["lock"] = new RemoteMessage.Lock(true),
            ["waitingForApproval"] = new RemoteMessage.WaitingForApproval("0427"),
            ["denied"] = new RemoteMessage.Denied(),
            ["result"] = new RemoteMessage.Result(1, true, null, "delivered"),
            ["result_error"] = new RemoteMessage.Result(2, false, "structure_changed", "notSent"),
            ["pong"] = new RemoteMessage.Pong(12.5),
        };
        var built = Built();
        int checkedCount = 0;
        foreach (var v in F["messages"]!.AsArray())
        {
            string name = (string)v!["name"]!;
            var swift = v["message"];
            RemoteMessage? mine = expected.GetValueOrDefault(name) ?? built.GetValueOrDefault(name);
            Assert.True(mine is not null, "no C# value for " + name);
            Assert.True(SharedVectorTests.SameJson(swift, mine!.ToJson()), $"{name}: C# {mine.ToJson().ToJsonString()} / Swift {swift!.ToJsonString()}");
            if (expected.ContainsKey(name) && name != "welcome")
                Assert.Equal(mine, RemoteMessage.FromJson(swift));
            checkedCount++;
        }
        Assert.Equal(expected.Count + built.Count, checkedCount);
        Assert.Null(RemoteMessage.FromJson(JsonNode.Parse("""{"someFutureKind":{"x":1}}""")));
        Assert.Null(RemoteMessage.FromJson(JsonNode.Parse("""{"command":{"id":1,"_1":{"teleport":{}}}}""")));
    }

    /// <summary>The messages with Live state and status, built from the same values as the Swift test.</summary>
    static Dictionary<string, RemoteMessage> Built()
    {
        var bridge = new LiveState();
        bridge.Apply((JsonObject)JsonNode.Parse("""{"type":"song","tempo":124.5,"playing":true,"beat":"17.3.1","selected_track":1,"selected_scene":2,"set_name":"","tracks":2,"scenes":3,"structure":42,"bridge_version":3}""")!);
        bridge.Apply((JsonObject)JsonNode.Parse("""{"type":"scenes","items":[{"index":0,"name":"1 Intro","color":"#FF3A34","triggered":false,"playing":true},{"index":1,"name":"2 本編","color":"#888888","triggered":true,"playing":false}]}""")!);
        bridge.Apply((JsonObject)JsonNode.Parse("""{"type":"tracks","master":{"volume":0.75,"pan":0},"items":[{"index":0,"name":"Music","color":"#1A2B3C","volume":0.75,"pan":0,"mute":false,"solo":false,"playing_slot":0,"fired_slot":-1,"sends":[0.5,0.25]},{"index":1,"name":"SE","color":"#888888","volume":0.5,"pan":-0.25,"mute":true,"solo":false,"playing_slot":-1,"fired_slot":-1,"sends":[]}]}""")!);
        bridge.Apply((JsonObject)JsonNode.Parse("""{"type":"clips","track":0,"items":[{"scene":0,"has_clip":true,"name":"Opening","color":"#FFA500","is_playing":true,"is_triggered":false,"length_beats":16},{"scene":1,"has_clip":false,"name":"","color":"#888888","is_playing":false,"is_triggered":false,"length_beats":0}]}""")!);
        bridge.Apply((JsonObject)JsonNode.Parse("""{"type":"clips","track":1,"items":[]}""")!);
        bridge.Apply((JsonObject)JsonNode.Parse("""{"type":"meters","items":[[0,0.5,0.25]],"master":[0.75,0.5]}""")!);
        bridge.Apply((JsonObject)JsonNode.Parse("""{"type":"progress","items":[[0,4,16]]}""")!);
        var diff = new SetDiff(2, 1, 3, 3, 2, [new SetDiff.Row("track", 1, "SE", null), new SetDiff.Row("scene", 1, "2 本編", "2 Main")], true);
        var status = new RemoteStatus("Stage PC", true, "Backup Stage Mac", true, false, 1.5, new RemoteStatus.CueSummary("↓", "次のシーン", 12, "delivered"),
            [new RemoteStatus.CueKeySummary(336, "↓", "次のシーン"), new RemoteStatus.CueKeySummary(328, "↑", "")], diff);
        return new Dictionary<string, RemoteMessage>
        {
            ["welcome"] = new RemoteMessage.Welcome("Stage PC", RemoteFeature.All),
            ["update_song"] = new RemoteMessage.Update(new LiveUpdate.Song(bridge.Song)),
            ["update_scenes"] = new RemoteMessage.Update(new LiveUpdate.Scenes(bridge.Scenes)),
            ["update_tracks"] = new RemoteMessage.Update(new LiveUpdate.Tracks(bridge.Tracks, bridge.Master)),
            ["update_clips"] = new RemoteMessage.Update(new LiveUpdate.Clips(0, bridge.Clips[0])),
            ["update_meters"] = new RemoteMessage.Update(new LiveUpdate.Meters(new Dictionary<int, double[]> { [0] = [0.5, 0.25], [3] = [0.125, 0] }, [0.75, 0.5])),
            ["update_progress"] = new RemoteMessage.Update(new LiveUpdate.Progress(new Dictionary<int, double[]> { [1] = [4, 16] })),
            ["update_full"] = new RemoteMessage.Update(new LiveUpdate.Full(bridge)),
            ["status"] = new RemoteMessage.Status(status),
            ["status_minimal"] = new RemoteMessage.Status(new RemoteStatus("Stage PC", false, null, false, false, null, null, [])),
        };
    }
}
