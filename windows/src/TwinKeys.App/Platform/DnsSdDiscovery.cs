using System.Net;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using TwinKeys.Core;
using static TwinKeys.App.Platform.NativeMethods;

namespace TwinKeys.App.Platform;

/// <summary>
/// Finds other TwinKeys computers and advertises this one with mDNS / DNS-SD, the same service the
/// Mac's Bonjour uses (<c>_twinkeys._udp</c>, TXT id / v / modes / boot, plus os=win from Windows;
/// docs/design-windows.md 3.1 and 6.1). Uses the Windows DNS-SD API (DnsServiceRegister,
/// DnsServiceBrowse, DnsServiceResolve; Windows 10 1809 and later).
///
/// The browse is restarted every 30 s and a computer not seen for 90 s is dropped (a goodbye with TTL 0
/// drops it at once). Whether Windows and macOS find each other on a real network is checked on real
/// computers (docs/design-windows.md 9.3, R4); "Connect by IP Address" works without any of this.
/// </summary>
internal sealed unsafe class DnsSdDiscovery : IDisposable
{
    private sealed class Entry
    {
        public PeerInfo? Peer;
        public IPEndPoint? EndPoint;
        public DateTime SeenAt;
        public DateTime ResolvedAt;
        public bool Resolving;
    }

    private sealed class ResolveOp
    {
        public required DnsSdDiscovery Owner;
        public required string Instance;
        public DNS_SERVICE_RESOLVE_REQUEST* Request;
        public DNS_SERVICE_CANCEL* Cancel;
        public nint Name;
        public GCHandle Handle;
    }

    private const string Suffix = "." + TxtKeys.ServiceType + ".local";
    private readonly object gate = new();
    private readonly string ownId;
    private readonly Dictionary<string, Entry> entries = [];
    private GCHandle self;
    private Timer? timer;
    private DateTime browseStartedAt = DateTime.MinValue;
    private bool disposed;

    // Advertisement.
    private DNS_SERVICE_REGISTER_REQUEST* registerRequest;
    private readonly List<nint> registerStrings = [];
    // Browse.
    private DNS_SERVICE_BROWSE_REQUEST* browseRequest;
    private DNS_SERVICE_CANCEL* browseCancel;
    private nint browseName;
    private bool browsing;

    public string OwnBoot { get; } = Guid.NewGuid().ToString("D").ToUpperInvariant();
    public Action<string>? Log { get; set; }
    /// <summary>The visible peers changed (called on a thread-pool thread).</summary>
    public Action<IReadOnlyList<PeerInfo>>? PeersChanged { get; set; }
    /// <summary>A peer's address (null: no longer seen). Feeds <see cref="UdpTransport.SetDiscovered"/>.</summary>
    public Action<string, IPEndPoint?>? EndPointChanged { get; set; }
    /// <summary>Another running TwinKeys uses our instance ID (copied settings).</summary>
    public Action? DuplicateId { get; set; }

    public DnsSdDiscovery(string ownId)
    {
        this.ownId = ownId;
        self = GCHandle.Alloc(this);
    }

    public IReadOnlyList<PeerInfo> Peers
    {
        get { lock (gate) return entries.Values.Where(e => e.Peer is not null).Select(e => e.Peer!).DistinctBy(p => p.Id).OrderBy(p => p.Name).ToList(); }
    }

    public bool IsVisible(string peerId)
    {
        lock (gate) return entries.Values.Any(e => e.Peer?.Id == peerId);
    }

    public void Start()
    {
        StartBrowse();
        timer = new Timer(_ => Maintain(), null, TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));
    }

    // MARK: Advertising

    /// <summary>Advertises (again) with the current name, port and modes.</summary>
    public void Advertise(string name, ushort port, bool sends, bool receives)
    {
        lock (gate)
        {
            if (disposed) return;
            StopAdvertisingLocked();
            var instance = SafeLabel(name) + Suffix;
            var host = Environment.MachineName + ".local";
            string[] keys = [TxtKeys.Id, TxtKeys.Version, TxtKeys.Modes, TxtKeys.Boot, TxtKeys.Os];
            string[] values = [ownId, WireProtocol.Version.ToString(), TxtKeys.ModesValue(sends, receives), OwnBoot, "win"];
            var keyArray = (char**)Marshal.AllocHGlobal(sizeof(nint) * keys.Length);
            var valueArray = (char**)Marshal.AllocHGlobal(sizeof(nint) * keys.Length);
            registerStrings.Add((nint)keyArray);
            registerStrings.Add((nint)valueArray);
            for (int i = 0; i < keys.Length; i++)
            {
                var k = Marshal.StringToHGlobalUni(keys[i]);
                var v = Marshal.StringToHGlobalUni(values[i]);
                registerStrings.Add(k); registerStrings.Add(v);
                keyArray[i] = (char*)k;
                valueArray[i] = (char*)v;
            }
            var inst = DnsServiceConstructInstance(instance, host, null, null, port, 0, 0, (uint)keys.Length, keyArray, valueArray);
            if (inst is null) { Log?.Invoke("mDNS: could not build the service record"); return; }
            registerRequest = (DNS_SERVICE_REGISTER_REQUEST*)NativeMemory.AllocZeroed((nuint)sizeof(DNS_SERVICE_REGISTER_REQUEST));
            registerRequest->Version = DNS_QUERY_REQUEST_VERSION1;
            registerRequest->InterfaceIndex = 0;
            registerRequest->pServiceInstance = inst;
            registerRequest->pRegisterCompletionCallback = &RegisterDone;
            registerRequest->pQueryContext = GCHandle.ToIntPtr(self);
            uint r = DnsServiceRegister(registerRequest, null);
            Log?.Invoke(r == DNS_REQUEST_PENDING ? $"mDNS: advertising \"{instance}\" on UDP port {port}" : $"mDNS: advertising failed (status {r})");
        }
    }

    private void StopAdvertisingLocked()
    {
        if (registerRequest is null) return;
        DnsServiceDeRegister(registerRequest, null);
        // The request and the strings stay allocated: Windows may still use them until its callback (small, once per change).
        registerRequest = null;
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)])]
    private static void RegisterDone(uint status, nint context, DNS_SERVICE_INSTANCE* instance)
    {
        try
        {
            if (GCHandle.FromIntPtr(context).Target is DnsSdDiscovery d && status != 0) d.Log?.Invoke($"mDNS: registration finished with status {status}");
        }
        catch { }
        if (instance is not null) DnsServiceFreeInstance(instance);
    }

    /// <summary>DNS-SD instance names: no dots, at most 63 bytes.</summary>
    private static string SafeLabel(string name)
    {
        var s = name.Replace('.', '-').Trim();
        if (s.Length == 0) s = "TwinKeys PC";
        return Utf8Text.TruncateString(s, 63);
    }

    // MARK: Browsing

    private void StartBrowse()
    {
        lock (gate)
        {
            if (disposed) return;
            if (browsing) { DnsServiceBrowseCancel(browseCancel); browsing = false; }
            if (browseRequest is null)
            {
                browseRequest = (DNS_SERVICE_BROWSE_REQUEST*)NativeMemory.AllocZeroed((nuint)sizeof(DNS_SERVICE_BROWSE_REQUEST));
                browseCancel = (DNS_SERVICE_CANCEL*)NativeMemory.AllocZeroed((nuint)sizeof(DNS_SERVICE_CANCEL));
                browseName = Marshal.StringToHGlobalUni(TxtKeys.ServiceType + ".local");
            }
            browseRequest->Version = DNS_QUERY_REQUEST_VERSION1;
            browseRequest->InterfaceIndex = 0;
            browseRequest->QueryName = (char*)browseName;
            browseRequest->pBrowseCallback = &BrowseCallback;
            browseRequest->pQueryContext = GCHandle.ToIntPtr(self);
            uint r = DnsServiceBrowse(browseRequest, browseCancel);
            browsing = r == DNS_REQUEST_PENDING;
            browseStartedAt = DateTime.UtcNow;
            if (!browsing) Log?.Invoke($"mDNS: browsing failed (status {r})");
        }
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)])]
    private static void BrowseCallback(uint status, nint context, DNS_RECORD* records)
    {
        try
        {
            if (GCHandle.FromIntPtr(context).Target is DnsSdDiscovery d && status == 0)
                for (var r = records; r is not null; r = r->pNext)
                    if (r->wType == DNS_TYPE_PTR && r->pNameHost is not null) d.Seen(new string(r->pNameHost), r->dwTtl);
        }
        catch { }
        finally
        {
            if (records is not null) DnsRecordListFree(records, 1);
        }
    }

    private void Seen(string instance, uint ttl)
    {
        if (!instance.EndsWith(Suffix, StringComparison.OrdinalIgnoreCase) && !instance.EndsWith(Suffix + ".", StringComparison.OrdinalIgnoreCase)) return;
        bool changed = false;
        bool resolve = false;
        lock (gate)
        {
            if (ttl == 0)
            {
                if (entries.Remove(instance, out var gone))
                {
                    changed = gone.Peer is not null;
                    if (gone.Peer is not null) EndPointChanged?.Invoke(gone.Peer.Id, null);
                }
            }
            else
            {
                if (!entries.TryGetValue(instance, out var e)) entries[instance] = e = new Entry();
                e.SeenAt = DateTime.UtcNow;
                if (!e.Resolving && DateTime.UtcNow - e.ResolvedAt > TimeSpan.FromSeconds(25)) { e.Resolving = true; resolve = true; }
            }
        }
        if (resolve) Resolve(instance);
        if (changed) PeersChanged?.Invoke(Peers);
    }

    private void Resolve(string instance)
    {
        var op = new ResolveOp { Owner = this, Instance = instance };
        op.Handle = GCHandle.Alloc(op);
        op.Request = (DNS_SERVICE_RESOLVE_REQUEST*)NativeMemory.AllocZeroed((nuint)sizeof(DNS_SERVICE_RESOLVE_REQUEST));
        op.Cancel = (DNS_SERVICE_CANCEL*)NativeMemory.AllocZeroed((nuint)sizeof(DNS_SERVICE_CANCEL));
        op.Name = Marshal.StringToHGlobalUni(instance);
        op.Request->Version = DNS_QUERY_REQUEST_VERSION1;
        op.Request->InterfaceIndex = 0;
        op.Request->QueryName = (char*)op.Name;
        op.Request->pResolveCompletionCallback = &ResolveDone;
        op.Request->pQueryContext = GCHandle.ToIntPtr(op.Handle);
        uint r = DnsServiceResolve(op.Request, op.Cancel);
        if (r != DNS_REQUEST_PENDING)
        {
            Log?.Invoke($"mDNS: resolving {instance} failed (status {r})");
            Finish(op);
            lock (gate) if (entries.TryGetValue(instance, out var e)) e.Resolving = false;
        }
    }

    private static void Finish(ResolveOp op)
    {
        // The request memory is released a little later: Windows may still be returning from the callback.
        var (req, cancel, name) = ((nint)op.Request, (nint)op.Cancel, op.Name);
        if (op.Handle.IsAllocated) op.Handle.Free();
        _ = Task.Delay(TimeSpan.FromSeconds(5)).ContinueWith(_ =>
        {
            NativeMemory.Free((void*)req);
            NativeMemory.Free((void*)cancel);
            Marshal.FreeHGlobal(name);
        }, TaskScheduler.Default);
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvStdcall)])]
    private static void ResolveDone(uint status, nint context, DNS_SERVICE_INSTANCE* instance)
    {
        try
        {
            if (GCHandle.FromIntPtr(context).Target is ResolveOp op)
            {
                op.Owner.Resolved(op.Instance, status, instance);
                Finish(op);
            }
        }
        catch { }
        finally
        {
            if (instance is not null) DnsServiceFreeInstance(instance);
        }
    }

    private void Resolved(string instance, uint status, DNS_SERVICE_INSTANCE* inst)
    {
        PeerInfo? peer = null;
        IPEndPoint? ep = null;
        string? host = null;
        bool duplicate = false;
        if (status == 0 && inst is not null)
        {
            var txt = new Dictionary<string, string>();
            for (uint i = 0; i < inst->dwPropertyCount; i++)
            {
                if (inst->keys[i] is null) continue;
                txt[new string(inst->keys[i])] = inst->values[i] is null ? "" : new string(inst->values[i]);
            }
            duplicate = TxtKeys.IsDuplicateOfUs(txt, ownId, OwnBoot);
            peer = TxtKeys.Peer(txt, DisplayName(instance), ownId);
            if (inst->ip4Address is not null) ep = new IPEndPoint(new IPAddress(*inst->ip4Address), inst->wPort);
            else if (inst->ip6Address is not null) ep = new IPEndPoint(new IPAddress(new ReadOnlySpan<byte>(inst->ip6Address, 16), inst->dwInterfaceIndex), inst->wPort);
            if (inst->pszHostName is not null) host = new string(inst->pszHostName);
            if (ep is null && host is not null && peer is not null) ResolveHostLater(instance, host, inst->wPort);
        }
        if (duplicate) DuplicateId?.Invoke();
        lock (gate)
        {
            if (!entries.TryGetValue(instance, out var e)) return;
            e.Resolving = false;
            e.ResolvedAt = DateTime.UtcNow;
            if (peer is null) return;
            e.Peer = peer;
            if (ep is not null) e.EndPoint = ep;
        }
        if (ep is not null) EndPointChanged?.Invoke(peer!.Id, ep);
        PeersChanged?.Invoke(Peers);
    }

    /// <summary>No address in the answer: ask Windows for the host name (it resolves .local names with mDNS).</summary>
    private void ResolveHostLater(string instance, string host, ushort port)
    {
        HostLookup.Start(host, a =>
        {
            string? id;
            lock (gate)
            {
                if (!entries.TryGetValue(instance, out var e) || e.Peer is null) return;
                e.EndPoint = new IPEndPoint(a, port);
                id = e.Peer.Id;
            }
            EndPointChanged?.Invoke(id, new IPEndPoint(a, port));
        }, err => Log?.Invoke($"mDNS: could not resolve {host}: {err}"));
    }

    /// <summary>"Stage PC._twinkeys._udp.local" -> "Stage PC" (DNS escapes such as \032 decoded).</summary>
    internal static string DisplayName(string instance)
    {
        var s = instance.TrimEnd('.');
        if (s.EndsWith(Suffix, StringComparison.OrdinalIgnoreCase)) s = s[..^Suffix.Length];
        s = Regex.Replace(s, @"\\(\d{3})", m => ((char)int.Parse(m.Groups[1].Value)).ToString());
        return s.Replace("\\.", ".").Replace("\\\\", "\\");
    }

    private void Maintain()
    {
        if (disposed) return;
        var now = DateTime.UtcNow;
        var gone = new List<string>();
        List<string> stale = [];
        lock (gate)
        {
            foreach (var (name, e) in entries.ToList())
            {
                if (now - e.SeenAt > TimeSpan.FromSeconds(90))
                {
                    entries.Remove(name);
                    if (e.Peer is not null) gone.Add(e.Peer.Id);
                }
                else if (!e.Resolving && now - e.ResolvedAt > TimeSpan.FromSeconds(60))
                {
                    e.Resolving = true;
                    stale.Add(name);
                }
            }
        }
        foreach (var id in gone) EndPointChanged?.Invoke(id, null);
        if (gone.Count > 0) PeersChanged?.Invoke(Peers);
        foreach (var name in stale) Resolve(name);
        if (now - browseStartedAt > TimeSpan.FromSeconds(30)) StartBrowse();
    }

    public void Dispose()
    {
        lock (gate)
        {
            if (disposed) return;
            disposed = true;
            timer?.Dispose();
            StopAdvertisingLocked();
            if (browsing) DnsServiceBrowseCancel(browseCancel);
            browsing = false;
        }
    }
}

/// <summary>Host name lookup off the DNS-SD callback thread (kept out of the unsafe class: no await there).</summary>
internal static class HostLookup
{
    public static void Start(string host, Action<IPAddress> found, Action<string> failed)
    {
        _ = Task.Run(async () =>
        {
            try
            {
                var addrs = await Dns.GetHostAddressesAsync(host.TrimEnd('.'));
                var a = addrs.FirstOrDefault(x => x.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork) ?? addrs.FirstOrDefault();
                if (a is not null) found(a);
            }
            catch (Exception e) { failed(e.Message); }
        });
    }
}
