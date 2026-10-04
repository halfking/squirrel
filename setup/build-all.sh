#!/usr/bin/env bash
#  build-all.sh — build the Squirrel setup programs for macOS, Windows and Linux.
#
#  Every platform is a separate native implementation that shares the same
#  payload (rime-config/default.custom.yaml + setup/shared/presets.json) and the
#  same five-step flow, so a user on any of them ends up with the same Rime setup.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${OUT_DIR:-$SCRIPT_DIR/dist}"
VERSION="${VERSION:-1.0.0}"
PLATFORMS="${PLATFORMS:-macos windows linux}"

# Toolchain overrides (useful on a clean machine / CI):
#   SWIFT   — path to the Swift driver            (macOS)
#   DOTNET  — path to the dotnet muxer            (Windows)
#   ZIG     — path to zig, enables cross-compile (Linux)
#   SYSROOT — Debian sysroot for the Linux cross build
: "${SWIFT:=swift}"
: "${DOTNET:=dotnet}"
: "${ZIG:=}"
: "${SYSROOT:=/tmp/sysroot}"
PYTHON="${PYTHON:-python3}"

say() { printf '\n\033[1;32m######## %s\033[0m\n' "$*"; }

mkdir -p "$OUT_DIR"

for platform in $PLATFORMS; do
  case "$platform" in
    macos)
      say "构建 macOS (Swift / AppKit)"
      ( cd "$SCRIPT_DIR/macos" && SWIFT="$SWIFT" OUT_DIR="$OUT_DIR" VERSION="$VERSION" ./build.sh )
      ;;
    windows)
      say "构建 Windows (C# / WPF)"
      ( cd "$SCRIPT_DIR/windows" && DOTNET="$DOTNET" OUT_DIR="$OUT_DIR" VERSION="$VERSION" ./build.sh )
      ;;
    linux)
      say "构建 Linux x86_64 (C / GTK 3)"
      ( cd "$SCRIPT_DIR/linux" && ZIG="$ZIG" SYSROOT="$SYSROOT" PYTHON="$PYTHON" \
          OUT_DIR="$OUT_DIR" VERSION="$VERSION" ./build.sh )
      if [ -n "$ZIG" ] && [ -d "${SYSROOT}-arm64" ]; then
        say "构建 Linux aarch64 (C / GTK 3)"
        ( cd "$SCRIPT_DIR/linux" && TARGET=aarch64-linux-gnu ZIG="$ZIG" SYSROOT="${SYSROOT}-arm64" \
            PYTHON="$PYTHON" OUT_DIR="$OUT_DIR" VERSION="$VERSION" ./build.sh )
      fi
      ;;
    *)
      echo "未知平台 / unknown platform: $platform" >&2
      exit 1
      ;;
  esac
done

say "汇总校验和"
( cd "$OUT_DIR" && shasum -a 256 ./*.dmg ./*.zip ./*.exe ./*.tar.gz > SHA256SUMS.txt 2>/dev/null || true )

say "全部产物："
ls -lh "$OUT_DIR" | sed 's/^/    /'
cat "$OUT_DIR/SHA256SUMS.txt" 2>/dev/null | sed 's/^/    /'
