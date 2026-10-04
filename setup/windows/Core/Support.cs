using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.IO;
using System.Reflection;
using System.Text;
using System.Text.Json;

namespace SquirrelSetup.Core;

public enum LogLevel
{
    Info,
    Ok,
    Warn,
    Error,
    Detail
}

public static class Payload
{
    public static byte[] ReadResource(string name)
    {
        var assembly = Assembly.GetExecutingAssembly();
        using var stream = assembly.GetManifestResourceStream($"SquirrelSetup.Resources.{name}")
            ?? throw new InvalidOperationException($"安装包缺少内置文件 / bundled resource missing: {name}");
        using var memory = new MemoryStream();
        stream.CopyTo(memory);
        return memory.ToArray();
    }
}

public static class Presets
{
    public sealed class Spec
    {
        public string name { get; set; } = "";
        public string repo { get; set; } = "";
        public string mirror { get; set; } = "";
        public string @ref { get; set; } = "";
        public string description { get; set; } = "";
        public string[] files { get; set; } = Array.Empty<string>();
    }

    public sealed class Manifest
    {
        public string[] mirrors { get; set; } = Array.Empty<string>();
        public Spec[] packages { get; set; } = Array.Empty<Spec>();
    }

    public static Manifest Load()
    {
        var json = Encoding.UTF8.GetString(Payload.ReadResource("presets.json"));
        return JsonSerializer.Deserialize<Manifest>(json, new JsonSerializerOptions
        {
            PropertyNameCaseInsensitive = true
        }) ?? throw new InvalidOperationException("presets.json 解析失败");
    }
}

public static class Net
{
    private static readonly HttpClient Client = new()
    {
        Timeout = TimeSpan.FromMinutes(10)
    };

    /// <summary>Download a byte array, trying each URL in order.</summary>
    public static async Task<byte[]> GetAnyAsync(IEnumerable<string> urls, CancellationToken token = default)
    {
        var reasons = new List<string>();
        foreach (var url in urls)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, url);
                request.Headers.TryAddWithoutValidation("User-Agent", "SquirrelSetup/1.0 (Windows)");
                using var response = await Client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token)
                    .ConfigureAwait(false);
                if (!response.IsSuccessStatusCode)
                {
                    reasons.Add($"{url} → HTTP {(int)response.StatusCode}");
                    continue;
                }
                return await response.Content.ReadAsByteArrayAsync(token).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                reasons.Add($"{url} → {ex.Message}");
            }
        }
        throw new InvalidOperationException("所有下载地址均失败 / all download sources failed:\n" + string.Join("\n", reasons));
    }

    public static IEnumerable<string> ExpandMirrors(IEnumerable<string> templates,
                                                   string repo, string mirror, string gitRef, string file)
    {
        foreach (var template in templates)
        {
            yield return template
                .Replace("{repo}", repo)
                .Replace("{mirror}", mirror)
                .Replace("{ref}", gitRef)
                .Replace("{file}", file);
        }
    }
}

public static class Proc
{
    public sealed record Result(int ExitCode, string Output);

    /// <summary>Run a command, streaming combined output line by line.</summary>
    public static async Task<Result> RunAsync(string fileName, IEnumerable<string> arguments,
                                              Action<string>? onOutput = null,
                                              bool elevated = false,
                                              CancellationToken token = default)
    {
        var info = new ProcessStartInfo
        {
            FileName = fileName,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        foreach (var argument in arguments)
        {
            info.ArgumentList.Add(argument);
        }
        if (elevated)
        {
            info.Verb = "runas";
            info.UseShellExecute = true;
            info.RedirectStandardOutput = false;
            info.RedirectStandardError = false;
        }

        using var process = new Process { StartInfo = info };
        var builder = new StringBuilder();
        process.Start();
        if (!elevated)
        {
            var stdout = process.StandardOutput.ReadToEndAsync();
            var stderr = process.StandardError.ReadToEndAsync();
            await process.WaitForExitAsync(token).ConfigureAwait(false);
            var text = (await stdout.ConfigureAwait(false)) + (await stderr.ConfigureAwait(false));
            builder.Append(text);
            if (onOutput is not null && !string.IsNullOrWhiteSpace(text))
            {
                foreach (var line in text.Split('\n'))
                {
                    if (line.Trim().Length > 0)
                    {
                        onOutput(line.TrimEnd('\r'));
                    }
                }
            }
        }
        else
        {
            await process.WaitForExitAsync(token).ConfigureAwait(false);
        }
        return new Result(process.ExitCode, builder.ToString());
    }

    public static async Task<Result> RunPowerShellAsync(string script, Action<string>? onOutput = null)
    {
        return await RunAsync("powershell.exe",
            new[] { "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script },
            onOutput).ConfigureAwait(false);
    }

    public static bool IsAdministrator()
    {
        try
        {
            using var identity = System.Security.Principal.WindowsIdentity.GetCurrent();
            var principal = new System.Security.Principal.WindowsPrincipal(identity);
            return principal.IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
        }
        catch
        {
            return false;
        }
    }

    [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern int ShellExecute(IntPtr hwnd, string lpOperation, string lpFile,
                                           string lpParameters, string lpDirectory, int nShowCmd);

    public static void OpenFolder(string path)
    {
        ShellExecute(IntPtr.Zero, "open", path, null, null, 1);
    }
}

public static class Fmt
{
    public static string Bytes(long bytes) => $"{bytes / 1048576.0:0.0} MB";
}
