using System.Text.RegularExpressions;
using System.Xml.Linq;

namespace TwinKeys.Core.Tests;

/// <summary>
/// The Windows app's texts (src/TwinKeys.App/Strings/*/Resources.resw): both languages have the same
/// keys and placeholders, and every key the app code uses exists. Runs on Linux (the app itself
/// only builds on Windows).
/// </summary>
public class StringsTests
{
    static string AppDir()
    {
        for (var d = new DirectoryInfo(AppContext.BaseDirectory); d is not null; d = d.Parent)
        {
            var p = Path.Combine(d.FullName, "src", "TwinKeys.App");
            if (Directory.Exists(p)) return p;
        }
        throw new DirectoryNotFoundException("src/TwinKeys.App");
    }

    static Dictionary<string, string> Load(string lang) =>
        XDocument.Load(Path.Combine(AppDir(), "Strings", lang, "Resources.resw")).Root!.Elements("data")
            .ToDictionary(e => (string)e.Attribute("name")!, e => (string)e.Element("value")!);

    static string Placeholders(string s) => string.Join(",", Regex.Matches(s, @"\{(\d+)\}").Select(m => m.Value).Distinct().Order());

    [Fact]
    public void JapaneseAndEnglishHaveTheSameKeysAndPlaceholders()
    {
        var ja = Load("ja-JP");
        var en = Load("en-US");
        Assert.Equal(en.Keys.Order(), ja.Keys.Order());
        foreach (var k in en.Keys) Assert.True(Placeholders(en[k]) == Placeholders(ja[k]), $"{k}: {en[k]} / {ja[k]}");
        foreach (var (k, v) in ja) Assert.False(string.IsNullOrWhiteSpace(v), k);
    }

    [Fact]
    public void EveryKeyTheAppUsesExists()
    {
        var en = Load("en-US");
        var used = new HashSet<string>();
        foreach (var file in Directory.EnumerateFiles(AppDir(), "*.cs", SearchOption.AllDirectories))
        {
            if (file.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}")) continue;
            var text = File.ReadAllText(file);
            foreach (Match m in Regex.Matches(text, @"(?:\bS|Strings\.Current)(?:\[""(\w+)""\]|\.F\(""(\w+)"")"))
                used.Add(m.Groups[1].Success ? m.Groups[1].Value : m.Groups[2].Value);
        }
        Assert.NotEmpty(used);
        var missing = used.Where(k => !en.ContainsKey(k)).Order().ToList();
        Assert.True(missing.Count == 0, "missing: " + string.Join(", ", missing));
    }

    [Fact]
    public void MockupTextsAreUsed()
    {
        var ja = Load("ja-JP");
        Assert.Equal("オールノートオフ", ja["AllNotesOff"]);
        Assert.Equal("{0} に接続済み", ja["ConnectedTo"]);
        Assert.Equal("バックアップに届きました", ja["DeliveredToBackup"]);
        Assert.Equal("キューのキーを、ほかのアプリに渡さない（おすすめ）", ja["BlockCueKeys"]);
        Assert.Equal("Live に音を届ける方法を選びます", ja["FirstRunHeading"]);
        Assert.Equal("サインイン時に起動", ja["StartAtSignIn"]);
    }
}
