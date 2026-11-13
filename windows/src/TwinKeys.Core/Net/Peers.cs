namespace TwinKeys.Core;

/// <summary>A TwinKeys instance found on the network (port of Peers.swift).</summary>
public sealed record PeerInfo(string Id, string Name, bool Sends, bool Receives, string? Version = null, string? Os = null)
{
    /// <summary>Prefix of placeholder peer IDs for connections made by IP address.</summary>
    public const string ManualPrefix = "manual:";

    /// <summary>False when the peer speaks another protocol version: connecting would never work.</summary>
    public bool IsCompatible => Version is null || Version == WireProtocol.Version.ToString();
}

/// <summary>Keys of the mDNS/Bonjour TXT record (service <c>_twinkeys._udp</c>).</summary>
public static class TxtKeys
{
    public const string ServiceType = "_twinkeys._udp";
    public const string Id = "id";
    public const string Version = "v";
    public const string Modes = "modes";
    /// <summary>Random per launch. Our own ID with another boot value means another computer copied our ID.</summary>
    public const string Boot = "boot";
    /// <summary>
    /// The OS (docs/design-windows.md 3.1): "win" from this app, "mac" from Macs with the os key
    /// (older Macs do not send it), so the window shows the other OS only when it is known.
    /// </summary>
    public const string Os = "os";

    public static string ModesValue(bool sends, bool receives) => (sends ? "s" : "") + (receives ? "r" : "");

    /// <summary>Builds a peer from a TXT record. Null for our own instance or a bad record.</summary>
    public static PeerInfo? Peer(IReadOnlyDictionary<string, string> txt, string serviceName, string ownId)
    {
        if (!txt.TryGetValue(Id, out var id) || id.Length == 0 || id == ownId) return null;
        var m = txt.GetValueOrDefault(Modes) ?? "";
        return new PeerInfo(id, serviceName, m.Contains('s'), m.Contains('r'), txt.GetValueOrDefault(Version), txt.GetValueOrDefault(Os));
    }

    /// <summary>True if the record carries our ID but comes from another running instance.</summary>
    public static bool IsDuplicateOfUs(IReadOnlyDictionary<string, string> txt, string ownId, string ownBoot) =>
        txt.GetValueOrDefault(Id) == ownId && txt.TryGetValue(Boot, out var b) && b != ownBoot;
}

/// <summary>
/// A typed address for "Connect by IP Address": "192.168.1.20", "192.168.1.20:47802",
/// "fe80::1%12" or "[fe80::1%12]:47802". The port defaults to TwinKeys' fixed port 47801.
/// </summary>
public static class ManualAddress
{
    public const ushort DefaultPort = 47801;

    public static (string Host, ushort Port)? Parse(string raw)
    {
        var s = raw.Trim();
        if (s.Length == 0) return null;
        if (s.StartsWith('['))
        {
            int close = s.IndexOf(']');
            if (close < 0) return null;
            var host = s[1..close];
            var rest = s[(close + 1)..];
            if (rest.Length == 0) return host.Length == 0 ? null : (host, DefaultPort);
            if (!rest.StartsWith(':') || !ushort.TryParse(rest[1..], out var p) || p == 0 || host.Length == 0) return null;
            return (host, p);
        }
        if (s.Count(c => c == ':') > 1) return (s, DefaultPort);
        int colon = s.IndexOf(':');
        if (colon >= 0)
        {
            var host = s[..colon];
            if (!ushort.TryParse(s[(colon + 1)..], out var p) || p == 0 || host.Length == 0) return null;
            return (host, p);
        }
        return (s, DefaultPort);
    }
}
