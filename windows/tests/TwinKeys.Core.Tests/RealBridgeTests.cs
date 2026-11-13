using System.Diagnostics;

namespace TwinKeys.Core.Tests;

/// <summary>
/// The C# Bridge client against the real TwinKeysBridge script (LiveBridge/TwinKeysBridge) running
/// on the fake Live of its own tests (scripts/fake-live-bridge.py). Needs Python 3: set
/// TWINKEYS_PYTHON to the interpreter (CI does); skipped otherwise.
/// </summary>
public class RealBridgeTests
{
    internal static string RepoRoot()
    {
        var d = new DirectoryInfo(AppContext.BaseDirectory);
        while (d is not null && !Directory.Exists(Path.Combine(d.FullName, "LiveBridge", "TwinKeysBridge"))) d = d.Parent;
        return d?.FullName ?? throw new DirectoryNotFoundException("repository root (LiveBridge/) not found");
    }

    internal static string BridgeSource() => Path.Combine(RepoRoot(), "LiveBridge", "TwinKeysBridge");

    [Fact]
    public void ClientTalksToTheRealScript()
    {
        var python = Environment.GetEnvironmentVariable("TWINKEYS_PYTHON");
        if (string.IsNullOrEmpty(python)) Assert.Skip("TWINKEYS_PYTHON is not set");
        ushort cmdPort = BridgeClientTests.FreePort(), statePort = BridgeClientTests.FreePort();
        var psi = new ProcessStartInfo(python)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
        };
        foreach (var a in new[] { Path.Combine(RepoRoot(), "scripts", "fake-live-bridge.py"), "--command-port", $"{cmdPort}", "--state-port", $"{statePort}", "--tracks", "3", "--scenes", "4", "--seconds", "40" })
            psi.ArgumentList.Add(a);
        using var p = Process.Start(psi)!;
        var output = new List<string>();
        p.OutputDataReceived += (_, e) => { if (e.Data is not null) lock (output) output.Add(e.Data); };
        p.ErrorDataReceived += (_, e) => { if (e.Data is not null) lock (output) output.Add("err " + e.Data); };
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        string Out() { lock (output) return string.Join("\n", output); }
        try
        {
            Assert.True(BridgeClientTests.WaitFor(() => Out().Contains("ready"), 15), Out());
            using var client = new BridgeClient(cmdPort, statePort);
            client.Start();
            Assert.True(BridgeClientTests.WaitFor(() => client.IsConnected && client.Snapshot().Scenes.Count == 4 && client.Snapshot().Tracks.Count == 3, 15), Out());
            var live = client.Snapshot();
            Assert.Equal(["Track 0", "Track 1", "Track 2"], live.Tracks.Select(t => t.Name));
            Assert.Equal(["Scene 0", "Scene 1", "Scene 2", "Scene 3"], live.Scenes.Select(s => s.Name));
            Assert.Equal(BridgeInstaller.VersionOf(BridgeSource()), live.Song.BridgeVersion);
            Assert.NotNull(live.Song.Structure);

            (bool Ok, string? Err) Run(LiveCommand c, bool check = false)
            {
                (bool, string?)? r = null;
                client.Run(c, check, (ok, err) => r = (ok, err));
                Assert.True(BridgeClientTests.WaitFor(() => r is not null, 5));
                return r!.Value;
            }

            Assert.Equal((true, null), Run(new LiveCommand.Play()));
            Assert.Equal((true, null), Run(new LiveCommand.SetTempo(132.5)));
            Assert.Equal((true, null), Run(new LiveCommand.SelectScene(2), check: true));
            Assert.Equal((true, null), Run(new LiveCommand.FireClip(1, 3), check: true));
            Assert.Equal((true, null), Run(new LiveCommand.SetSend(0, 0, 0.5)));
            Assert.Equal((true, null), Run(new LiveCommand.SetMute(2, true)));
            // The script checks ranges too: a track that this set does not have.
            var bad = Run(new LiveCommand.StopTrack(7));
            Assert.False(bad.Ok);
            Assert.Contains("out of range", bad.Err);
            // Send B on a set with one return track.
            Assert.False(Run(new LiveCommand.SetSend(0, 1, 0.5)).Ok);
            Assert.True(BridgeClientTests.WaitFor(() =>
            {
                var s = client.Snapshot();
                return s.Song.Playing && Math.Abs(s.Song.Tempo - 132.5) < 1e-9 && s.Song.SelectedScene == 2 && s.Tracks[2].Mute;
            }, 5), Out());
            Assert.Contains("call start_playing", Out());
        }
        finally
        {
            try { p.Kill(); } catch (InvalidOperationException) { }
            p.WaitForExit(5000);
        }
    }
}
