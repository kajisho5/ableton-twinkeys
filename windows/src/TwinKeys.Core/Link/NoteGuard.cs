namespace TwinKeys.Core;

/// <summary>
/// Tracks notes sent to the MIDI output so they can be turned off automatically if their
/// note-off never arrives, and on All Notes Off (port of NoteGuard.swift).
/// </summary>
public sealed class NoteGuard(double timeout, double minimumTimeout = 0)
{
    public readonly record struct Key(byte Channel, byte Note) : IComparable<Key>
    {
        public int CompareTo(Key other) => Channel != other.Channel ? Channel.CompareTo(other.Channel) : Note.CompareTo(other.Note);
    }

    /// <summary>Seconds after note-on before an automatic note-off. 0 or less disables it.</summary>
    public double Timeout { get; set; } = timeout;
    /// <summary>Lower bound for the effective timeout when enabled (the peer's guard uses 3 s).</summary>
    public double MinimumTimeout { get; set; } = minimumTimeout;
    private readonly Dictionary<Key, double> active = [];
    public IReadOnlyDictionary<Key, double> Active => active;

    private double EffectiveTimeout => Math.Max(Timeout, MinimumTimeout);

    public void Record(MidiMessage m, double now)
    {
        var k = new Key(m.Channel, m.Note);
        if (m.IsNoteOn && m.Velocity > 0) active[k] = now;
        else active.Remove(k);
    }

    /// <summary>Restarts the timer of a note that is known to be still held on purpose.</summary>
    public void Touch(byte channel, byte note, double now)
    {
        var k = new Key(channel, note);
        if (active.ContainsKey(k)) active[k] = now;
    }

    /// <summary>Note-offs for notes held longer than the timeout (removed from tracking). Notes in <paramref name="keep"/> are left alone.</summary>
    public List<MidiMessage> Expire(double now, ISet<Key>? keep = null)
    {
        if (Timeout <= 0) return [];
        double limit = EffectiveTimeout;
        var old = active.Where(kv => now - kv.Value >= limit && (keep is null || !keep.Contains(kv.Key))).Select(kv => kv.Key).Order().ToList();
        foreach (var k in old) active.Remove(k);
        return old.Select(k => MidiMessage.NoteOff(k.Channel, k.Note)).ToList();
    }

    /// <summary>Note-offs for everything still sounding; clears tracking.</summary>
    public List<MidiMessage> ReleaseAll()
    {
        var all = active.Keys.Order().ToList();
        active.Clear();
        return all.Select(k => MidiMessage.NoteOff(k.Channel, k.Note)).ToList();
    }
}
