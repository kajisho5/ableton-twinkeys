using System.Xml.Linq;
using Microsoft.UI.Xaml.Markup;

namespace TwinKeys.App.Platform;

/// <summary>
/// CI only (--smoke-windows): loads each window's XAML again with XamlReader, which reports the
/// line and position of an error (the compiled windows only say "XAML parsing failed").
/// </summary>
internal static class XamlCheck
{
    public static void Run(Action<string> log)
    {
        foreach (var name in new[] { "MainWindow", "SettingsWindow", "FirstRunWindow" })
        {
            try
            {
                using var s = typeof(XamlCheck).Assembly.GetManifestResourceStream($"Xaml.{name}.xaml")
                    ?? throw new FileNotFoundException(name);
                var root = XDocument.Load(s).Root!.Elements().First();
                foreach (var el in root.DescendantsAndSelf())
                    foreach (var a in el.Attributes().ToList())
                        if (a.Name.LocalName is "Click" or "Toggled" or "SelectionChanged") a.Remove();
                XamlReader.Load(root.ToString());
                log($"XAML check {name}: ok");
            }
            catch (Exception e)
            {
                log($"XAML check {name}: {e.GetType().Name}: {e.Message}");
            }
        }
        foreach (var snippet in new[]
        {
            "<Grid Background=\"{ThemeResource TkWindowBackground}\" />",
            "<Border Style=\"{StaticResource TkCardStyle}\" />",
            "<TextBlock Style=\"{StaticResource TkHint}\" />",
            "<StackPanel Orientation=\"Horizontal\" Spacing=\"1.6\"><Rectangle Width=\"4.4\" Height=\"10\" RadiusX=\"1\" RadiusY=\"1\" Fill=\"{ThemeResource TkOnAccent}\" /></StackPanel>",
            "<NavigationView PaneDisplayMode=\"Left\" IsBackButtonVisible=\"Collapsed\" IsSettingsVisible=\"False\" IsPaneToggleButtonVisible=\"False\" OpenPaneLength=\"220\" />",
        })
        {
            try
            {
                XamlReader.Load(FirstSpaceNs(snippet));
                log($"XAML snippet ok: {snippet}");
            }
            catch (Exception e)
            {
                log($"XAML snippet failed: {snippet}: {e.Message}");
            }
        }
    }

    private static string FirstSpaceNs(string s)
    {
        int i = s.IndexOf(' ');
        return s[..i] + " xmlns=\"http://schemas.microsoft.com/winfx/2006/xaml/presentation\"" + s[i..];
    }
}
