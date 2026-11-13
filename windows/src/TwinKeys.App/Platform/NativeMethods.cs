using System.Runtime.InteropServices;

namespace TwinKeys.App.Platform;

/// <summary>
/// The Win32 functions TwinKeys calls (written by hand instead of CsWin32 so there is no extra
/// package; docs/design-windows.md 2.4). Each block names its documentation page.
/// </summary>
internal static unsafe class NativeMethods
{
    // MARK: Keyboard hook and hot keys
    // https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc
    // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowshookexw
    // https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerhotkey

    public const int WH_KEYBOARD_LL = 13;
    public const int WM_KEYDOWN = 0x0100, WM_KEYUP = 0x0101, WM_SYSKEYDOWN = 0x0104, WM_SYSKEYUP = 0x0105;
    public const int WM_HOTKEY = 0x0312, WM_TIMER = 0x0113, WM_QUIT = 0x0012, WM_APP = 0x8000;
    public const uint LLKHF_EXTENDED = 0x01, LLKHF_INJECTED = 0x10, LLKHF_UP = 0x80;
    public const uint MOD_ALT = 0x1, MOD_CONTROL = 0x2, MOD_SHIFT = 0x4, MOD_WIN = 0x8, MOD_NOREPEAT = 0x4000;
    public const int VK_SHIFT = 0x10, VK_CONTROL = 0x11, VK_MENU = 0x12, VK_LWIN = 0x5B, VK_RWIN = 0x5C;

    [StructLayout(LayoutKind.Sequential)]
    public struct KBDLLHOOKSTRUCT
    {
        public uint vkCode;
        public uint scanCode;
        public uint flags;
        public uint time;
        public nuint dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG
    {
        public nint hwnd;
        public uint message;
        public nuint wParam;
        public nint lParam;
        public uint time;
        public POINT pt;
        public uint lPrivate;
    }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern nint SetWindowsHookExW(int idHook, delegate* unmanaged[Stdcall]<int, nuint, nint, nint> lpfn, nint hmod, uint dwThreadId);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UnhookWindowsHookEx(nint hhk);

    [DllImport("user32.dll")]
    public static extern nint CallNextHookEx(nint hhk, int nCode, nuint wParam, nint lParam);

    [DllImport("user32.dll")]
    public static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool RegisterHotKey(nint hWnd, int id, uint fsModifiers, uint vk);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool UnregisterHotKey(nint hWnd, int id);

    [DllImport("user32.dll")]
    public static extern int GetMessageW(out MSG lpMsg, nint hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    public static extern nint DispatchMessageW(in MSG lpMsg);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool TranslateMessage(in MSG lpMsg);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool PostThreadMessageW(uint idThread, uint msg, nuint wParam, nint lParam);

    [DllImport("user32.dll")]
    public static extern nuint SetTimer(nint hWnd, nuint nIDEvent, uint uElapse, nint lpTimerFunc);

    [DllImport("user32.dll")]
    public static extern nint GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(nint hWnd, out uint lpdwProcessId);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    public static extern nint GetModuleHandleW(string? lpModuleName);

    // MARK: WinMM MIDI output
    // https://learn.microsoft.com/en-us/windows/win32/api/mmeapi/nf-mmeapi-midioutshortmsg

    public const uint MMSYSERR_NOERROR = 0;
    public const uint CALLBACK_NULL = 0;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MIDIOUTCAPSW
    {
        public ushort wMid;
        public ushort wPid;
        public uint vDriverVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szPname;
        public ushort wTechnology;
        public ushort wVoices;
        public ushort wNotes;
        public ushort wChannelMask;
        public uint dwSupport;
    }

    [DllImport("winmm.dll")]
    public static extern uint midiOutGetNumDevs();

    [DllImport("winmm.dll", CharSet = CharSet.Unicode)]
    public static extern uint midiOutGetDevCapsW(nuint uDeviceID, ref MIDIOUTCAPSW pmoc, uint cbmoc);

    [DllImport("winmm.dll")]
    public static extern uint midiOutOpen(out nint phmo, uint uDeviceID, nint dwCallback, nint dwInstance, uint fdwOpen);

    [DllImport("winmm.dll")]
    public static extern uint midiOutShortMsg(nint hmo, uint dwMsg);

    [DllImport("winmm.dll")]
    public static extern uint midiOutReset(nint hmo);

    [DllImport("winmm.dll")]
    public static extern uint midiOutClose(nint hmo);

    // MARK: Notification area (tray) icon and its menu
    // https://learn.microsoft.com/en-us/windows/win32/api/shellapi/nf-shellapi-shell_notifyiconw

    public const uint NIM_ADD = 0, NIM_MODIFY = 1, NIM_DELETE = 2, NIM_SETVERSION = 4;
    public const uint NIF_MESSAGE = 0x1, NIF_ICON = 0x2, NIF_TIP = 0x4, NIF_SHOWTIP = 0x80;
    public const uint NOTIFYICON_VERSION_4 = 4;
    public const int WM_CONTEXTMENU = 0x007B, WM_LBUTTONUP = 0x0202, WM_RBUTTONUP = 0x0205, WM_LBUTTONDBLCLK = 0x0203;
    public const int NIN_SELECT = 0x0400, NIN_KEYSELECT = 0x0401;
    public const uint MF_STRING = 0x0, MF_GRAYED = 0x1, MF_DISABLED = 0x2, MF_CHECKED = 0x8, MF_SEPARATOR = 0x800;
    public const uint TPM_RIGHTBUTTON = 0x2, TPM_RETURNCMD = 0x100, TPM_NONOTIFY = 0x80, TPM_BOTTOMALIGN = 0x20;
    public static readonly nint HWND_MESSAGE = -3;
    public const uint IMAGE_ICON = 1, LR_LOADFROMFILE = 0x10, LR_DEFAULTSIZE = 0x40;

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct NOTIFYICONDATAW
    {
        public uint cbSize;
        public nint hWnd;
        public uint uID;
        public uint uFlags;
        public uint uCallbackMessage;
        public nint hIcon;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
        public string szTip;
        public uint dwState;
        public uint dwStateMask;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string szInfo;
        public uint uVersion;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string szInfoTitle;
        public uint dwInfoFlags;
        public Guid guidItem;
        public nint hBalloonIcon;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct WNDCLASSEXW
    {
        public uint cbSize;
        public uint style;
        public delegate* unmanaged[Stdcall]<nint, uint, nuint, nint, nint> lpfnWndProc;
        public int cbClsExtra;
        public int cbWndExtra;
        public nint hInstance;
        public nint hIcon;
        public nint hCursor;
        public nint hbrBackground;
        public char* lpszMenuName;
        public char* lpszClassName;
        public nint hIconSm;
    }

    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool Shell_NotifyIconW(uint dwMessage, ref NOTIFYICONDATAW lpData);

    [DllImport("user32.dll", SetLastError = true)]
    public static extern ushort RegisterClassExW(in WNDCLASSEXW lpwcx);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern nint CreateWindowExW(uint dwExStyle, string lpClassName, string lpWindowName, uint dwStyle,
        int x, int y, int nWidth, int nHeight, nint hWndParent, nint hMenu, nint hInstance, nint lpParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyWindow(nint hWnd);

    [DllImport("user32.dll")]
    public static extern nint DefWindowProcW(nint hWnd, uint msg, nuint wParam, nint lParam);

    [DllImport("user32.dll")]
    public static extern nint CreatePopupMenu();

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool AppendMenuW(nint hMenu, uint uFlags, nuint uIDNewItem, string? lpNewItem);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyMenu(nint hMenu);

    [DllImport("user32.dll")]
    public static extern int TrackPopupMenuEx(nint hMenu, uint uFlags, int x, int y, nint hwnd, nint lptpm);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool SetForegroundWindow(nint hWnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool GetCursorPos(out POINT lpPoint);

    [DllImport("user32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    public static extern nint LoadImageW(nint hInst, string name, uint type, int cx, int cy, uint fuLoad);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool DestroyIcon(nint hIcon);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    public static extern uint RegisterWindowMessageW(string lpString);

    [DllImport("user32.dll")]
    public static extern uint GetDpiForWindow(nint hwnd);

    // MARK: DPAPI (the pairing code, readable only by this Windows user)
    // https://learn.microsoft.com/en-us/windows/win32/api/dpapi/nf-dpapi-cryptprotectdata

    [StructLayout(LayoutKind.Sequential)]
    public struct DATA_BLOB
    {
        public uint cbData;
        public nint pbData;
    }

    public const uint CRYPTPROTECT_UI_FORBIDDEN = 0x1;

    [DllImport("crypt32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CryptProtectData(in DATA_BLOB pDataIn, string? szDataDescr, nint pOptionalEntropy, nint pvReserved, nint pPromptStruct, uint dwFlags, out DATA_BLOB pDataOut);

    [DllImport("crypt32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CryptUnprotectData(in DATA_BLOB pDataIn, nint ppszDataDescr, nint pOptionalEntropy, nint pvReserved, nint pPromptStruct, uint dwFlags, out DATA_BLOB pDataOut);

    [DllImport("kernel32.dll")]
    public static extern nint LocalFree(nint hMem);

    // MARK: DNS-SD (mDNS) — Windows 10 1809 and later
    // https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsserviceregister
    // https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsservicebrowse
    // https://learn.microsoft.com/en-us/windows/win32/api/windns/nf-windns-dnsserviceresolve

    public const uint DNS_QUERY_REQUEST_VERSION1 = 1;
    public const uint DNS_REQUEST_PENDING = 9506;
    public const ushort DNS_TYPE_PTR = 12;

    [StructLayout(LayoutKind.Sequential)]
    public struct DNS_SERVICE_INSTANCE
    {
        public char* pszInstanceName;
        public char* pszHostName;
        public uint* ip4Address;
        public byte* ip6Address;
        public ushort wPort;
        public ushort wPriority;
        public ushort wWeight;
        public uint dwPropertyCount;
        public char** keys;
        public char** values;
        public uint dwInterfaceIndex;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DNS_SERVICE_CANCEL { public nint reserved; }

    [StructLayout(LayoutKind.Sequential)]
    public struct DNS_SERVICE_REGISTER_REQUEST
    {
        public uint Version;
        public uint InterfaceIndex;
        public DNS_SERVICE_INSTANCE* pServiceInstance;
        public delegate* unmanaged[Stdcall]<uint, nint, DNS_SERVICE_INSTANCE*, void> pRegisterCompletionCallback;
        public nint pQueryContext;
        public nint hCredentials;
        public int unicastEnabled;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DNS_SERVICE_BROWSE_REQUEST
    {
        public uint Version;
        public uint InterfaceIndex;
        public char* QueryName;
        public delegate* unmanaged[Stdcall]<uint, nint, DNS_RECORD*, void> pBrowseCallback;
        public nint pQueryContext;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct DNS_SERVICE_RESOLVE_REQUEST
    {
        public uint Version;
        public uint InterfaceIndex;
        public char* QueryName;
        public delegate* unmanaged[Stdcall]<uint, nint, DNS_SERVICE_INSTANCE*, void> pResolveCompletionCallback;
        public nint pQueryContext;
    }

    /// <summary>The head of DNS_RECORDW; for a PTR record the data is one PWSTR (pNameHost).</summary>
    [StructLayout(LayoutKind.Sequential)]
    public struct DNS_RECORD
    {
        public DNS_RECORD* pNext;
        public char* pName;
        public ushort wType;
        public ushort wDataLength;
        public uint Flags;
        public uint dwTtl;
        public uint dwReserved;
        public char* pNameHost;
    }

    [DllImport("dnsapi.dll", CharSet = CharSet.Unicode)]
    public static extern DNS_SERVICE_INSTANCE* DnsServiceConstructInstance(string pServiceName, string pHostName, uint* pIp4, byte* pIp6,
        ushort wPort, ushort wPriority, ushort wWeight, uint dwPropertiesCount, char** keys, char** values);

    [DllImport("dnsapi.dll")]
    public static extern void DnsServiceFreeInstance(DNS_SERVICE_INSTANCE* pInstance);

    [DllImport("dnsapi.dll")]
    public static extern uint DnsServiceRegister(DNS_SERVICE_REGISTER_REQUEST* pRequest, DNS_SERVICE_CANCEL* pCancel);

    [DllImport("dnsapi.dll")]
    public static extern uint DnsServiceDeRegister(DNS_SERVICE_REGISTER_REQUEST* pRequest, DNS_SERVICE_CANCEL* pCancel);

    [DllImport("dnsapi.dll")]
    public static extern uint DnsServiceBrowse(DNS_SERVICE_BROWSE_REQUEST* pRequest, DNS_SERVICE_CANCEL* pCancel);

    [DllImport("dnsapi.dll")]
    public static extern uint DnsServiceBrowseCancel(DNS_SERVICE_CANCEL* pCancelHandle);

    [DllImport("dnsapi.dll")]
    public static extern uint DnsServiceResolve(DNS_SERVICE_RESOLVE_REQUEST* pRequest, DNS_SERVICE_CANCEL* pCancel);

    [DllImport("dnsapi.dll")]
    public static extern uint DnsServiceResolveCancel(DNS_SERVICE_CANCEL* pCancelHandle);

    [DllImport("dnsapi.dll")]
    public static extern void DnsRecordListFree(DNS_RECORD* p, int freeType);
}
