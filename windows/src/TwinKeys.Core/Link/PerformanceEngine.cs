namespace TwinKeys.Core;

/// <summary>Modifier keys held at the time of a key event (Command = the Windows key).</summary>
[Flags]
public enum Modifiers : byte { None = 0, Shift = 1, Control = 2, Alt = 4, Command = 8 }

/// <summary>One raw key event from the keyboard hook. <paramref name="KeyCode"/> is a <see cref="KeyIds"/> value.</summary>
public readonly record struct KeyInput(ushort KeyCode, bool IsDown, bool IsRepeat = false, Modifiers Modifiers = Modifiers.None);

/// <summary>
/// Turns presses of cue keys into note on/off messages (port of PerformanceEngine.swift). Every
/// cue key sends one fixed note at full velocity on <see cref="Channel"/>. Not thread-safe.
/// </summary>
public sealed class PerformanceEngine
{
    public byte Channel { get; set; }
    private Dictionary<ushort, CueKey> cueKeys = [];
    /// <summary>keycode -> note currently sounding for that key.</summary>
    private readonly Dictionary<ushort, byte> held = [];

    public PerformanceEngine(IEnumerable<CueKey>? keys = null, byte channel = 0)
    {
        Channel = channel;
        SetCueKeys(keys ?? CueKey.Defaults);
    }

    public IReadOnlyDictionary<ushort, CueKey> CueKeys => cueKeys;
    public IReadOnlyDictionary<ushort, byte> Held => held;
    public List<byte> HeldNotes => held.Values.Order().ToList();

    /// <summary>Replaces the cue keys. Returns note-offs for keys still held.</summary>
    public List<MidiMessage> SetCueKeys(IEnumerable<CueKey> keys)
    {
        var offs = ReleaseAll();
        cueKeys = [];
        foreach (var k in CueKey.Sanitized(keys)) cueKeys.TryAdd(k.KeyCode, k);
        return offs;
    }

    public bool IsCueKey(ushort keyCode) => cueKeys.ContainsKey(keyCode);

    /// <summary>Handles one key event; returns the MIDI messages with the cue key each belongs to.</summary>
    public List<(MidiMessage Message, CueKey? Cue)> HandleEvents(KeyInput input)
    {
        if (input.IsDown)
        {
            if (!cueKeys.TryGetValue(input.KeyCode, out var cue)) return [];
            // Key repeat is never a new press; keys with Ctrl, Alt, Shift or Windows are shortcuts, not cues.
            if (input.IsRepeat || input.Modifiers != Modifiers.None || held.ContainsKey(input.KeyCode)) return [];
            held[input.KeyCode] = cue.Note;
            return [(MidiMessage.NoteOn(Channel, cue.Note, CueKey.Velocity), cue)];
        }
        // A release always ends the note, even if the key was removed from the list meanwhile.
        if (held.Remove(input.KeyCode, out var note))
            return [(MidiMessage.NoteOff(Channel, note), cueKeys.GetValueOrDefault(input.KeyCode))];
        return [];
    }

    public List<MidiMessage> Handle(KeyInput input) => HandleEvents(input).Select(e => e.Message).ToList();

    /// <summary>Ends one sounding note as if its key had been released (key-up never seen).</summary>
    public List<MidiMessage> Release(byte note)
    {
        foreach (var kv in held)
        {
            if (kv.Value != note) continue;
            held.Remove(kv.Key);
            return [MidiMessage.NoteOff(Channel, note)];
        }
        return [];
    }

    /// <summary>Releases every held note (capture turned off, panic, etc.).</summary>
    public List<MidiMessage> ReleaseAll()
    {
        var offs = held.Values.Order().Select(n => MidiMessage.NoteOff(Channel, n)).ToList();
        held.Clear();
        return offs;
    }
}
