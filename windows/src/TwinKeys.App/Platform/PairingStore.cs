using System.Runtime.InteropServices;
using System.Text;
using static TwinKeys.App.Platform.NativeMethods;

namespace TwinKeys.App.Platform;

/// <summary>
/// Keeps the pairing code encrypted with DPAPI for this Windows user (the Mac keeps it in the
/// keychain; settings.json never holds it). The environment variable TWINKEYS_PAIRING_CODE overrides
/// it, as on the Mac (for automated tests).
/// </summary>
internal sealed class PairingStore(string directory)
{
    private string FilePath => Path.Combine(directory, "pairing.dat");

    public static string? EnvironmentCode => Environment.GetEnvironmentVariable("TWINKEYS_PAIRING_CODE");

    public string? Load()
    {
        if (EnvironmentCode is string env) return env;
        try
        {
            if (!File.Exists(FilePath)) return null;
            var plain = Unprotect(File.ReadAllBytes(FilePath));
            return plain is null ? null : Encoding.UTF8.GetString(plain);
        }
        catch (IOException) { return null; }
    }

    public bool Save(string? code)
    {
        try
        {
            if (code is null) { File.Delete(FilePath); return true; }
            Directory.CreateDirectory(directory);
            var data = Protect(Encoding.UTF8.GetBytes(code));
            if (data is null) return false;
            File.WriteAllBytes(FilePath, data);
            return true;
        }
        catch (IOException) { return false; }
        catch (UnauthorizedAccessException) { return false; }
    }

    private static byte[]? Protect(byte[] plain) => Transform(plain, protect: true);
    private static byte[]? Unprotect(byte[] data) => Transform(data, protect: false);

    private static unsafe byte[]? Transform(byte[] input, bool protect)
    {
        fixed (byte* p = input)
        {
            var inBlob = new DATA_BLOB { cbData = (uint)input.Length, pbData = (nint)p };
            DATA_BLOB outBlob;
            bool ok = protect
                ? CryptProtectData(in inBlob, "TwinKeys pairing code", 0, 0, 0, CRYPTPROTECT_UI_FORBIDDEN, out outBlob)
                : CryptUnprotectData(in inBlob, 0, 0, 0, 0, CRYPTPROTECT_UI_FORBIDDEN, out outBlob);
            if (!ok) return null;
            try
            {
                var result = new byte[outBlob.cbData];
                Marshal.Copy(outBlob.pbData, result, 0, result.Length);
                return result;
            }
            finally
            {
                LocalFree(outBlob.pbData);
            }
        }
    }
}
