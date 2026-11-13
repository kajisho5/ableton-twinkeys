using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using TwinKeys.App.Platform;
using TwinKeys.App.ViewModels;
using TwinKeys.Core;
using Windows.System;

namespace TwinKeys.App.Views;

/// <summary>The main window (docs/design-windows.md 3.1). Refreshed from the Conductor's snapshot 10 times a second.</summary>
public sealed partial class MainWindow : Window
{
    private readonly AppModel model;
    private readonly Action<string?> showSettings;
    private readonly Action showFirstRun;
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer timer;
    private bool updating;
    private string peerSignature = "";
    private string bannerKey = "";

    internal MainWindow(AppModel model, Action<string?> showSettings, Action showFirstRun, Action quit)
    {
        this.model = model;
        this.showSettings = showSettings;
        this.showFirstRun = showFirstRun;
        InitializeComponent();
        Title = "TwinKeys";
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon(WindowHelpers.AssetPath("TwinKeys.ico"));
        WindowHelpers.Resize(this, 640, 600);
        AppWindow.Closing += (_, e) =>
        {
            if (model.Settings.CloseToTray) { e.Cancel = true; AppWindow.Hide(); }
            else quit();
        };

        AddShortcut(VirtualKey.K, VirtualKeyModifiers.Control, model.ToggleConnect);
        AddShortcut(VirtualKey.K, VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift, () => _ = ConnectByIpAsync());
        AddShortcut((VirtualKey)188, VirtualKeyModifiers.Control, () => showSettings(null));   // Ctrl+, (VK_OEM_COMMA)
        AddShortcut(VirtualKey.F1, VirtualKeyModifiers.None, OpenHelp);

        model.LanguageChanged += () => { peerSignature = ""; bannerKey = ""; ApplyStrings(); Refresh(); };
        model.Changed += () => { peerSignature = ""; Refresh(); };
        ApplyStrings();
        Refresh();
        timer = DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromMilliseconds(100);
        timer.Tick += (_, _) => Refresh();
        timer.Start();
    }

    private void AddShortcut(VirtualKey key, VirtualKeyModifiers mods, Action action)
    {
        var a = new KeyboardAccelerator { Key = key, Modifiers = mods };
        a.Invoked += (_, e) => { e.Handled = true; action(); };
        Root.KeyboardAccelerators.Add(a);
    }

    private static Brush B(string key) => (Brush)Application.Current.Resources[key];

    private void OpenHelp() => AppModel.OpenUrl(Strings.Current.IsJapanese ? AppModel.HelpPageJa : AppModel.HelpPageEn);

    private void ApplyStrings()
    {
        var S = Strings.Current;
        PanicButton.Content = S["AllNotesOff"];
        ToolTipService.SetToolTip(PanicButton, S.F("AllNotesOffHelp", model.Settings.HotkeyAllNotesOff));
        LastCueTitle.Text = S["LastCue"];
        NearbyTitle.Text = S["NearbyTwinKeys"];
        ConnectByIpLink.Content = S["ConnectByIp"];
        ToolTipService.SetToolTip(ConnectByIpLink, S["ConnectByIpHint"]);
        ModesTitle.Text = S["ModeAndKeyboard"];
        SendKeysLabel.Text = S["SendKeys"];
        SendKeysHint.Text = S["SendKeysHint"];
        ReceiveLabel.Text = S["ReceiveNotes"];
        ReceiveHint.Text = S["ReceiveNotesHint"];
        CaptureLabel.Text = S["KeyCapture"];
        VersionText.Text = "v" + AppModel.Version;
        ToolTipService.SetToolTip(VersionText, S["TestVersionNote"]);
    }

    private static string NoteText(byte note) => MidiMessage.NoteName(note).Replace("#", "♯");

    private string NameOf(ConductorSnapshot s, string id) =>
        s.PeerNames.GetValueOrDefault(id)
        ?? model.Peers.FirstOrDefault(p => p.Id == id)?.Name
        ?? (id.StartsWith(PeerInfo.ManualPrefix, StringComparison.Ordinal) ? id[PeerInfo.ManualPrefix.Length..] : Strings.Current["AnotherComputer"]);

    private static string? OsName(string? os) => os switch { "win" => "Windows", "mac" => "macOS", _ => null };

    private void Refresh()
    {
        var S = Strings.Current;
        var s = model.Snapshot();
        updating = true;
        try
        {
            RefreshHeader(S, s);
            RefreshCue(S, s);
            RefreshPeers(S, s);
            SendKeysToggle.IsOn = s.SendKeys;
            ReceiveToggle.IsOn = s.ReceiveNotes;
            CaptureToggle.IsOn = s.KeyCapture;
            if (!model.HookInstalled)
            {
                CaptureHint.Text = S["HookMissing"];
                CaptureHint.Foreground = B("TkCriticalText");
            }
            else
            {
                CaptureHint.Text = !s.KeyCapture ? S.F("CaptureHintOff", model.Settings.HotkeyKeyCapture)
                    : model.Settings.BlockCueKeys ? S.F("CaptureHintOn", model.Settings.HotkeyKeyCapture)
                    : S.F("CaptureHintOnPassThrough", model.Settings.HotkeyKeyCapture);
                CaptureHint.Foreground = B("TkSecondaryText");
            }
            RefreshFooter(S);
            RefreshLive(S);
            RefreshBanner(S, s);
        }
        finally
        {
            updating = false;
        }
    }

    private void RefreshHeader(Strings S, ConductorSnapshot s)
    {
        switch (s.Link)
        {
            case LinkStateMachine.State.Connected c:
                {
                    LinkDot.Fill = B("TkSuccess");
                    LinkTitle.Text = S.F("ConnectedTo", NameOf(s, c.Peer));
                    var parts = new List<string> { s.LatencyMs is double ms ? S.F("Latency", $"{ms:0}") : S["Measuring"] };
                    parts.Add((s.SendKeys, s.ReceiveNotes) switch
                    {
                        (true, true) => S["SendingAndReceiving"],
                        (true, false) => S["Sending"],
                        (false, true) => S["Receiving"],
                        _ => S["BothOff"],
                    });
                    if (OsName(model.Peers.FirstOrDefault(p => p.Id == c.Peer)?.Os) is string os) parts.Add(S.F("PeerOs", os));
                    if (model.Conductor.PeerLiveConnected is bool peerLive) parts.Add(peerLive ? S["PeerLiveOK"] : S["PeerLiveNo"]);
                    LinkDetail.Text = string.Join(S["Separator"], parts);
                    break;
                }
            case LinkStateMachine.State.Connecting c:
                LinkDot.Fill = B("TkCaution");
                LinkTitle.Text = S.F("ConnectingTo", NameOf(s, c.Peer));
                LinkDetail.Text = c.Attempt > 1 ? S.F("Retrying", c.Attempt) : S["WaitingForAnswer"];
                break;
            default:
                LinkDot.Fill = B("TkTertiaryText");
                LinkTitle.Text = s.IsPaired ? S["NotConnected"] : S["NeedsPairing"];
                LinkDetail.Text = !s.IsPaired ? S["NeedsPairingDetail"] : model.Peers.Count > 0 ? S["ChooseComputer"] : S["Searching"];
                break;
        }
    }

    private void RefreshCue(Strings S, ConductorSnapshot s)
    {
        if (s.LastCue is not CueStatus cue)
        {
            CueRow.Visibility = Visibility.Collapsed;
            NoCueText.Visibility = Visibility.Visible;
            NoCueText.Text = s.SendKeys ? S["NoCueYet"] : S["NoCueReceivedYet"];
            DeliveryIcon.Visibility = Visibility.Collapsed;
            DeliveryTitle.Text = "";
            DeliveryDetail.Text = "";
            return;
        }
        CueRow.Visibility = Visibility.Visible;
        NoCueText.Visibility = Visibility.Collapsed;
        DeliveryIcon.Visibility = Visibility.Visible;
        CueKeyLabel.Text = cue.Label;
        CueMemo.Text = cue.Memo.Length > 0 ? cue.Memo : cue.Label;
        CueDetail.Text = S.F("CueDetail", NoteText(cue.Note), cue.Count);
        var peer = cue.PeerName ?? S["AnotherComputer"];
        (string brush, string glyph, string title, string detail) = cue.Delivery switch
        {
            CueStatus.DeliveryKind.Delivered => ("TkSuccess", "✓", S["DeliveredToBackup"], $"{peer}{S["Separator"]}{cue.DeliveredMs ?? 0:0} ms"),
            CueStatus.DeliveryKind.Waiting => ("TkCaution", "…", S["WaitingForBackup"], peer),
            CueStatus.DeliveryKind.Missing => ("TkCritical", "!", S["NotConfirmed"], S["NotConfirmedDetail"]),
            CueStatus.DeliveryKind.Unconfirmed => ("TkTertiaryText", "?", S["CannotConfirm"], S["CannotConfirmDetail"]),
            CueStatus.DeliveryKind.NotConnected => ("TkTertiaryText", "–", S["CueNotConnected"], S["CueNotConnectedDetail"]),
            _ => ("TkAccent", "↓", S["ReceivedFromMain"], peer),
        };
        DeliveryCircle.Fill = B(brush);
        DeliveryGlyph.Text = glyph;
        DeliveryTitle.Text = title;
        DeliveryTitle.Foreground = cue.Delivery == CueStatus.DeliveryKind.Missing ? B("TkCriticalText") : B("TkText");
        DeliveryDetail.Text = detail;
    }

    private void RefreshPeers(Strings S, ConductorSnapshot s)
    {
        var peers = model.Peers.ToList();
        string? linkPeer = s.Link switch
        {
            LinkStateMachine.State.Connected c => c.Peer,
            LinkStateMachine.State.Connecting c => c.Peer,
            _ => null,
        };
        // A computer connected by IP address that mDNS does not show still gets its row.
        if (linkPeer is not null && peers.All(p => p.Id != linkPeer))
            peers.Insert(0, new PeerInfo(linkPeer, NameOf(s, linkPeer), false, false));
        var sig = string.Join("|", peers.Select(p => $"{p.Id}/{p.Name}/{p.Os}/{p.Sends}{p.Receives}/{p.IsCompatible}/{s.MismatchedPeers.Contains(p.Id)}"))
                  + $"#{s.Link}#{(int)(s.LatencyMs ?? -1)}#{s.IsPaired}#{S.Language}";
        if (sig == peerSignature) return;
        peerSignature = sig;
        PeerList.Children.Clear();
        if (peers.Count == 0)
        {
            var empty = new StackPanel { Padding = new Thickness(16, 12, 16, 12), Spacing = 4 };
            empty.Children.Add(new TextBlock { Text = S["NoPeersTitle"], FontSize = 14, FontWeight = FontWeights.SemiBold });
            empty.Children.Add(new TextBlock { Text = S["NoPeersHint"], Style = (Style)Application.Current.Resources["TkHint"] });
            PeerList.Children.Add(empty);
            return;
        }
        foreach (var p in peers) PeerList.Children.Add(PeerRow(S, s, p, linkPeer));
    }

    private Grid PeerRow(Strings S, ConductorSnapshot s, PeerInfo p, string? linkPeer)
    {
        bool isLink = p.Id == linkPeer;
        bool connected = isLink && s.Link is LinkStateMachine.State.Connected;
        var row = new Grid { Height = 52, Padding = new Thickness(16, 0, 10, 0), CornerRadius = new CornerRadius(7) };
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        if (isLink)
        {
            row.Background = B("TkSelectedRow");
            var bar = new Rectangle { Width = 3, Height = 24, RadiusX = 1.5, RadiusY = 1.5, Fill = B("TkAccent"), HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(-16, 0, 0, 0) };
            row.Children.Add(bar);
        }
        var dot = new Ellipse
        {
            Width = 8, Height = 8, Margin = new Thickness(0, 0, 14, 0), VerticalAlignment = VerticalAlignment.Center,
            Fill = connected ? B("TkSuccess") : isLink ? B("TkCaution") : B("TkTertiaryText"),
        };
        row.Children.Add(dot);
        var text = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        Grid.SetColumn(text, 1);
        text.Children.Add(new TextBlock { Text = p.Name, FontSize = 14, FontWeight = FontWeights.SemiBold, TextTrimming = TextTrimming.CharacterEllipsis });
        var detail = new TextBlock { FontSize = 12, Foreground = B("TkSecondaryText"), TextTrimming = TextTrimming.CharacterEllipsis };
        if (s.MismatchedPeers.Contains(p.Id)) { detail.Text = S["CodeMismatch"]; detail.Foreground = B("TkCriticalText"); }
        else if (!p.IsCompatible) { detail.Text = S["Incompatible"]; detail.Foreground = B("TkCriticalText"); }
        else
        {
            var parts = new List<string>();
            if (OsName(p.Os) is string os) parts.Add(os);
            if (p.Sends || p.Receives) parts.Add(p.Sends && p.Receives ? S["ModeSendReceive"] : p.Sends ? S["ModeSend"] : S["ModeReceive"]);
            if (connected && s.LatencyMs is double ms) parts.Add($"{ms:0} ms");
            else if (isLink) parts.Add(S["ConnectingShort"]);
            detail.Text = string.Join(S["Separator"], parts);
        }
        text.Children.Add(detail);
        row.Children.Add(text);
        var button = new Button
        {
            Content = isLink ? S["Disconnect"] : S["Connect"], Width = 104, Height = 32, VerticalAlignment = VerticalAlignment.Center,
            IsEnabled = isLink || (p.IsCompatible && s.IsPaired),
        };
        ToolTipService.SetToolTip(button, isLink ? S.F("DisconnectFrom", p.Name) : S.F("ConnectTo", p.Name));
        button.Click += (_, _) => { if (isLink) model.Disconnect(); else model.Connect(p); peerSignature = ""; };
        Grid.SetColumn(button, 2);
        row.Children.Add(button);
        return row;
    }

    private void RefreshFooter(Strings S)
    {
        switch (model.Midi.Current)
        {
            case WinMmMidiOut.Status.Ready r:
                MidiDot.Fill = B("TkSuccess");
                MidiStatus.Text = S.F("MidiReady", r.PortName);
                break;
            case WinMmMidiOut.Status.NotFound n:
                MidiDot.Fill = B("TkCritical");
                MidiStatus.Text = S.F("MidiNotFound", n.Wanted);
                break;
            case WinMmMidiOut.Status.Error e:
                MidiDot.Fill = B("TkCritical");
                MidiStatus.Text = S.F("MidiError", e.Text);
                break;
            default:
                MidiDot.Fill = B("TkTertiaryText");
                MidiStatus.Text = S["MidiOff"];
                break;
        }
    }

    /// <summary>The footer's Live status (phase 2).</summary>
    private void RefreshLive(Strings S)
    {
        if (model.LiveConnected)
        {
            LiveDot.Fill = model.BridgeNeedsRestart ? B("TkCaution") : B("TkSuccess");
            LiveStatus.Text = model.BridgeNeedsRestart ? S["LiveNeedsRestart"] : S["LiveConnected"];
        }
        else
        {
            LiveDot.Fill = B("TkTertiaryText");
            LiveStatus.Text = model.Installer.IsInstalled ? S["LiveNotConnected"] : S["LiveNotInstalled"];
        }
    }

    private async Task ConfirmBecomeMainAsync()
    {
        var S = Strings.Current;
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = S["BecomeMainTitle"],
            Content = new TextBlock { Text = S["BecomeMainMessage"], TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = S["BecomeMainConfirm"],
            CloseButtonText = S["Cancel"],
            DefaultButton = ContentDialogButton.Primary,
        };
        model.OwnInputHasFocus = true;
        try
        {
            if (await dialog.ShowAsync() == ContentDialogResult.Primary) model.BecomeMain();
        }
        finally { model.OwnInputHasFocus = false; }
        bannerKey = "";
    }

    private void RefreshBanner(Strings S, ConductorSnapshot s)
    {
        string key = "", text = "", title = "";
        string? action = null;
        Action? onAction = null;
        var severity = InfoBarSeverity.Informational;
        var diff = model.Conductor.SetDifference;
        if (model.Problem is string problem)
        {
            (key, severity, text) = ("problem:" + problem, InfoBarSeverity.Error, problem);
        }
        else if (model.MainLost(s))
        {
            // The main computer stopped answering: this PC can take over (the Mac's 2.3 banner).
            (key, severity, title, text, action) = ("mainLost", InfoBarSeverity.Error, S["MainLostTitle"], S["MainLostMessage"], S["BecomeMainButton"]);
            onAction = () => _ = ConfirmBecomeMainAsync();
        }
        else if (!s.IsPaired)
        {
            (key, text, action) = ("pairing", S["NeedsPairingBanner"], S["SetUpPairing"]);
            onAction = () => showSettings("pairing");
        }
        else if (model.Settings.MidiMode == MidiOutputMode.Loopback && model.Midi.Current is WinMmMidiOut.Status.NotFound)
        {
            (key, severity, text, action) = ("midi", InfoBarSeverity.Warning, S.F("MidiMissingBanner", model.Settings.MidiPortName), S["OpenMidiSetup"]);
            onAction = showFirstRun;
        }
        else if (s.MismatchedPeers.Count > 0)
        {
            (key, severity, text, action) = ("mismatch", InfoBarSeverity.Warning, S["CodeMismatchBanner"], S["SetUpPairing"]);
            onAction = () => showSettings("pairing");
        }
        else if (s.ClaimsMain)
        {
            (key, severity, text, action) = ("claimsMain", InfoBarSeverity.Informational, S["ThisPcIsMain"], S["ReturnToMain"]);
            onAction = () => { model.ReturnToMain(); bannerKey = ""; };
        }
        else if (diff is not null)
        {
            var summary = S.F("SetDiffSummary", diff.MainTracks, diff.BackupTracks, diff.MainScenes, diff.BackupScenes, diff.Differences)
                          + (diff.Complete ? "" : " " + S["SetDiffChecking"]);
            var rows = diff.Rows.Take(5).Select(r => $"{(r.Kind == "track" ? "T" : "S")}{r.Index + 1}: {r.Main ?? "—"} / {r.Backup ?? "—"}");
            (key, severity, title, text) = ($"setDiff:{summary}:{string.Join("|", rows)}", InfoBarSeverity.Warning, S["SetDiffTitle"],
                summary + "\n" + string.Join("\n", rows) + "\n" + S["SetDiffNote"]);
        }
        key += "#" + S.Language;
        if (key == bannerKey) return;
        bannerKey = key;
        Banner.IsOpen = text.Length > 0;
        Banner.Severity = severity;
        Banner.Title = title;
        Banner.Message = text;
        if (action is not null && onAction is not null)
        {
            var b = new Button { Content = action };
            b.Click += (_, _) => onAction();
            Banner.ActionButton = b;
        }
        else
        {
            Banner.ActionButton = null;
        }
    }

    // MARK: Events

    private void OnPanic(object sender, RoutedEventArgs e) => model.Panic();

    private void OnSendKeysToggled(object sender, RoutedEventArgs e)
    {
        if (!updating) model.SetSendKeys(SendKeysToggle.IsOn);
    }

    private void OnReceiveToggled(object sender, RoutedEventArgs e)
    {
        if (!updating) model.SetReceiveNotes(ReceiveToggle.IsOn);
    }

    private void OnCaptureToggled(object sender, RoutedEventArgs e)
    {
        if (!updating) model.SetKeyCapture(CaptureToggle.IsOn);
    }

    private void OnConnectByIp(object sender, RoutedEventArgs e) => _ = ConnectByIpAsync();

    private async Task ConnectByIpAsync()
    {
        var S = Strings.Current;
        var box = new TextBox { PlaceholderText = "192.168.1.20", Text = model.Settings.ManualAddress ?? "" };
        var error = new TextBlock { Foreground = B("TkCriticalText"), TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed };
        var panel = new StackPanel { Spacing = 10 };
        panel.Children.Add(new TextBlock { Text = S["ConnectByIpExplain"], TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(box);
        panel.Children.Add(error);
        var mine = AppModel.LocalAddresses();
        panel.Children.Add(new TextBlock
        {
            Text = S.F("ThisPcAddress", mine.Count > 0 ? string.Join(", ", mine) : S["NoAddress"]) + "  " + S.F("PortLabel", model.Net.ListenPort ?? UdpTransport.FixedPort),
            Style = (Style)Application.Current.Resources["TkHint"],
        });
        var dialog = new ContentDialog
        {
            XamlRoot = Content.XamlRoot,
            Title = S["ConnectByIpTitle"],
            Content = panel,
            PrimaryButtonText = S["Connect"],
            CloseButtonText = S["Cancel"],
            DefaultButton = ContentDialogButton.Primary,
        };
        dialog.PrimaryButtonClick += async (d, args) =>
        {
            var deferral = args.GetDeferral();
            bool ok = ManualAddress.Parse(box.Text) is not null && await model.ConnectByAddressAsync(box.Text);
            if (!ok)
            {
                args.Cancel = true;
                error.Text = S["InvalidAddress"];
                error.Visibility = Visibility.Visible;
            }
            deferral.Complete();
        };
        model.OwnInputHasFocus = true;
        try { await dialog.ShowAsync(); }
        finally { model.OwnInputHasFocus = false; }
    }
}
