namespace TwinKeys.Core;

/// <summary>
/// System-wide shortcuts as text ("Ctrl+Alt+K") and as RegisterHotKey values (MOD_* flags and a
/// Windows virtual-key code). docs/design-windows.md 3.5.
/// </summary>
public static class Hotkey
{
    public const uint ModAlt = 0x1, ModControl = 0x2, ModShift = 0x4, ModWin = 0x8;

    /// <summary>Null when the text is not "modifiers + one key" with at least Ctrl, Alt or Win.</summary>
    public static (uint Modifiers, uint VirtualKey)? Parse(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        uint mods = 0;
        uint? vk = null;
        foreach (var raw in text.Split('+', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            switch (raw.ToUpperInvariant())
            {
                case "CTRL" or "CONTROL": mods |= ModControl; break;
                case "ALT": mods |= ModAlt; break;
                case "SHIFT": mods |= ModShift; break;
                case "WIN": mods |= ModWin; break;
                case var k when vk is null && Key(k) is uint v: vk = v; break;
                default: return null;
            }
        }
        if (vk is null || (mods & (ModControl | ModAlt | ModWin)) == 0) return null;
        return (mods, vk.Value);
    }

    private static uint? Key(string k)
    {
        if (k.Length == 1 && k[0] is >= 'A' and <= 'Z') return k[0];
        if (k.Length == 1 && k[0] is >= '0' and <= '9') return k[0];
        if (k.Length is 2 or 3 && k[0] == 'F' && int.TryParse(k[1..], out var n) && n is >= 1 and <= 24) return (uint)(0x70 + n - 1);
        return null;
    }
}
