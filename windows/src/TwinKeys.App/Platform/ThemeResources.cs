using System.Xml.Linq;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Markup;

namespace TwinKeys.App.Platform;

/// <summary>
/// Makes sure the app's resources (the WinUI control styles and TwinKeys' colours and styles from
/// App.xaml) are present before any window loads. On the CI runners the unpackaged, self-contained
/// app came up with an empty Application.Resources, so every window failed with "Cannot find a
/// Resource with the Name/Key TkWindowBackground". If that happens, the same dictionary is read
/// from the copy of App.xaml embedded in the app and added in code.
/// </summary>
internal static class ThemeResources
{
    public static string Ensure(Application app)
    {
        var res = app.Resources;
        var notes = new List<string>();
        if (!res.MergedDictionaries.OfType<XamlControlsResources>().Any())
        {
            res.MergedDictionaries.Insert(0, new XamlControlsResources());
            notes.Add("control styles added in code");
        }
        if (!res.ContainsKey("TkCritical"))
        {
            using var s = typeof(ThemeResources).Assembly.GetManifestResourceStream("Xaml.App.xaml")
                ?? throw new FileNotFoundException("App.xaml copy");
            var dict = XDocument.Load(s).Descendants().First(e => e.Name.LocalName == "ResourceDictionary");
            // The control styles are added above; only TwinKeys' own resources are read here.
            dict.Elements().FirstOrDefault(e => e.Name.LocalName == "ResourceDictionary.MergedDictionaries")?.Remove();
            res.MergedDictionaries.Add((ResourceDictionary)XamlReader.Load(dict.ToString()));
            notes.Add("TwinKeys resources added in code");
        }
        return notes.Count == 0 ? "resources from App.xaml" : string.Join(", ", notes);
    }
}
