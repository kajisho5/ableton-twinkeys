namespace TwinKeys.Core.Tests;

public class SettingsTests : IDisposable
{
    readonly string dir = Path.Combine(Path.GetTempPath(), "twinkeys-tests-" + Guid.NewGuid().ToString("N"));
    public void Dispose() { try { Directory.Delete(dir, true); } catch (IOException) { } }

    [Fact]
    public void FirstRunWritesDefaultsAndKeepsInstanceId()
    {
        var store = new SettingsStore(dir);
        var (a, broken) = store.Load();
        Assert.Null(broken);
        Assert.True(File.Exists(store.SettingsFile));
        var (b, _) = store.Load();
        Assert.Equal(a.InstanceId, b.InstanceId);
        Assert.Equal(CueKey.Defaults, b.CueKeys);
    }

    [Fact]
    public void RoundTripKeepsEverything()
    {
        var s = new AppSettings
        {
            SendKeys = false, KeyCapture = false, AutoNoteOffSeconds = 5, MidiChannel = 3, Language = "ja",
            ManualAddress = "192.168.1.20", CueKeys = [CueKey.Make(KeyIds.Down, 37, "次のシーン")], BlockCueKeys = false,
            MidiMode = MidiOutputMode.BridgeOnly, MidiPortName = "TwinKeys A", FirstRunDone = true,
            LiveUserLibrary = @"D:\Music\Ableton\User Library",
        };
        var back = AppSettings.FromJson(s.ToJson())!;
        Assert.Equal(s.ToJson(), back.ToJson());
        Assert.Contains("\"sc:0x50:e\"", s.ToJson());
        Assert.Contains("次のシーン", s.ToJson());
        Assert.Equal(@"D:\Music\Ableton\User Library", back.LiveUserLibrary);
        Assert.Null(AppSettings.FromJson("{}")!.LiveUserLibrary);
    }

    [Fact]
    public void PartialAndBadValuesFallBackToDefaults()
    {
        var json = """{"cue_keys":[{"key":"sc:0x50:e","note":37},{"key":5},{"key":"sc:0x48:e","note":999},{"key":"sc:0x4d:e","label":"→","memo":"Go","note":39}],"midi_channel":"two","language":"fr","send_keys":false}""";
        var s = AppSettings.FromJson(json)!;
        Assert.Equal(new byte[] { 37, 39 }, s.CueKeys.Select(k => k.Note));
        Assert.Equal("↓", s.CueKeys[0].Label);
        Assert.Equal(1, s.MidiChannel);
        Assert.Equal("system", s.Language);
        Assert.False(s.SendKeys);
        Assert.True(s.BlockCueKeys);
        Assert.Equal(MidiOutputMode.Loopback, s.MidiMode);
        Assert.Equal("TwinKeys", s.MidiPortName);
    }

    [Fact]
    public void BrokenFileIsKeptAsBackup()
    {
        Directory.CreateDirectory(dir);
        var store = new SettingsStore(dir);
        File.WriteAllText(store.SettingsFile, "{ not json");
        var (s, broken) = store.Load();
        Assert.NotNull(broken);
        Assert.StartsWith("settings.broken-", broken);
        Assert.True(File.Exists(Path.Combine(dir, broken!)));
        Assert.Equal(CueKey.Defaults, s.CueKeys);
    }

    [Fact]
    public void InstanceIdIsWrittenLikeTheMac()
    {
        var s = new AppSettings { InstanceId = Guid.Parse("8f0c2b7e-4d3a-4b8e-9c11-2a6f5e0d9b34") };
        Assert.Contains("\"8F0C2B7E-4D3A-4B8E-9C11-2A6F5E0D9B34\"", s.ToJson());
    }
}

public class HotkeyTests
{
    [Fact]
    public void ParsesTheDefaults()
    {
        Assert.Equal((Hotkey.ModControl | Hotkey.ModAlt, (uint)'K'), Hotkey.Parse("Ctrl+Alt+K"));
        Assert.Equal((Hotkey.ModControl | Hotkey.ModAlt, (uint)'P'), Hotkey.Parse(" ctrl + alt + p "));
        Assert.Equal((Hotkey.ModControl | Hotkey.ModShift, 0x70u + 11), Hotkey.Parse("Ctrl+Shift+F12"));
        Assert.Null(Hotkey.Parse("K"));
        Assert.Null(Hotkey.Parse("Shift+K"));
        Assert.Null(Hotkey.Parse("Ctrl+Alt"));
        Assert.Null(Hotkey.Parse("Ctrl+Alt+K+L"));
        Assert.Null(Hotkey.Parse(""));
    }
}
