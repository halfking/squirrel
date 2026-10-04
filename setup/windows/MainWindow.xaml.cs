using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using SquirrelSetup.Core;

namespace SquirrelSetup;

public partial class MainWindow : Window, IInstallerSink
{
    private readonly Dictionary<string, (TextBlock glyph, TextBlock title, TextBlock detail)> _rows = new();
    private InstallerEngine? _engine;
    private bool _busy;

    public MainWindow()
    {
        InitializeComponent();
        BuildStepRows();
        Subtitle.Text = "为 macOS / Windows / Linux 提供同一套 Rime 配置 · Windows 版 · v1.0.0";
        _engine = new InstallerEngine(this);
        Loaded += async (_, _) => await _engine!.DetectOnlyAsync();
    }

    private void BuildStepRows()
    {
        foreach (var step in Steps.All)
        {
            var grid = new Grid { Margin = new Thickness(0, 3, 0, 3) };
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(26) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(190) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(200) });

            var glyph = new TextBlock
            {
                Text = "○",
                FontSize = 15,
                Foreground = Brushes.Gainsboro,
                VerticalAlignment = VerticalAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Center
            };
            var title = new TextBlock
            {
                Text = step.Title,
                FontSize = 14,
                FontWeight = FontWeights.Medium,
                Foreground = Brushes.Black,
                VerticalAlignment = VerticalAlignment.Center
            };
            var subtitle = new TextBlock
            {
                Text = step.Subtitle,
                FontSize = 12,
                Foreground = Brushes.DimGray,
                TextTrimming = TextTrimming.CharacterEllipsis,
                VerticalAlignment = VerticalAlignment.Center,
                Margin = new Thickness(0, 0, 10, 0)
            };
            var detail = new TextBlock
            {
                Text = "",
                FontSize = 12,
                Foreground = Brushes.Gray,
                TextTrimming = TextTrimming.CharacterEllipsis,
                TextAlignment = TextAlignment.Right,
                VerticalAlignment = VerticalAlignment.Center
            };

            Grid.SetColumn(glyph, 0);
            Grid.SetColumn(title, 1);
            Grid.SetColumn(subtitle, 2);
            Grid.SetColumn(detail, 3);
            grid.Children.Add(glyph);
            grid.Children.Add(title);
            grid.Children.Add(subtitle);
            grid.Children.Add(detail);
            StepPanel.Children.Add(grid);
            _rows[step.Id] = (glyph, title, detail);
        }
    }

    private async void OnInstallClick(object sender, RoutedEventArgs e)
    {
        if (_busy || _engine is null)
        {
            return;
        }
        SetBusy(true);
        StatusText.Text = "正在安装，请勿关闭窗口…";
        var success = await _engine.RunAllAsync();
        StatusText.Text = success
            ? "安装完成 ✅ 请在「设置 › 时间和语言 › 语言和区域 › 输入法」中添加小狼毫。"
            : "安装未完成，请根据日志排查后点击「开始安装」重试。";
        StatusText.Foreground = success ? Brushes.ForestGreen : Brushes.Firebrick;
        SetBusy(false);
    }

    private async void OnDetectClick(object sender, RoutedEventArgs e)
    {
        if (_busy || _engine is null)
        {
            return;
        }
        LogBox.Clear();
        SetBusy(true);
        await _engine.DetectOnlyAsync();
        SetBusy(false);
    }

    private void OnRevealClick(object sender, RoutedEventArgs e)
    {
        Directory.CreateDirectory(InstallerEngine.RimeUserDir);
        Proc.OpenFolder(InstallerEngine.RimeUserDir);
    }

    private void OnCloseClick(object sender, RoutedEventArgs e) => Close();

    private void SetBusy(bool busy)
    {
        _busy = busy;
        InstallButton.IsEnabled = !busy;
        DetectButton.IsEnabled = !busy;
    }

    // ---- IInstallerSink (all calls arrive on a worker thread) ------------

    void IInstallerSink.OnStep(string id, StepState state, string detail)
    {
        Dispatcher.Invoke(() =>
        {
            if (!_rows.TryGetValue(id, out var row))
            {
                return;
            }
            row.detail.Text = state switch
            {
                StepState.Running => "进行中…",
                StepState.Done => detail,
                StepState.Skipped => detail,
                StepState.Failed => detail,
                _ => ""
            };
            switch (state)
            {
                case StepState.Pending:
                    row.glyph.Text = "○";
                    row.glyph.Foreground = Brushes.Gainsboro;
                    break;
                case StepState.Running:
                    row.glyph.Text = "◐";
                    row.glyph.Foreground = Brushes.DarkOrange;
                    break;
                case StepState.Done:
                    row.glyph.Text = "✓";
                    row.glyph.Foreground = Brushes.ForestGreen;
                    break;
                case StepState.Skipped:
                    row.glyph.Text = "⊘";
                    row.glyph.Foreground = Brushes.Gray;
                    break;
                case StepState.Failed:
                    row.glyph.Text = "✕";
                    row.glyph.Foreground = Brushes.Firebrick;
                    break;
            }
            var index = Steps.All.ToList().FindIndex(s => s.Id == id);
            if (index >= 0 && state is StepState.Done or StepState.Skipped or StepState.Failed)
            {
                Progress.Value = index + 1;
            }
        });
    }

    void IInstallerSink.OnLog(string line, LogLevel level)
    {
        Dispatcher.Invoke(() =>
        {
            var (glyph, color) = level switch
            {
                LogLevel.Info => ("›", Brushes.Black),
                LogLevel.Ok => ("✓", Brushes.ForestGreen),
                LogLevel.Warn => ("!", Brushes.DarkOrange),
                LogLevel.Error => ("✕", Brushes.Firebrick),
                _ => (" ", Brushes.DimGray)
            };
            LogBox.AppendText($"{glyph} {line}{Environment.NewLine}");
            LogBox.ScrollToEnd();
        });
    }
}
