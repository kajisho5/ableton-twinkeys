namespace TwinKeys.Core;

/// <summary>A MIDI message TwinKeys can produce. Channels are 0-based (0 = MIDI channel 1).</summary>
public readonly record struct MidiMessage(bool IsNoteOn, byte Channel, byte Note, byte Velocity)
{
    public static MidiMessage NoteOn(byte channel, byte note, byte velocity) => new(true, channel, note, velocity);
    public static MidiMessage NoteOff(byte channel, byte note) => new(false, channel, note, 0);

    /// <summary>MIDI 1.0 bytes (status, data1, data2).</summary>
    public byte[] Bytes => IsNoteOn
        ? [(byte)(0x90 | (Channel & 0x0F)), (byte)(Note & 0x7F), (byte)(Velocity & 0x7F)]
        : [(byte)(0x80 | (Channel & 0x0F)), (byte)(Note & 0x7F), 0];

    /// <summary>"All Notes Off" (CC 123) for every channel, as raw MIDI 1.0 bytes.</summary>
    public static IReadOnlyList<byte[]> AllNotesOffBytes { get; } =
        Enumerable.Range(0, 16).Select(ch => new byte[] { (byte)(0xB0 | ch), 123, 0 }).ToArray();

    /// <summary>Note name in the convention where MIDI note 60 is "C3" (as the Mac version and Live show it).</summary>
    public static string NoteName(byte note)
    {
        string[] names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
        return $"{names[note % 12]}{note / 12 - 2}";
    }
}
