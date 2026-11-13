using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using TwinKeys.Core;
using static TwinKeys.App.Platform.NativeMethods;

namespace TwinKeys.App.Platform;

/// <summary>
/// Advertises the iPhone remote server (phase 3) with DNS-SD as <c>_twinkeys-remote._tcp</c>, the
/// service TwinKeys Remote looks for (the Mac's NWListener.Service, no TXT record). Same Windows API
/// as <see cref="DnsSdDiscovery"/>. Whether an iPhone finds it on a real network is checked with a
/// real iPhone and PC (docs/design-windows.md 14).
/// </summary>
internal sealed unsafe class RemoteAdvertiser : IDisposable
{
    private readonly object gate = new();
    private DNS_SERVICE_REGISTER_REQUEST* request;
    private bool disposed;
    public Action<string>? Log { get; set; }

    /// <summary>Advertises (again) with this name and TCP port; null port stops advertising.</summary>
    public void Advertise(string name, ushort? port)
    {
        lock (gate)
        {
            if (disposed) return;
            StopLocked();
            if (port is not ushort p) return;
            var label = Utf8Text.TruncateString(name.Replace('.', '-').Trim() is { Length: > 0 } n ? n : "TwinKeys PC", 63);
            var instance = label + "." + RemoteProtocol.ServiceType + ".local";
            var host = Environment.MachineName + ".local";
            DNS_SERVICE_INSTANCE* inst;
            try { inst = DnsServiceConstructInstance(instance, host, null, null, p, 0, 0, 0, null, null); }
            catch (Exception e) when (e is DllNotFoundException or EntryPointNotFoundException) { Log?.Invoke("Remote: mDNS is not available: " + e.Message); return; }
            if (inst is null) { Log?.Invoke("Remote: could not build the mDNS record"); return; }
            request = (DNS_SERVICE_REGISTER_REQUEST*)NativeMemory.AllocZeroed((nuint)sizeof(DNS_SERVICE_REGISTER_REQUEST));
            request->Version = DNS_QUERY_REQUEST_VERSION1;
            request->pServiceInstance = inst;
            request->pRegisterCompletionCallback = &Done;
            uint r = DnsServiceRegister(request, null);
            Log?.Invoke(r == DNS_REQUEST_PENDING ? $"Remote: advertising \"{instance}\" on TCP port {p}" : $"Remote: mDNS advertising failed (status {r})");
        }
    }

    private void StopLocked()
    {
        if (request is null) return;
        DnsServiceDeRegister(request, null);
        // The request stays allocated: Windows may still use it until its callback (small, once per change).
        request = null;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)])]
    private static void Done(uint status, nint context, DNS_SERVICE_INSTANCE* instance)
    {
        if (instance is not null) DnsServiceFreeInstance(instance);
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            StopLocked();
            disposed = true;
        }
    }
}
