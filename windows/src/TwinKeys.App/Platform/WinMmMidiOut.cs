using System.Collections.Concurrent;
using System.Runtime.InteropServices;
using TwinKeys.Core;
using static TwinKeys.App.Platform.NativeMethods;

namespace TwinKeys.App.Platform;

/// <summary>
/// Method M1 (docs/design-windows.md 4.3): sends cue notes with WinMM to the loopback MIDI port the
/// person created and named "TwinKeys" (Windows MIDI Services loopback or loopMIDI). Live reads the
/// other end of the loopback as its MIDI input. TwinKeys never creates a port itself.
///
/// Messages are queued and sent from a dedicated thread (the keyboard hook never waits for MIDI).
/// While the port is missing it is looked for again every 3 s, so creating it later just works.
/// </summary>
internal sealed class WinMmMidiOut : IMidiOutput, IDisposable
{
    public abstract record Status
    {
        private Status() { }
        public sealed record Ready(string PortName) : Status;
        public sealed record NotFound(string Wanted) : Status;
        public sealed record Off : Status;
        public sealed record Error(string Text) : Status;
    }

    private readonly BlockingCollection<byte[]> queue = new(boundedCapacity: 4096);
    private readonly Thread thread;
    private readonly object gate = new();
    private nint handle;
    private string wanted;
    private bool enabled = true;
    private DateTime nextLook = DateTime.MinValue;
    private volatile Status status;
    public Action<string>? Log { get; set; }

    public WinMmMidiOut(string portName)
    {
        wanted = portName;
        status = new Status.NotFound(portName);
        thread = new Thread(Run) { IsBackground = true, Name = "TwinKeys MIDI out", Priority = ThreadPriority.Highest };
        thread.Start();
    }

    public Status Current => status;

    /// <summary>Names of all MIDI outputs WinMM shows (for the settings and the first-run screen).</summary>
    public static List<string> OutputNames()
    {
        var list = new List<string>();
        uint n = midiOutGetNumDevs();
        for (uint i = 0; i < n; i++)
        {
            var caps = new MIDIOUTCAPSW();
            if (midiOutGetDevCapsW(i, ref caps, (uint)Marshal.SizeOf<MIDIOUTCAPSW>()) == MMSYSERR_NOERROR) list.Add(caps.szPname ?? "");
        }
        return list;
    }

    /// <summary>The output to use for <paramref name="wanted"/>: the same name first, then a name starting with it.</summary>
    public static int? FindPort(IReadOnlyList<string> names, string wanted)
    {
        for (int i = 0; i < names.Count; i++) if (string.Equals(names[i].Trim(), wanted, StringComparison.OrdinalIgnoreCase)) return i;
        for (int i = 0; i < names.Count; i++) if (names[i].StartsWith(wanted, StringComparison.OrdinalIgnoreCase)) return i;
        return null;
    }

    public void SetPort(string portName, bool on)
    {
        lock (gate)
        {
            wanted = portName;
            enabled = on;
            CloseLocked();
            nextLook = DateTime.MinValue;
            status = on ? new Status.NotFound(portName) : new Status.Off();
        }
    }

    /// <summary>Look for the port now (for example after the person created it).</summary>
    public void Rescan()
    {
        lock (gate) { if (handle == 0) nextLook = DateTime.MinValue; }
        queue.TryAdd([]);
    }

    public void Send(byte[] bytes)
    {
        if (bytes.Length == 3) queue.TryAdd(bytes);
    }

    private void Run()
    {
        while (!queue.IsCompleted)
        {
            byte[]? m = null;
            try { queue.TryTake(out m, 1000); } catch (ObjectDisposedException) { return; } catch (InvalidOperationException) { return; }
            lock (gate)
            {
                EnsureOpenLocked();
                if (m is not { Length: 3 } || handle == 0) continue;
                uint msg = (uint)(m[0] | (m[1] << 8) | (m[2] << 16));
                uint r = midiOutShortMsg(handle, msg);
                if (r != MMSYSERR_NOERROR)
                {
                    Log?.Invoke($"MIDI send failed (error {r}); looking for the port again");
                    CloseLocked();
                    status = new Status.Error($"MMSYSERR {r}");
                    nextLook = DateTime.UtcNow;
                }
            }
        }
    }

    private void EnsureOpenLocked()
    {
        if (!enabled || handle != 0 || DateTime.UtcNow < nextLook) return;
        nextLook = DateTime.UtcNow.AddSeconds(3);
        var names = OutputNames();
        if (FindPort(names, wanted) is not int index)
        {
            if (status is not Status.NotFound) Log?.Invoke($"MIDI output \"{wanted}\" not found (outputs: {string.Join(", ", names)})");
            status = new Status.NotFound(wanted);
            return;
        }
        uint r = midiOutOpen(out var h, (uint)index, 0, 0, CALLBACK_NULL);
        if (r != MMSYSERR_NOERROR)
        {
            status = new Status.Error($"midiOutOpen {r}");
            Log?.Invoke($"MIDI output \"{names[index]}\" could not be opened (error {r})");
            return;
        }
        handle = h;
        status = new Status.Ready(names[index]);
        Log?.Invoke($"MIDI output: {names[index]}");
    }

    private void CloseLocked()
    {
        if (handle == 0) return;
        midiOutReset(handle);
        midiOutClose(handle);
        handle = 0;
    }

    public void Dispose()
    {
        queue.CompleteAdding();
        thread.Join(TimeSpan.FromSeconds(1));
        lock (gate) CloseLocked();
    }
}
