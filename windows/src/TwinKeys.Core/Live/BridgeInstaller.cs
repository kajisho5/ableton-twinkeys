namespace TwinKeys.Core;

/// <summary>
/// Copies the TwinKeysBridge Remote Script from the app into Live's User Library ("Remote Scripts").
/// Port of LiveBridgeInstaller in Sources/TwinKeys/LiveBridgeClient.swift. The folder logic is here
/// (no Windows API), so it is tested on Linux with temporary folders.
///
/// Where Live looks on Windows (docs/design-windows.md 4.5): the User Library's "Remote Scripts"
/// folder, by default <c>Documents\Ableton\User Library\Remote Scripts</c>. That default is only
/// confirmed by third-party guides (Ableton's article could not be read), and the User Library can be
/// moved in Live's settings, so the person can choose another User Library folder.
/// </summary>
public sealed class BridgeInstaller
{
    public const string FolderName = "TwinKeysBridge";

    /// <summary>The Bridge files shipped with the app (a folder holding __init__.py, constants.py, …).</summary>
    public string Bundled { get; }
    /// <summary>The User Library folder (holds "Remote Scripts").</summary>
    public string UserLibrary { get; }

    public BridgeInstaller(string bundled, string userLibrary)
    {
        Bundled = bundled;
        UserLibrary = userLibrary;
    }

    /// <summary>The default User Library on Windows: Documents\Ableton\User Library (Documents may be redirected, e.g. to OneDrive).</summary>
    public static string DefaultUserLibrary(string documents) => Path.Combine(documents, "Ableton", "User Library");

    public string RemoteScripts => Path.Combine(UserLibrary, "Remote Scripts");
    public string Installed => Path.Combine(RemoteScripts, FolderName);
    public bool IsInstalled => File.Exists(Path.Combine(Installed, "__init__.py"));
    public bool HasBundled => File.Exists(Path.Combine(Bundled, "__init__.py"));

    /// <summary>BRIDGE_VERSION in a copy's constants.py (0 for copies older than 2.2, or none).</summary>
    public static int VersionOf(string folder)
    {
        string text;
        try { text = File.ReadAllText(Path.Combine(folder, "constants.py")); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return 0; }
        foreach (var raw in text.Split('\n'))
        {
            var line = raw.TrimEnd('\r');
            if (!line.StartsWith("BRIDGE_VERSION", StringComparison.Ordinal)) continue;
            var parts = line.Split('=');
            if (parts.Length == 2 && int.TryParse(parts[1].Trim(), out var v)) return v;
        }
        return 0;
    }

    public int BundledVersion => VersionOf(Bundled);
    public int InstalledVersion => VersionOf(Installed);

    /// <summary>A User Library exists at the chosen place (Live made it; we do not guess further).</summary>
    public bool UserLibraryExists => Directory.Exists(UserLibrary);

    /// <summary>
    /// An older copy is installed: replace it with the app's (only if one was installed before; nothing
    /// is installed without the person asking). Live uses it from its next start. True when replaced.
    /// </summary>
    public bool UpdateIfOutdated() => IsInstalled && HasBundled && InstalledVersion < BundledVersion && Install() is null;

    /// <summary>Installs or updates the script. Returns an error message, or null on success.</summary>
    public string? Install()
    {
        if (!HasBundled) return "The Bridge is not included in this build.";
        try
        {
            Directory.CreateDirectory(RemoteScripts);
            // Copy next to it first, then swap, so a failed copy never leaves half a script.
            var temp = Installed + ".new";
            if (Directory.Exists(temp)) Directory.Delete(temp, true);
            Directory.CreateDirectory(temp);
            foreach (var f in Directory.GetFiles(Bundled, "*.py"))
                File.Copy(f, Path.Combine(temp, Path.GetFileName(f)), true);
            if (Directory.Exists(Installed)) Directory.Delete(Installed, true);
            Directory.Move(temp, Installed);
            return null;
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            return e.Message;
        }
    }
}
