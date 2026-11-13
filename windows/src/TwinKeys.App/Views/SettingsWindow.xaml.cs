using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;
using TwinKeys.App.Platform;
using TwinKeys.App.ViewModels;
using TwinKeys.Core;
using Windows.ApplicationModel.DataTransfer;

namespace TwinKeys.App.Views;

/// <summary>
/// Settings (docs/design-windows.md 3.2): cue keys, MIDI output, Live (phase 2), pairing code,
/// iPhone remote (phase 3, shown as "coming"), updates, general. Each page is built in code.
/// </summary>
public sealed partial class SettingsWindow : Window
{
    private readonly AppModel model;
    private readonly Action showFirstRun;
    private string page = "cues";

    internal SettingsWindow(AppModel model, Action showFirstRun)
    {
        this.model = model;
        this.showFirstRun = showFirstRun;
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon(WindowHelpers.AssetPath("TwinKeys.ico"));
        WindowHelpers.Resize(this, 860, 640);
        model.LanguageChanged += Rebuild;
        Closed += (_, _) => model.LanguageChanged -= Rebuild;
        Rebuild();
    }

    private static Brush B(string key) => (Brush)Application.Current.Resources[key];
    private static Style St(string key) => (Style)Application.Current.Resources[key];

    public void SelectPage(string key)
    {
        page = key;
        Rebuild();
    }

    private void Rebuild()
    {
        var S = Strings.Current;
        Title = S["SettingsTitle"];
        TitleText.Text = S["SettingsTitle"];
        Nav.MenuItems.Clear();
        NavigationViewItem? selected = null;
        foreach (var (key, glyph, text, enabled) in new (string, string, string, bool)[]
        {
            ("cues", "", S["PageCueKeys"], true),
            ("midi", "", S["PageMidi"], true),
            ("live", "", S["PageLive"], true),
            ("pairing", "", S["PagePairing"], true),
            ("remote", "", S["PageRemote"], false),
            ("updates", "", S["PageUpdates"], true),
            ("general", "", S["PageGeneral"], true),
        })
        {
            object content = text;
            if (!enabled)
            {
                var sp = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
                sp.Children.Add(new TextBlock { Text = text });
                sp.Children.Add(new TextBlock { Text = S["Coming"], FontSize = 11, VerticalAlignment = VerticalAlignment.Center, Foreground = B("TkTertiaryText") });
                content = sp;
            }
            var item = new NavigationViewItem { Content = content, Icon = new FontIcon { Glyph = glyph }, Tag = key, IsEnabled = enabled };
            Nav.MenuItems.Add(item);
            if (key == page) selected = item;
        }
        building = true;
        Nav.SelectedItem = selected;
        building = false;
        ShowPage();
    }

    private bool building;

    private void OnNavigationChanged(NavigationView sender, NavigationViewSelectionChangedEventArgs args)
    {
        if (building || args.SelectedItem is not NavigationViewItem { Tag: string key }) return;
        page = key;
        ShowPage();
    }

    private void ShowPage()
    {
        PagePanel.Children.Clear();
        switch (page)
        {
            case "midi": MidiPage(); break;
            case "live": LivePage(); break;
            case "pairing": PairingPage(); break;
            case "updates": UpdatesPage(); break;
            case "general": GeneralPage(); break;
            default: CueKeysPage(); break;
        }
    }

    // MARK: Building blocks

    private void Heading(string title, string? description = null)
    {
        PagePanel.Children.Add(new TextBlock { Text = title, FontSize = 28, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 8, 0, 0) });
        if (description is not null) PagePanel.Children.Add(new TextBlock { Text = description, Style = St("TkHint"), FontSize = 13 });
    }

    private StackPanel Card()
    {
        var inner = new StackPanel { Spacing = 10 };
        PagePanel.Children.Add(new Border { Style = St("TkCardStyle"), Padding = new Thickness(16), Child = inner });
        return inner;
    }

    private static TextBlock Hint(string text) => new() { Text = text, Style = St("TkHint") };

    private static Border Keycap(string label) => new()
    {
        MinWidth = 44, Height = 34, Padding = new Thickness(10, 0, 10, 0), CornerRadius = new CornerRadius(5), BorderThickness = new Thickness(1),
        Background = B("TkKeycapBackground"), BorderBrush = B("TkKeycapStroke"), HorizontalAlignment = HorizontalAlignment.Left,
        Child = new TextBlock { Text = label, FontSize = 15, FontWeight = FontWeights.SemiBold, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
    };

    private void TrackFocus(Control c)
    {
        c.GotFocus += (_, _) => model.OwnInputHasFocus = true;
        c.LostFocus += (_, _) => model.OwnInputHasFocus = false;
    }

    private async Task<ContentDialogResult> ShowDialog(ContentDialog d)
    {
        d.XamlRoot = Content.XamlRoot;
        model.OwnInputHasFocus = true;
        try { return await d.ShowAsync(); }
        finally { model.OwnInputHasFocus = false; }
    }

    // MARK: Cue keys

    private void CueKeysPage()
    {
        var S = Strings.Current;
        Heading(S["PageCueKeys"], S["CueKeysByPosition"]);
        var card = Card();
        var header = CueGrid();
        header.Children.Add(Cell(new TextBlock { Text = S["CueKeyColumn"], FontWeight = FontWeights.SemiBold, Foreground = B("TkSecondaryText") }, 0));
        header.Children.Add(Cell(new TextBlock { Text = S["CueMemoColumn"], FontWeight = FontWeights.SemiBold, Foreground = B("TkSecondaryText") }, 1));
        header.Children.Add(Cell(new TextBlock { Text = "MIDI", FontWeight = FontWeights.SemiBold, Foreground = B("TkSecondaryText") }, 2));
        card.Children.Add(header);
        var keys = model.Settings.CueKeys.OrderBy(k => k.Note).ToList();
        if (keys.Count == 0) card.Children.Add(Hint(S["CueKeysNone"]));
        foreach (var k in keys)
        {
            card.Children.Add(new Rectangle { Height = 1, Fill = B("TkCardStroke") });
            var row = CueGrid();
            row.Children.Add(Cell(Keycap(k.Label), 0));
            var memo = new TextBox { Text = k.Memo, PlaceholderText = S["MemoPlaceholder"], VerticalAlignment = VerticalAlignment.Center };
            ToolTipService.SetToolTip(memo, S.F("MemoFor", k.Label));
            TrackFocus(memo);
            var code = k.KeyCode;
            memo.LostFocus += (_, _) =>
            {
                var list = model.Settings.CueKeys.Select(x => x.KeyCode == code ? x with { Memo = memo.Text } : x).ToList();
                model.SetCueKeys(list);
            };
            row.Children.Add(Cell(memo, 1));
            row.Children.Add(Cell(new TextBlock
            {
                Text = $"ch {model.Settings.MidiChannel}{S["Separator"]}{MidiMessage.NoteName(k.Note).Replace("#", "♯")}",
                FontFamily = new FontFamily("Consolas"), Foreground = B("TkSecondaryText"), VerticalAlignment = VerticalAlignment.Center,
            }, 2));
            var remove = new Button { Content = new FontIcon { Glyph = "", FontSize = 14 }, Width = 40, Height = 34, Padding = new Thickness(0) };
            ToolTipService.SetToolTip(remove, S.F("RemoveCueKey", k.Label));
            remove.Click += (_, _) =>
            {
                model.SetCueKeys(model.Settings.CueKeys.Where(x => x.KeyCode != code).ToList());
                ShowPage();
            };
            row.Children.Add(Cell(remove, 3));
            card.Children.Add(row);
        }
        card.Children.Add(new Rectangle { Height = 1, Fill = B("TkCardStroke") });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        var add = new Button { Content = S["AddCueKey"], Style = St("AccentButtonStyle"), MinWidth = 180, Height = 40 };
        add.Click += async (_, _) => await AddKeysAsync();
        var letters = new Button { Content = S["AddLettersAndDigits"], MinWidth = 180, Height = 40 };
        var result = Hint("");
        letters.Click += (_, _) =>
        {
            var before = model.Settings.CueKeys.Select(x => x.KeyCode).ToHashSet();
            var after = CueKey.Adding(KeyIds.Alphanumeric, model.Settings.CueKeys);
            model.SetCueKeys(after);
            var added = after.Where(x => !before.Contains(x.KeyCode)).Select(x => x.Label).ToList();
            ShowPage();
            PagePanel.Children.Add(Hint(added.Count > 0 ? S.F("AddedKeys", string.Join(" ", added)) : S["CueKeysFull"]));
        };
        buttons.Children.Add(add);
        buttons.Children.Add(letters);
        buttons.Children.Add(new TextBlock { Text = S["AddCueKeyHint"], Style = St("TkHint"), MaxWidth = 260, VerticalAlignment = VerticalAlignment.Center });
        card.Children.Add(buttons);
        card.Children.Add(result);

        var options = Card();
        var block = new CheckBox { IsChecked = model.Settings.BlockCueKeys };
        block.Content = new TextBlock { Text = S["BlockCueKeys"], FontSize = 14, TextWrapping = TextWrapping.Wrap };
        block.Checked += (_, _) => model.SetBlockCueKeys(true);
        block.Unchecked += (_, _) => model.SetBlockCueKeys(false);
        options.Children.Add(block);
        options.Children.Add(new TextBlock { Text = S["BlockCueKeysHelp"], Style = St("TkHint"), Margin = new Thickness(28, -6, 0, 0) });
        options.Children.Add(new Rectangle { Height = 1, Fill = B("TkCardStroke") });
        var autoRow = new Grid();
        autoRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        autoRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        autoRow.Children.Add(new TextBlock { Text = S["AutoNoteOffLabel"], FontSize = 14, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap });
        var seconds = new ComboBox { MinWidth = 140 };
        double[] choices = [0, 3, 5, 10, 20, 30, 60];
        foreach (var c in choices) seconds.Items.Add(c == 0 ? S["Off"] : S.F("Seconds", c));
        seconds.SelectedIndex = Math.Max(0, Array.IndexOf(choices, model.Settings.AutoNoteOffSeconds));
        seconds.SelectionChanged += (_, _) => { if (seconds.SelectedIndex >= 0) model.SetAutoNoteOff(choices[seconds.SelectedIndex]); };
        Grid.SetColumn(seconds, 1);
        autoRow.Children.Add(seconds);
        options.Children.Add(autoRow);
        options.Children.Add(Hint(S["AutoNoteOffHelp"]));
    }

    private static Grid CueGrid()
    {
        var g = new Grid { ColumnSpacing = 16, MinHeight = 40 };
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(150) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(130) });
        g.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(40) });
        return g;
    }

    private static FrameworkElement Cell(FrameworkElement e, int column)
    {
        Grid.SetColumn(e, column);
        e.VerticalAlignment = VerticalAlignment.Center;
        return e;
    }

    /// <summary>"Add Key…": the keys pressed while the dialog is open become cue keys (by position).</summary>
    private async Task AddKeysAsync()
    {
        var S = Strings.Current;
        var added = new TextBlock { Style = St("TkHint"), FontSize = 14 };
        var panel = new StackPanel { Spacing = 10, MinWidth = 360 };
        panel.Children.Add(new TextBlock { Text = S["PressKeyToAdd"], FontSize = 16, FontWeight = FontWeights.SemiBold });
        panel.Children.Add(Hint(S["PressKeyHint"]));
        panel.Children.Add(added);
        var dialog = new ContentDialog { Title = S["AddKeyTitle"], Content = panel, CloseButtonText = S["Done"] };
        var labels = new List<string>();
        model.StartLearning(k =>
        {
            if (model.Settings.CueKeys.Any(x => x.KeyCode == k.KeyCode)) { added.Text = S.F("KeyAlreadyUsed", KeyIds.Label(k.KeyCode)); return; }
            var after = CueKey.Adding([k.KeyCode], model.Settings.CueKeys);
            if (after.Count == model.Settings.CueKeys.Count) { added.Text = S["CueKeysFull"]; return; }
            model.SetCueKeys(after);
            labels.Add(KeyIds.Label(k.KeyCode));
            added.Text = S.F("AddedKeys", string.Join(" ", labels));
        });
        try { await ShowDialog(dialog); }
        finally { model.StopLearning(); }
        ShowPage();
    }

    // MARK: MIDI output

    private void MidiPage()
    {
        var S = Strings.Current;
        Heading(S["PageMidi"], S["FirstRunSubtitle"]);
        var card = Card();
        var loop = new RadioButton { Content = S["ModeLoopback"], GroupName = "midi", IsChecked = model.Settings.MidiMode == MidiOutputMode.Loopback, FontWeight = FontWeights.SemiBold };
        card.Children.Add(loop);
        card.Children.Add(new TextBlock { Text = S["ModeLoopbackDetail"], Style = St("TkHint"), Margin = new Thickness(28, -6, 0, 0) });
        var virt = new RadioButton { Content = S["ModeVirtual"], GroupName = "midi", IsEnabled = false };
        card.Children.Add(virt);
        card.Children.Add(new TextBlock { Text = S["ModeVirtualDetail"] + "\n○ " + S["ModeVirtualUnavailable"], Style = St("TkHint"), Margin = new Thickness(28, -6, 0, 0) });
        var bridge = new RadioButton { Content = S["ModeBridge"], GroupName = "midi", IsEnabled = false };
        card.Children.Add(bridge);
        card.Children.Add(new TextBlock { Text = S["ModeBridgeDetail"] + "\n○ " + S["ModeBridgeUnavailable"], Style = St("TkHint"), Margin = new Thickness(28, -6, 0, 0) });
        loop.Checked += (_, _) => { model.SetMidiOutput(MidiOutputMode.Loopback, model.Settings.MidiPortName); ShowPage(); };

        var port = Card();
        var nameRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        nameRow.Children.Add(new TextBlock { Text = S["PortName"], FontSize = 14, VerticalAlignment = VerticalAlignment.Center });
        var name = new TextBox { Text = model.Settings.MidiPortName, MinWidth = 220 };
        TrackFocus(name);
        name.LostFocus += (_, _) => { if (name.Text.Trim() != model.Settings.MidiPortName) { model.SetMidiOutput(model.Settings.MidiMode, name.Text); ShowPage(); } };
        nameRow.Children.Add(name);
        var rescan = new Button { Content = S["LookAgain"] };
        rescan.Click += (_, _) => { model.Midi.Rescan(); ShowPageSoon(); };
        nameRow.Children.Add(rescan);
        port.Children.Add(nameRow);
        port.Children.Add(StatusLine(MidiStatusText(S), model.Midi.Current is WinMmMidiOut.Status.Ready));
        var outputs = WinMmMidiOut.OutputNames();
        port.Children.Add(Hint(S.F("MidiOutputsFound", outputs.Count > 0 ? string.Join(", ", outputs) : S["None"])));
        port.Children.Add(Hint(S["LoopbackHowTo"]));

        var test = Card();
        var testRow = new Grid();
        testRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        testRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        testRow.Children.Add(new TextBlock { Text = S.F("TestSendLabel", model.Settings.MidiPortName), FontSize = 14, VerticalAlignment = VerticalAlignment.Center, TextWrapping = TextWrapping.Wrap });
        var send = new Button { Content = S["TestSend"], MinWidth = 120 };
        var result = Hint("");
        send.Click += async (_, _) =>
        {
            bool ok = await model.TestSendAsync();
            result.Text = ok ? S["TestSendDone"] : S.F("MidiNotFound", model.Settings.MidiPortName);
        };
        Grid.SetColumn(send, 1);
        testRow.Children.Add(send);
        test.Children.Add(testRow);
        test.Children.Add(result);
        var setup = new Button { Content = S["OpenFirstRun"] };
        setup.Click += (_, _) => showFirstRun();
        PagePanel.Children.Add(setup);
    }

    private void ShowPageSoon()
    {
        var t = DispatcherQueue.CreateTimer();
        t.Interval = TimeSpan.FromMilliseconds(400);
        t.IsRepeating = false;
        t.Tick += (_, _) => ShowPage();
        t.Start();
    }

    private string MidiStatusText(Strings S) => model.Midi.Current switch
    {
        WinMmMidiOut.Status.Ready r => S.F("FoundPort", r.PortName) + (model.TestSendWorked ? S["SentHere"] : ""),
        WinMmMidiOut.Status.NotFound n => S.F("MidiNotFound", n.Wanted),
        WinMmMidiOut.Status.Error e => S.F("MidiError", e.Text),
        _ => S["MidiOff"],
    };

    private static StackPanel StatusLine(string text, bool ok)
    {
        var sp = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
        sp.Children.Add(new Ellipse { Width = 8, Height = 8, VerticalAlignment = VerticalAlignment.Center, Fill = ok ? B("TkSuccess") : B("TkCritical") });
        sp.Children.Add(new TextBlock { Text = text, FontSize = 13, Foreground = ok ? B("TkSuccess") : B("TkCriticalText"), FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap });
        return sp;
    }

    // MARK: Live, pairing, updates, general

    private void LivePage()
    {
        var S = Strings.Current;
        Heading(S["PageLive"]);
        Card().Children.Add(new TextBlock { Text = S["LivePhase2"], TextWrapping = TextWrapping.Wrap, FontSize = 14 });
    }

    private void PairingPage()
    {
        var S = Strings.Current;
        Heading(S["PagePairing"], S["PairingExplain"]);
        var card = Card();
        card.Children.Add(new TextBlock { Text = S["ThisPcCode"], FontSize = 14, Foreground = B("TkSecondaryText") });
        card.Children.Add(new TextBlock
        {
            Text = model.PairingCode ?? S["NoCodeYet"], FontSize = 28, FontWeight = FontWeights.SemiBold,
            FontFamily = new FontFamily("Consolas"), IsTextSelectionEnabled = true,
        });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        var make = new Button { Content = S["MakeNewCode"] };
        make.Click += async (_, _) =>
        {
            if (model.PairingCode is not null)
            {
                var confirm = new ContentDialog
                {
                    Title = S["ReplaceCodeTitle"], Content = S["ReplaceCodeMessage"],
                    PrimaryButtonText = S["MakeNew"], CloseButtonText = S["Cancel"], DefaultButton = ContentDialogButton.Close,
                };
                if (await ShowDialog(confirm) != ContentDialogResult.Primary) return;
            }
            model.MakeNewPairingCode();
            ShowPage();
        };
        var copy = new Button { Content = S["Copy"], IsEnabled = model.PairingCode is not null };
        copy.Click += (_, _) =>
        {
            var data = new DataPackage();
            data.SetText(model.PairingCode ?? "");
            Clipboard.SetContent(data);
        };
        var enter = new Button { Content = S["EnterCode"], Style = St("AccentButtonStyle") };
        enter.Click += async (_, _) => await EnterCodeAsync();
        buttons.Children.Add(make);
        buttons.Children.Add(copy);
        buttons.Children.Add(enter);
        card.Children.Add(buttons);
        card.Children.Add(Hint(S["PairingSameOnBoth"]));
        var net = Card();
        var mine = AppModel.LocalAddresses();
        net.Children.Add(new TextBlock { Text = S.F("ThisPcAddress", mine.Count > 0 ? string.Join(", ", mine) : S["NoAddress"]), FontSize = 14, IsTextSelectionEnabled = true });
        net.Children.Add(Hint(S.F("PortLabel", model.Net.ListenPort ?? UdpTransport.FixedPort) + S["Separator"] + S["FirewallHint"]));
    }

    private async Task EnterCodeAsync()
    {
        var S = Strings.Current;
        var box = new TextBox { PlaceholderText = "XXXXX-XXXXX", CharacterCasing = CharacterCasing.Upper, MaxLength = 16 };
        var error = new TextBlock { Foreground = B("TkCriticalText"), TextWrapping = TextWrapping.Wrap, Visibility = Visibility.Collapsed, Text = S["InvalidCode"] };
        var panel = new StackPanel { Spacing = 10 };
        panel.Children.Add(new TextBlock { Text = S["EnterCodeExplain"], TextWrapping = TextWrapping.Wrap });
        panel.Children.Add(box);
        panel.Children.Add(Hint(S["EnterCodeRule"]));
        panel.Children.Add(error);
        var dialog = new ContentDialog
        {
            Title = S["EnterCodeTitle"], Content = panel, PrimaryButtonText = S["Save"], CloseButtonText = S["Cancel"],
            DefaultButton = ContentDialogButton.Primary,
        };
        dialog.PrimaryButtonClick += (_, args) =>
        {
            if (Pairing.Normalize(box.Text) is null) { args.Cancel = true; error.Visibility = Visibility.Visible; return; }
            model.SetPairingCode(box.Text);
        };
        await ShowDialog(dialog);
        ShowPage();
    }

    private void UpdatesPage()
    {
        var S = Strings.Current;
        Heading(S["PageUpdates"]);
        var card = Card();
        card.Children.Add(new TextBlock { Text = S.F("CurrentVersion", AppModel.Version), FontSize = 14 });
        card.Children.Add(Hint(S["TestVersionNote"]));
        card.Children.Add(Hint(S["UpdatesZipNote"]));
        var open = new Button { Content = S["OpenReleases"] };
        open.Click += (_, _) => AppModel.OpenUrl(AppModel.ReleasesPage);
        card.Children.Add(open);
    }

    private void GeneralPage()
    {
        var S = Strings.Current;
        Heading(S["PageGeneral"]);
        var card = Card();
        var langRow = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 12 };
        langRow.Children.Add(new TextBlock { Text = S["Language"], FontSize = 14, VerticalAlignment = VerticalAlignment.Center });
        var lang = new ComboBox { MinWidth = 200 };
        string[] codes = ["system", "en", "ja"];
        lang.Items.Add(S["LanguageSystem"]);
        lang.Items.Add("English");
        lang.Items.Add("日本語");
        lang.SelectedIndex = Math.Max(0, Array.IndexOf(codes, model.Settings.Language));
        lang.SelectionChanged += (_, _) =>
        {
            if (lang.SelectedIndex >= 0 && codes[lang.SelectedIndex] != model.Settings.Language)
                DispatcherQueue.TryEnqueue(() => model.SetLanguage(codes[lang.SelectedIndex]));
        };
        langRow.Children.Add(lang);
        card.Children.Add(langRow);
        card.Children.Add(new Rectangle { Height = 1, Fill = B("TkCardStroke") });

        bool startup;
        try { startup = StartupRegistration.IsEnabled; } catch (Exception) { startup = false; }
        var signIn = new ToggleSwitch { Header = S["StartAtSignIn"], IsOn = startup };
        signIn.Toggled += (_, _) =>
        {
            try { StartupRegistration.Set(signIn.IsOn); }
            catch (Exception e) { model.Log("Start at sign-in could not be changed: " + e.Message); }
        };
        card.Children.Add(signIn);
        var tray = new ToggleSwitch { Header = S["CloseToTray"], IsOn = model.Settings.CloseToTray };
        tray.Toggled += (_, _) => model.SetCloseToTray(tray.IsOn);
        card.Children.Add(tray);
        card.Children.Add(Hint(S["CloseToTrayHelp"]));
        card.Children.Add(new Rectangle { Height = 1, Fill = B("TkCardStroke") });
        card.Children.Add(new TextBlock { Text = S["ShortcutsTitle"], FontSize = 14, FontWeight = FontWeights.SemiBold });
        card.Children.Add(Hint(S.F("ShortcutsList", model.Settings.HotkeyKeyCapture, model.Settings.HotkeyAllNotesOff)));
        var logs = new Button { Content = S["ShowLogs"] };
        logs.Click += (_, _) =>
        {
            Directory.CreateDirectory(model.LogDirectory);
            AppModel.OpenUrl(model.LogDirectory);
        };
        card.Children.Add(logs);
    }
}
