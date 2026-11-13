using Microsoft.UI.Text;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using TwinKeys.App.Platform;
using TwinKeys.App.ViewModels;
using TwinKeys.Core;

namespace TwinKeys.App.Views;

/// <summary>
/// First run (docs/design-windows.md 3.4): choose how cues reach Live and send one test note.
/// Phase 1 offers the loopback port (M1); the virtual device (M2) and the Bridge-only way (M3) are
/// shown but not selectable yet.
/// </summary>
public sealed partial class FirstRunWindow : Window
{
    private readonly AppModel model;
    private readonly Microsoft.UI.Dispatching.DispatcherQueueTimer timer;

    internal FirstRunWindow(AppModel model)
    {
        this.model = model;
        InitializeComponent();
        ExtendsContentIntoTitleBar = true;
        SetTitleBar(AppTitleBar);
        AppWindow.SetIcon(WindowHelpers.AssetPath("TwinKeys.ico"));
        WindowHelpers.Resize(this, 640, 600);
        Build();
        // The port may be created while this window is open: look again every 2 s.
        timer = DispatcherQueue.CreateTimer();
        timer.Interval = TimeSpan.FromSeconds(2);
        timer.Tick += (_, _) => { model.Midi.Rescan(); Build(); };
        timer.Start();
        Closed += (_, _) => timer.Stop();
    }

    private static Brush B(string key) => (Brush)Application.Current.Resources[key];

    private void Build()
    {
        var S = Strings.Current;
        Title = S["FirstRunTitle"];
        TitleText.Text = S["FirstRunTitle"];
        Heading.Text = S["FirstRunHeading"];
        Subtitle.Text = S["FirstRunSubtitle"];
        TestLabel.Text = S.F("TestSendLabel", model.Settings.MidiPortName);
        TestButton.Content = S["TestSend"];
        LaterButton.Content = S["Later"];
        NextButton.Content = S["Next"];
        Options.Children.Clear();
        bool found = model.Midi.Current is WinMmMidiOut.Status.Ready;
        string loopStatus = model.Midi.Current switch
        {
            WinMmMidiOut.Status.Ready r => "● " + S.F("FoundPort", r.PortName) + (model.TestSendWorked ? S["SentHere"] : ""),
            _ => "○ " + S.F("PortMissingCreate", model.Settings.MidiPortName),
        };
        Options.Children.Add(Option(S["ModeLoopback"], S["ModeLoopbackDetail"], loopStatus, found ? "TkSuccess" : "TkCaution", selected: true, enabled: true));
        Options.Children.Add(Option(S["ModeVirtual"], S["ModeVirtualDetail"], "○ " + S["ModeVirtualUnavailable"], "TkTertiaryText", selected: false, enabled: false));
        Options.Children.Add(Option(S["ModeBridge"], S["ModeBridgeDetail"], "○ " + S["ModeBridgeUnavailable"], "TkTertiaryText", selected: false, enabled: false));
    }

    private static Border Option(string title, string detail, string status, string statusBrush, bool selected, bool enabled)
    {
        var grid = new Grid { ColumnSpacing = 14 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        var radio = new RadioButton { IsChecked = selected, IsEnabled = enabled, MinWidth = 0, VerticalAlignment = VerticalAlignment.Top, GroupName = "firstrun" };
        grid.Children.Add(radio);
        var text = new StackPanel { Spacing = 2 };
        Grid.SetColumn(text, 1);
        text.Children.Add(new TextBlock { Text = title, FontSize = 16, FontWeight = FontWeights.SemiBold, TextWrapping = TextWrapping.Wrap, Opacity = enabled ? 1 : 0.85 });
        text.Children.Add(new TextBlock { Text = detail, FontSize = 13, Foreground = B("TkSecondaryText"), TextWrapping = TextWrapping.Wrap });
        text.Children.Add(new TextBlock { Text = status, FontSize = 12, Foreground = B(statusBrush), FontWeight = enabled ? FontWeights.SemiBold : FontWeights.Normal, TextWrapping = TextWrapping.Wrap });
        grid.Children.Add(text);
        return new Border
        {
            Padding = new Thickness(16, 12, 16, 12),
            CornerRadius = new CornerRadius(8),
            BorderThickness = new Thickness(selected ? 2 : 1),
            BorderBrush = selected ? B("TkAccent") : B("TkCardStroke"),
            Background = selected ? B("TkSelectedRow") : B("TkCardBackground"),
            Child = grid,
        };
    }

    private async void OnTest(object sender, RoutedEventArgs e)
    {
        var S = Strings.Current;
        TestButton.IsEnabled = false;
        bool ok = await model.TestSendAsync();
        TestResult.Visibility = Visibility.Visible;
        TestResult.Text = ok ? S["TestSendDone"] : S.F("PortMissingCreate", model.Settings.MidiPortName);
        TestButton.IsEnabled = true;
        Build();
    }

    private void OnLater(object sender, RoutedEventArgs e) => Close();

    private void OnNext(object sender, RoutedEventArgs e)
    {
        model.SetMidiOutput(MidiOutputMode.Loopback, model.Settings.MidiPortName);
        model.FinishFirstRun();
        Close();
    }
}
