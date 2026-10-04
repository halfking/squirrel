#!/usr/bin/env bash
#  build.sh — publish the Windows (WPF) setup program as a single self-contained .exe
#
#  Requires the .NET SDK (any recent version). Works on macOS/Linux thanks to
#  <EnableWindowsTargeting>true</EnableWindowsTargeting> in the csproj.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$SETUP_DIR/.." && pwd)"
OUT_DIR="${OUT_DIR:-$SETUP_DIR/dist}"
VERSION="${VERSION:-1.0.0}"
RID="${RID:-win-x64}"

DOTNET="${DOTNET:-dotnet}"
command -v "$DOTNET" >/dev/null 2>&1 || DOTNET="/tmp/dl/dotnet/dotnet"
[ -x "$DOTNET" ] || { echo "找不到 dotnet SDK，请先安装 .NET SDK 8+ 或设置 DOTNET=/path/to/dotnet" >&2; exit 1; }

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

mkdir -p "$SCRIPT_DIR/Resources" "$OUT_DIR"

say "准备内置负载"
cp "$REPO_DIR/rime-config/default.custom.yaml" "$SCRIPT_DIR/Resources/default.custom.yaml"
cp "$SETUP_DIR/shared/presets.json" "$SCRIPT_DIR/Resources/presets.json"

# Minimal application icon: a blue rounded square with a light glyph block.
if [ ! -f "$SCRIPT_DIR/Resources/Setup.ico" ]; then
  say "生成应用图标"
  python3 "$SCRIPT_DIR/tools/make_icon.py" "$SCRIPT_DIR/Resources/Setup.ico"
fi

say "发布 WPF 单文件可执行程序 ($RID)"
cd "$SCRIPT_DIR"
"$DOTNET" publish SquirrelSetup.csproj -c Release -r "$RID" -o "$OUT_DIR/publish" \
  -p:Version="$VERSION" --nologo

EXE="$OUT_DIR/publish/SquirrelSetup.exe"
[ -f "$EXE" ] || { echo "发布失败：未生成 $EXE" >&2; exit 1; }

say "整理产物"
mv "$EXE" "$OUT_DIR/SquirrelSetup-$VERSION-windows-x64.exe"
cp "$OUT_DIR/publish/SquirrelSetup.pdb" "$OUT_DIR/" 2>/dev/null || true
if [ -d "$OUT_DIR/publish" ]; then mv "$OUT_DIR/publish" "${TMPDIR:-/tmp}/squirrel-publish-$$"; fi
cp "$SCRIPT_DIR/Resources/presets.json" "$OUT_DIR/presets.json" 2>/dev/null || true

cat > "$OUT_DIR/Windows-使用说明.txt" <<TXT
Squirrel 鼠鬚管安装程序 (Windows x64)

1. 双击 SquirrelSetup-<版本>-windows-x64.exe（Windows 10/11 x64，无需预装 .NET）；
2. 点击「开始安装」，按提示完成 5 个步骤：
   检测环境 → 安装小狼毫 Weasel（UAC 提权）→ 写入用户配置
   → 下载 plum 词库方案 → 编译部署；
3. 完成后到「设置 › 时间和语言 › 语言和区域 › 输入法」中添加「小狼毫」。

用户配置目录：%APPDATA%\Rime
共享配置来源：rime-config/default.custom.yaml
TXT

say "生成校验和"
( cd "$OUT_DIR" && shasum -a 256 ./*.exe > SHA256SUMS-windows.txt )

say "产物："
ls -lh "$OUT_DIR" | sed 's/^/    /'
