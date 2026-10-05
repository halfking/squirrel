using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;

namespace SquirrelSetup.Core;

public enum StepState
{
    Pending,
    Running,
    Done,
    Skipped,
    Failed
}

public sealed record Step(string Id, string Title, string Subtitle, bool NeedsAdmin = false);

public static class Steps
{
    public static readonly IReadOnlyList<Step> All = new List<Step>
    {
        new("detect",  "检测运行环境",         "识别系统版本、已安装的小狼毫与用户配置"),
        new("engine",  "安装小狼毫 Weasel",    "下载官方安装包并静默安装（需要管理员权限）", true),
        new("config",  "写入用户配置",         "部署 default.custom.yaml（五笔 / 朙月拼音 / 左 Shift 切换）"),
        new("presets", "安装词库与方案",       "按 plum 方案下载 wubi86、五笔·拼音、朙月拼音词库"),
        new("deploy",  "编译并启用输入法",     "运行 WeaselDeployer /deploy 重新编译"),
        new("done",    "完成",                 "打开配置目录或开始使用")
    };
}

public interface IInstallerSink
{
    void OnStep(string id, StepState state, string detail);
    void OnLog(string line, LogLevel level);
}

/// <summary>
/// Installs the Rime engine (Weasel) on Windows and deploys this repository's
/// shared user configuration, mirroring the macOS and Linux setup programs.
/// </summary>
public sealed class InstallerEngine
{
    private const string WeaselVersion = "0.17.4";
    private static readonly string[] WeaselInstallerUrls =
    {
        $"https://github.com/rime/weasel/releases/download/{WeaselVersion}/weasel-{WeaselVersion}.0-installer.exe",
        $"https://gh-proxy.com/https://github.com/rime/weasel/releases/download/{WeaselVersion}/weasel-{WeaselVersion}.0-installer.exe",
        $"https://ghfast.top/https://github.com/rime/weasel/releases/download/{WeaselVersion}/weasel-{WeaselVersion}.0-installer.exe"
    };

    private readonly IInstallerSink _sink;
    private readonly Dictionary<string, StepState> _states = new();

    public InstallerEngine(IInstallerSink sink)
    {
        _sink = sink;
        foreach (var step in Steps.All)
        {
            _states[step.Id] = StepState.Pending;
        }
    }

    public static string RimeUserDir => Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Rime");

    /// <summary>Locate WeaselDeployer.exe in C:\Program Files\Rime\weasel-*\.</summary>
    public static string? FindWeaselDeployer()
    {
        foreach (var root in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                                     Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) })
        {
            var rimeDir = Path.Combine(root, "Rime");
            if (!Directory.Exists(rimeDir))
            {
                continue;
            }
            var candidate = Directory.GetDirectories(rimeDir, "weasel-*")
                .Select(dir => Path.Combine(dir, "WeaselDeployer.exe"))
                .FirstOrDefault(File.Exists);
            if (candidate is not null)
            {
                return candidate;
            }
        }
        return null;
    }

    public static bool IsWeaselInstalled() => FindWeaselDeployer() is not null;

    /// <summary>
    /// Installed Weasel version parsed from the weasel-X.Y.Z* install directory
    /// name, or null when not installed / not parseable. Only checking that
    /// WeaselDeployer.exe exists would silently skip upgrades on machines with
    /// an older engine (e.g. 0.16.x), whose data lacks the newer schema keys.
    /// </summary>
    public static Version? InstalledWeaselVersion()
    {
        Version? best = null;
        foreach (var root in new[] { Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles),
                                     Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86) })
        {
            var rimeDir = Path.Combine(root, "Rime");
            if (!Directory.Exists(rimeDir))
            {
                continue;
            }
            foreach (var dir in Directory.GetDirectories(rimeDir, "weasel-*"))
            {
                var text = Path.GetFileName(dir)["weasel-".Length..];
                var numbers = new List<int>();
                foreach (var part in text.Split('.'))
                {
                    if (!int.TryParse(part.Trim(), out var n))
                    {
                        break;
                    }
                    numbers.Add(n);
                }
                if (numbers.Count == 0)
                {
                    continue;
                }
                while (numbers.Count < 4)
                {
                    numbers.Add(0);
                }
                var version = new Version(numbers[0], numbers[1], numbers[2], numbers[3]);
                if (best is null || version > best)
                {
                    best = version;
                }
            }
        }
        return best;
    }

    private static Version TargetWeaselVersion()
    {
        var parts = WeaselVersion.Split('.');
        var numbers = parts.Select(p => int.TryParse(p, out var n) ? n : 0).ToList();
        while (numbers.Count < 4)
        {
            numbers.Add(0);
        }
        return new Version(numbers[0], numbers[1], numbers[2], numbers[3]);
    }

    public Task DetectOnlyAsync()
    {
        _sink.OnStep("detect", StepState.Running, "");
        return DetectAsync(_sink);
    }

    public Task<bool> RunAllAsync(CancellationToken token = default)
    {
        return RunAllCoreAsync(token);
    }

    private async Task<bool> RunAllCoreAsync(CancellationToken token)
    {
        bool success = true;
        var steps = new (string Id, Func<IInstallerSink, Task> Body)[]
        {
            ("detect",  DetectAsync),
            ("engine",  EngineAsync),
            ("config",  ConfigAsync),
            ("presets", PresetsAsync),
            ("deploy",  DeployAsync)
        };

        foreach (var (id, body) in steps)
        {
            token.ThrowIfCancellationRequested();
            _sink.OnStep(id, StepState.Running, "");
            try
            {
                await body(_sink).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                success = false;
                _sink.OnStep(id, StepState.Failed, ex.Message.Split('\n')[0]);
                _sink.OnLog(ex.Message, LogLevel.Error);
                break;
            }
        }

        _sink.OnStep("done", success ? StepState.Done : StepState.Failed,
                     success ? "" : "请查看上方日志后重试");
        if (success)
        {
            _sink.OnLog("全部完成，可以开始使用了。", LogLevel.Ok);
        }
        return success;
    }

    // ---- Step 1: detect -------------------------------------------------

    private async Task DetectAsync(IInstallerSink sink)
    {
        sink.OnLog("── 1/5 检测运行环境 / Detecting environment", LogLevel.Info);

        var os = Environment.OSVersion;
        var arch = System.Runtime.InteropServices.RuntimeInformation.OSArchitecture.ToString();
        sink.OnLog($"Windows {os.Version.Major}.{os.Version.Minor}.{os.Version.Build} · {arch}", LogLevel.Detail);

        var deployer = FindWeaselDeployer();
        var installedVersion = InstalledWeaselVersion();
        if (deployer is not null)
        {
            sink.OnLog($"已安装小狼毫：{deployer}（版本 {(installedVersion?.ToString() ?? "未知")}）", LogLevel.Ok);
        }
        else
        {
            sink.OnLog("未检测到小狼毫 Weasel，将下载官方安装包。", LogLevel.Warn);
        }

        if (Directory.Exists(RimeUserDir))
        {
            var count = Directory.GetFiles(RimeUserDir).Length;
            sink.OnLog($"Rime 用户目录：{RimeUserDir}（{count} 个文件）", LogLevel.Detail);
            if (Directory.Exists(Path.Combine(RimeUserDir, "build")))
            {
                sink.OnLog("已存在编译产物 build\\，本次部署会重新编译。", LogLevel.Detail);
            }
        }
        else
        {
            sink.OnLog($"Rime 用户目录尚未创建：{RimeUserDir}", LogLevel.Detail);
        }

        sink.OnLog(Proc.IsAdministrator()
            ? "管理员权限：已获取"
            : "管理员权限：安装小狼毫时会弹出 UAC 授权框", LogLevel.Detail);

        // 与 macOS / Linux 一致：探测首选方案镜像，提前暴露网络问题。
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
            const string probeUrl = "https://cdn.jsdelivr.net/gh/rime/rime-wubi@master/wubi86.schema.yaml";
            var data = await Net.GetAnyAsync(new[] { probeUrl }, cts.Token).ConfigureAwait(false);
            sink.OnLog(data.Length > 0
                ? "网络：可访问 plum 方案镜像（jsDelivr）"
                : "网络：jsDelivr 返回空响应，运行时将自动尝试其他镜像。",
                data.Length > 0 ? LogLevel.Ok : LogLevel.Warn);
        }
        catch (Exception ex)
        {
            sink.OnLog($"网络：jsDelivr 不可达（{ex.Message.Split('\n')[0]}），运行时将自动尝试其他镜像。", LogLevel.Warn);
        }

        sink.OnStep("detect", StepState.Done, $"Windows {os.Version.Major}.{os.Version.Minor}");
    }

    // ---- Step 2: engine -------------------------------------------------

    private async Task EngineAsync(IInstallerSink sink)
    {
        sink.OnLog("── 2/5 安装小狼毫 Weasel / Installing Weasel", LogLevel.Info);

        // 只看「WeaselDeployer.exe 存在」会漏掉引擎升级：旧版（如 0.16.x）
        // 目录里照样有部署器。这里比对安装目录名里的版本号，低于目标版本
        // 就走安装流程更新引擎。
        var installed = InstalledWeaselVersion();
        if (installed is not null)
        {
            var target = TargetWeaselVersion();
            if (installed >= target)
            {
                sink.OnLog($"小狼毫已安装（{installed} ≥ {WeaselVersion}），跳过安装。", LogLevel.Detail);
                sink.OnStep("engine", StepState.Skipped, $"已安装 {installed}");
                return;
            }
            sink.OnLog($"已安装小狼毫 {installed} 低于目标版本 {WeaselVersion}，将下载并安装更新。", LogLevel.Info);
        }

        var temp = Path.Combine(Path.GetTempPath(), $"weasel-{WeaselVersion}.0-installer.exe");
        sink.OnLog($"下载小狼毫 {WeaselVersion} 安装包…", LogLevel.Detail);
        var data = await Net.GetAnyAsync(WeaselInstallerUrls).ConfigureAwait(false);
        await File.WriteAllBytesAsync(temp, data).ConfigureAwait(false);
        sink.OnLog($"已下载 {Fmt.Bytes(data.Length)} → {temp}", LogLevel.Ok);

        sink.OnLog("启动安装程序（/S 静默安装），请在 UAC 弹窗中允许…", LogLevel.Detail);
        var result = await Proc.RunAsync(temp, new[] { "/S" }, elevated: true).ConfigureAwait(false);
        File.Delete(temp);

        var deployer = FindWeaselDeployer();
        if (deployer is null)
        {
            throw new InvalidOperationException(
                $"小狼毫安装后未找到 WeaselDeployer.exe（安装程序退出码 {result.ExitCode}）。" +
                "可手动运行 https://github.com/rime/weasel/releases 下载安装后重试。");
        }
        sink.OnLog($"安装完成：{deployer}", LogLevel.Ok);
        sink.OnStep("engine", StepState.Done, WeaselVersion);
    }

    // ---- Step 3: config -------------------------------------------------

    private async Task ConfigAsync(IInstallerSink sink)
    {
        sink.OnLog("── 3/5 写入用户配置 / Writing user config", LogLevel.Info);

        var payload = Payload.ReadResource("default.custom.yaml");
        Directory.CreateDirectory(RimeUserDir);
        var dest = Path.Combine(RimeUserDir, "default.custom.yaml");

        if (File.Exists(dest) && File.ReadAllBytes(dest).SequenceEqual(payload))
        {
            sink.OnLog("default.custom.yaml 已是最新内容，跳过写入。", LogLevel.Detail);
            sink.OnStep("config", StepState.Skipped, "已是最新");
            return;
        }
        if (File.Exists(dest))
        {
            var backup = dest + $".bak-{DateTime.Now:yyyyMMdd-HHmmss}";
            File.Copy(dest, backup);
            sink.OnLog($"已备份原配置 → {Path.GetFileName(backup)}", LogLevel.Detail);
        }
        await File.WriteAllBytesAsync(dest, payload).ConfigureAwait(false);
        sink.OnLog($"写入 {dest}", LogLevel.Ok);
        sink.OnLog("  方案：五笔·拼音 / 朙月拼音·简体 / 五笔86", LogLevel.Detail);
        sink.OnLog("  中英切换：左 Shift（打字中途按下则编码原样上屏）", LogLevel.Detail);
        sink.OnStep("config", StepState.Done, "default.custom.yaml");
    }

    // ---- Step 4: presets ------------------------------------------------

    private async Task PresetsAsync(IInstallerSink sink)
    {
        sink.OnLog("── 4/5 安装词库与方案（plum 方案）/ Installing plum presets", LogLevel.Info);

        var manifest = Presets.Load();
        Directory.CreateDirectory(RimeUserDir);

        var written = 0;
        var skipped = 0;
        long total = 0;

        foreach (var package in manifest.packages)
        {
            sink.OnLog($"方案包 {package.name}：{package.description}", LogLevel.Detail);
            foreach (var file in package.files)
            {
                var dest = Path.Combine(RimeUserDir, file);
                if (File.Exists(dest) && new FileInfo(dest).Length > 0)
                {
                    sink.OnLog($"  · {file} 已存在（{Fmt.Bytes(new FileInfo(dest).Length)}），跳过下载", LogLevel.Detail);
                    skipped++;
                    continue;
                }
                try
                {
                    var urls = Net.ExpandMirrors(manifest.mirrors, package.repo, package.mirror, package.@ref, file);
                    var data = await Net.GetAnyAsync(urls).ConfigureAwait(false);
                    await File.WriteAllBytesAsync(dest, data).ConfigureAwait(false);
                    total += data.Length;
                    written++;
                    sink.OnLog($"  ✓ {file} ← {package.repo}/{file} ({Fmt.Bytes(data.Length)})", LogLevel.Ok);
                }
                catch (Exception ex)
                {
                    sink.OnLog($"  ✕ {file} 下载失败：{ex.Message.Split('\n')[0]}", LogLevel.Error);
                }
            }
        }

        if (written == 0 && skipped == 0)
        {
            throw new InvalidOperationException("没有成功下载任何方案文件，请检查网络后重试。");
        }
        sink.OnLog($"方案文件就绪：新写入 {written} 个，跳过 {skipped} 个，共 {Fmt.Bytes(total)}", LogLevel.Ok);
        sink.OnStep("presets", StepState.Done, $"{written + skipped} 个方案文件");
    }

    // ---- Step 5: deploy -------------------------------------------------

    private async Task DeployAsync(IInstallerSink sink)
    {
        sink.OnLog("── 5/5 编译并启用输入法 / Building and enabling", LogLevel.Info);

        var deployer = FindWeaselDeployer()
            ?? throw new InvalidOperationException("找不到 WeaselDeployer.exe，请先完成步骤 2。");

        sink.OnLog("运行 WeaselDeployer /deploy（编译词库，通常需要 5–30 秒）…", LogLevel.Detail);
        var result = await Proc.RunAsync(deployer, new[] { "/deploy" },
            line => sink.OnLog(line, LogLevel.Detail)).ConfigureAwait(false);
        if (result.ExitCode != 0)
        {
            throw new InvalidOperationException($"WeaselDeployer /deploy 退出码 {result.ExitCode}");
        }

        var built = Path.Combine(RimeUserDir, "build", "default.yaml");
        if (File.Exists(built))
        {
            var text = File.ReadAllText(built, Encoding.UTF8);
            // 只查 "commit_code" 子串太弱：任何一个键映射到 commit_code 都会让它通过。
            // 这里逐行确认 Shift_L 真的映射到 commit_code（左 Shift 中英切换）。
            var shiftToggle = text.Split('\n')
                .Any(line => line.Trim().Equals("Shift_L: commit_code", StringComparison.Ordinal));
            if (shiftToggle)
            {
                sink.OnLog("编译产物 build\\default.yaml：Shift_L: commit_code（左 Shift 中英切换）✓", LogLevel.Ok);
            }
            else
            {
                sink.OnLog("警告：build\\default.yaml 中 Shift_L 未映射到 commit_code，请检查 default.custom.yaml 是否生效。", LogLevel.Warn);
            }
            var buildDir = Path.Combine(RimeUserDir, "build");
            var count = Directory.GetFiles(buildDir).Length;
            sink.OnLog($"编译产物：{count} 个文件", LogLevel.Detail);
        }
        else
        {
            sink.OnLog("警告：未生成 build\\default.yaml，部署可能未成功。", LogLevel.Warn);
        }

        sink.OnLog("小狼毫已部署。托盘出现输入法图标，在设置中添加「小狼毫」即可使用。", LogLevel.Ok);
        sink.OnStep("deploy", StepState.Done, "已部署");
    }
}
