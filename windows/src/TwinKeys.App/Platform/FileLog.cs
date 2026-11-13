namespace TwinKeys.App.Platform;

/// <summary>A daily log file in %LOCALAPPDATA%\TwinKeys\Logs (key names only, never what is typed).</summary>
internal sealed class FileLog(string directory)
{
    private readonly object gate = new();

    public string Directory => directory;

    public void Write(string line)
    {
        var now = DateTime.Now;
        var text = $"{now:yyyy-MM-dd HH:mm:ss.fff} {line}{Environment.NewLine}";
        lock (gate)
        {
            try
            {
                System.IO.Directory.CreateDirectory(directory);
                File.AppendAllText(Path.Combine(directory, $"TwinKeys-{now:yyyyMMdd}.log"), text);
            }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
        }
        System.Diagnostics.Debug.WriteLine(text);
    }
}
