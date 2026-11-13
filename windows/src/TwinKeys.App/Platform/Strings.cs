using System.Globalization;
using System.Xml.Linq;

namespace TwinKeys.App.Platform;

/// <summary>
/// The window texts in Japanese and English, read from Strings/ja-JP/Resources.resw and
/// Strings/en-US/Resources.resw (embedded in the app). Read by hand rather than with the resource
/// loader so the language can change at once, like the Mac's "Same as System / English / 日本語".
/// </summary>
internal sealed class Strings
{
    private static readonly Dictionary<string, string> En = Load("Strings.en.resw");
    private static readonly Dictionary<string, string> Ja = Load("Strings.ja.resw");
    public static Strings Current { get; private set; } = new("en");

    public string Language { get; }
    public bool IsJapanese => Language == "ja";
    private readonly Dictionary<string, string> map;

    private Strings(string lang)
    {
        Language = lang;
        map = lang == "ja" ? Ja : En;
    }

    /// <summary>"system", "en" or "ja".</summary>
    public static void Use(string setting)
    {
        var lang = setting switch
        {
            "ja" => "ja",
            "en" => "en",
            _ => CultureInfo.CurrentUICulture.TwoLetterISOLanguageName == "ja" ? "ja" : "en",
        };
        Current = new Strings(lang);
    }

    public string this[string key] => map.TryGetValue(key, out var v) ? v : En.TryGetValue(key, out var e) ? e : key;

    public string F(string key, params object[] args) => string.Format(CultureInfo.InvariantCulture, this[key], args);

    private static Dictionary<string, string> Load(string resource)
    {
        var d = new Dictionary<string, string>();
        using var s = typeof(Strings).Assembly.GetManifestResourceStream(resource);
        if (s is null) return d;
        var doc = XDocument.Load(s);
        foreach (var e in doc.Root!.Elements("data"))
        {
            var name = (string?)e.Attribute("name");
            var value = (string?)e.Element("value");
            if (name is not null && value is not null) d[name] = value;
        }
        return d;
    }
}
