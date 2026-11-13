using Microsoft.UI.Xaml;
using static TwinKeys.App.Platform.NativeMethods;

namespace TwinKeys.App.Platform;

internal static class WindowHelpers
{
    public static nint Handle(Window w) => WinRT.Interop.WindowNative.GetWindowHandle(w);

    /// <summary>Sizes a window in logical pixels (the mockups' sizes), whatever the display scale.</summary>
    public static void Resize(Window w, int width, int height)
    {
        uint dpi = GetDpiForWindow(Handle(w));
        double scale = dpi == 0 ? 1 : dpi / 96.0;
        w.AppWindow.Resize(new Windows.Graphics.SizeInt32((int)(width * scale), (int)(height * scale)));
    }

    public static string AssetPath(string name) => Path.Combine(AppContext.BaseDirectory, "Assets", name);

    /// <summary>Shows a window that may be hidden or minimized and brings it to the front.</summary>
    public static void Show(Window w)
    {
        w.AppWindow.Show();
        if (w.AppWindow.Presenter is Microsoft.UI.Windowing.OverlappedPresenter p && p.State == Microsoft.UI.Windowing.OverlappedPresenterState.Minimized) p.Restore();
        w.Activate();
        SetForegroundWindow(Handle(w));
    }
}
