namespace TwinKeys.Core;

/// <summary>
/// A key that fires one fixed MIDI note (a "cue"). Port of CueKey in Sources/TwinKeysCore/CueKeys.swift.
/// <see cref="KeyCode"/> is a Windows key id (<see cref="KeyIds"/>: scan code + extended flag), not the
/// macOS key code: key codes never go on the wire, only notes, labels and memos do.
/// </summary>
public sealed record CueKey(ushort KeyCode, string Label, string Memo, byte Note)
{
    /// <summary>Cue notes are given out from C1 (36) upwards.</summary>
    public const byte FirstNote = 36;
    /// <summary>Every cue is sent at full velocity.</summary>
    public const byte Velocity = 127;
    /// <summary>Most bytes of a memo sent to the other computer (fits in one packet).</summary>
    public const int MaxMemoBytes = 60;
    public const int MaxLabelBytes = 12;

    public static CueKey Make(ushort keyCode, byte note, string memo = "", string? label = null) =>
        new(keyCode, label ?? KeyIds.Label(keyCode), memo, note);

    /// <summary>↑ ↓ ← → Space Enter Esc, as suggested for a new install (same notes as the Mac).</summary>
    public static IReadOnlyList<CueKey> Defaults { get; } =
    [
        Make(KeyIds.Up, 36), Make(KeyIds.Down, 37), Make(KeyIds.Left, 38), Make(KeyIds.Right, 39),
        Make(KeyIds.Space, 40), Make(KeyIds.Enter, 41), Make(KeyIds.Escape, 42),
    ];

    /// <summary>Adds keys that are not cue keys yet, each with the next free note. Stops when notes run out.</summary>
    public static List<CueKey> Adding(IEnumerable<ushort> codes, IEnumerable<CueKey> keys)
    {
        var outList = keys.ToList();
        foreach (var code in codes)
        {
            if (KeyIds.IsModifier(code) || outList.Any(k => k.KeyCode == code)) continue;
            if (FreeNote(outList) is not byte n) break;
            outList.Add(Make(code, n));
        }
        return outList;
    }

    /// <summary>The lowest note from <see cref="FirstNote"/> that no key uses (null when all are taken).</summary>
    public static byte? FreeNote(IEnumerable<CueKey> keys)
    {
        var used = keys.Select(k => k.Note).ToHashSet();
        for (int n = FirstNote; n <= 127; n++) if (!used.Contains((byte)n)) return (byte)n;
        return null;
    }

    /// <summary>Keeps only usable entries: no duplicate key or note, note in range, texts cut to their byte limits.</summary>
    public static List<CueKey> Sanitized(IEnumerable<CueKey> keys)
    {
        var seenKeys = new HashSet<ushort>();
        var seenNotes = new HashSet<byte>();
        var outList = new List<CueKey>();
        foreach (var k in keys)
        {
            if (k.Note >= 128 || seenKeys.Contains(k.KeyCode) || seenNotes.Contains(k.Note)) continue;
            if (KeyIds.IsModifier(k.KeyCode)) continue;
            seenKeys.Add(k.KeyCode); seenNotes.Add(k.Note);
            var label = Utf8Text.TruncateString(k.Label ?? "", MaxLabelBytes);
            if (label.Length == 0) label = KeyIds.Label(k.KeyCode);
            outList.Add(k with { Label = label, Memo = Utf8Text.TruncateString(k.Memo ?? "", MaxMemoBytes) });
        }
        return outList;
    }
}

/// <summary>
/// Windows key ids: the keyboard scan code (set 1) of a key, with 0xE000 added for extended keys
/// (the arrows, Home, the right Ctrl…). The scan code names a key position, not a character, so a
/// cue key is the same key on a JIS and on a US keyboard, as on the Mac (docs/design-windows.md 5.2).
/// In settings.json a key is written as "sc:0x48:e" (extended) or "sc:0x39".
/// </summary>
public static class KeyIds
{
    public const ushort ExtendedFlag = 0xE000;
    public const ushort Escape = 0x01, Enter = 0x1C, Space = 0x39, Tab = 0x0F, Backspace = 0x0E;
    public const ushort Up = 0xE048, Down = 0xE050, Left = 0xE04B, Right = 0xE04D;
    public const ushort Delete = 0xE053, Home = 0xE047, End = 0xE04F, PageUp = 0xE049, PageDown = 0xE051, Insert = 0xE052;
    public const ushort NumpadEnter = 0xE01C;

    public static ushort Make(uint scanCode, bool extended) => (ushort)((extended ? (uint)ExtendedFlag : 0u) | (scanCode & 0xFFu));
    public static byte ScanCode(ushort id) => (byte)(id & 0xFF);
    public static bool IsExtended(ushort id) => (id & ExtendedFlag) == ExtendedFlag;

    private static readonly Dictionary<ushort, string> Table = new()
    {
        [Up] = "↑", [Down] = "↓", [Left] = "←", [Right] = "→",
        [Space] = "Space", [Enter] = "Enter", [Escape] = "Esc", [Tab] = "Tab", [Backspace] = "Backspace",
        [Delete] = "Del", [Insert] = "Ins", [Home] = "Home", [End] = "End", [PageUp] = "Page Up", [PageDown] = "Page Down",
        [NumpadEnter] = "Num Enter", [0xE035] = "Num /", [0xE037] = "PrtSc", [0xE05D] = "Menu",
        [0x3B] = "F1", [0x3C] = "F2", [0x3D] = "F3", [0x3E] = "F4", [0x3F] = "F5", [0x40] = "F6",
        [0x41] = "F7", [0x42] = "F8", [0x43] = "F9", [0x44] = "F10", [0x57] = "F11", [0x58] = "F12",
        [0x64] = "F13", [0x65] = "F14", [0x66] = "F15", [0x67] = "F16", [0x68] = "F17", [0x69] = "F18",
        [0x6A] = "F19", [0x6B] = "F20",
        [0x1E] = "A", [0x30] = "B", [0x2E] = "C", [0x20] = "D", [0x12] = "E", [0x21] = "F", [0x22] = "G", [0x23] = "H",
        [0x17] = "I", [0x24] = "J", [0x25] = "K", [0x26] = "L", [0x32] = "M", [0x31] = "N", [0x18] = "O", [0x19] = "P",
        [0x10] = "Q", [0x13] = "R", [0x1F] = "S", [0x14] = "T", [0x16] = "U", [0x2F] = "V", [0x11] = "W", [0x2D] = "X",
        [0x15] = "Y", [0x2C] = "Z",
        [0x02] = "1", [0x03] = "2", [0x04] = "3", [0x05] = "4", [0x06] = "5", [0x07] = "6", [0x08] = "7", [0x09] = "8",
        [0x0A] = "9", [0x0B] = "0",
        // Labels of the US layout; on a JIS keyboard the same positions carry other symbols.
        [0x0C] = "-", [0x0D] = "=", [0x1A] = "[", [0x1B] = "]", [0x2B] = "\\", [0x27] = ";", [0x28] = "'", [0x29] = "`",
        [0x33] = ",", [0x34] = ".", [0x35] = "/",
        [0x47] = "Num 7", [0x48] = "Num 8", [0x49] = "Num 9", [0x4A] = "Num -", [0x4B] = "Num 4", [0x4C] = "Num 5",
        [0x4D] = "Num 6", [0x4E] = "Num +", [0x4F] = "Num 1", [0x50] = "Num 2", [0x51] = "Num 3", [0x52] = "Num 0",
        [0x53] = "Num .", [0x37] = "Num *",
        // Keys only on a JIS keyboard.
        [0x7D] = "¥", [0x73] = "_", [0x70] = "かな", [0x79] = "変換", [0x7B] = "無変換",
    };

    /// <summary>Ctrl, Shift, Alt, the Windows keys and Caps Lock cannot be cue keys.</summary>
    public static bool IsModifier(ushort id) =>
        id is 0x1D or 0xE01D or 0x2A or 0x36 or 0x38 or 0xE038 or 0xE05B or 0xE05C or 0x3A or 0xE02A or 0xE036;

    public static string Label(ushort id) =>
        Table.TryGetValue(id, out var s) ? s : $"Key {(IsExtended(id) ? "E0" : "")}{ScanCode(id):X2}";

    /// <summary>Letters A–Z and digits 0–9 (by key position), for adding them in one go.</summary>
    public static IReadOnlyList<ushort> Alphanumeric { get; } =
    [
        0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26, 0x32,
        0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C,
        0x0B, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A,
    ];

    /// <summary>"sc:0x48:e" for an extended key, "sc:0x39" otherwise.</summary>
    public static string ToSetting(ushort id) => $"sc:0x{ScanCode(id):x2}{(IsExtended(id) ? ":e" : "")}";

    public static ushort? FromSetting(string? s)
    {
        if (s is null || !s.StartsWith("sc:0x", StringComparison.OrdinalIgnoreCase)) return null;
        var parts = s.Split(':');
        if (parts.Length is < 2 or > 3) return null;
        if (!byte.TryParse(parts[1].AsSpan(2), System.Globalization.NumberStyles.HexNumber, null, out var sc) || sc == 0) return null;
        bool ext = parts.Length == 3;
        if (ext && parts[2] != "e") return null;
        return Make(sc, ext);
    }
}
