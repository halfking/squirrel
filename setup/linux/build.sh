#!/usr/bin/env bash
#  build.sh — cross-compile the Linux (GTK 3) setup program.
#
#  Two supported paths:
#    * native:  ./build.sh                      (gcc + libgtk-3-dev on a Linux box)
#    * cross:   ZIG=/path/to/zig SYSROOT=/tmp/sysroot ./build.sh
#               builds a x86_64 (or aarch64) binary from macOS using zig cc and
#               a Debian sysroot created by tools/make_sysroot.py
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$SETUP_DIR/.." && pwd)"
OUT_DIR="${OUT_DIR:-$SETUP_DIR/dist}"
VERSION="${VERSION:-1.0.0}"
TARGET="${TARGET:-x86_64-linux-gnu}"
PYTHON="${PYTHON:-python3}"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

mkdir -p "$OUT_DIR" "$SCRIPT_DIR/build"

say "生成内置负载 payload.h"
"$PYTHON" "$SCRIPT_DIR/tools/embed.py" \
  "$REPO_DIR/rime-config/default.custom.yaml" \
  "$SETUP_DIR/shared/presets.json" \
  "$SCRIPT_DIR/build/payload.h"

if [ -n "${ZIG:-}" ]; then
  SYSROOT="${SYSROOT:-/tmp/sysroot}"
  LIBDIR="$SYSROOT/usr/lib/$TARGET"
  if [ ! -d "$SYSROOT" ]; then
    echo "错误：找不到 sysroot $SYSROOT，请先运行 tools/make_sysroot.py" >&2
    exit 1
  fi
  say "交叉编译 $TARGET (zig cc + $SYSROOT)"
  "$ZIG" cc -target "$TARGET.2.36" \
    -isystem "$SYSROOT/usr/include/gtk-3.0" \
    -isystem "$SYSROOT/usr/include/glib-2.0" \
    -isystem "$LIBDIR/glib-2.0/include" \
    -isystem "$SYSROOT/usr/include/cairo" \
    -isystem "$SYSROOT/usr/include/pango-1.0" \
    -isystem "$SYSROOT/usr/include/harfbuzz" \
    -isystem "$SYSROOT/usr/include/freetype2" \
    -isystem "$SYSROOT/usr/include/gdk-pixbuf-2.0" \
    -isystem "$SYSROOT/usr/include/atk-1.0" \
    -L"$LIBDIR" -L"$LIBDIR/gio-2.0" \
    -I"$SCRIPT_DIR/build" \
    -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
    -o "$SCRIPT_DIR/build/squirrel-setup" "$SCRIPT_DIR/src/squirrel_setup.c" \
    -lgtk-3 -lgdk-3 -lgobject-2.0 -lglib-2.0 -lpango-1.0 -lpangocairo-1.0 \
    -lpangoft2-1.0 -lcairo -lgdk_pixbuf-2.0 -latk-1.0 -lpthread
else
  say "本机编译 (gcc + libgtk-3-dev)"
  gcc -O2 -Wall -Wextra -Wno-unused-parameter -Wno-deprecated-declarations \
    -o "$SCRIPT_DIR/build/squirrel-setup" "$SCRIPT_DIR/src/squirrel_setup.c" \
    $(pkg-config --cflags --libs gtk+-3.0) -lpthread
fi

BINARY="$SCRIPT_DIR/build/squirrel-setup"
chmod +x "$BINARY"
file "$BINARY"

SUFFIX="$TARGET"
case "$TARGET" in
  x86_64-linux-gnu) SUFFIX="linux-x86_64" ;;
  aarch64-linux-gnu) SUFFIX="linux-aarch64" ;;
esac

say "打包发布目录"
STAGE="$SCRIPT_DIR/build/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp "$BINARY" "$STAGE/squirrel-setup"

cat > "$STAGE/run.sh" <<SH
#!/bin/sh
# 启动器：设置 GTK 后端与主题后运行安装程序
export GDK_BACKEND="\${GDK_BACKEND:-x11}"
export GTK_THEME="\${GTK_THEME:-Adwaita}"
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
exec "\$DIR/squirrel-setup" "\$@"
SH
chmod +x "$STAGE/run.sh"

cat > "$STAGE/使用说明.txt" <<TXT
Squirrel 鼠鬚管安装程序 (Linux, GTK 3)

依赖：系统需要已安装 GTK 3 运行库（libgtk-3.so.0），绝大多数桌面发行版默认自带。
  Debian/Ubuntu : sudo apt install libgtk-3-0
  Fedora        : sudo dnf install gtk3
  Arch/Omarchy  : sudo pacman -S gtk3
  openSUSE      : sudo zypper install gtk3

使用：
  1. 解压： tar -xzf SquirrelSetup-版本-linux-x86_64.tar.gz
  2. 运行： ./squirrel-setup     （或 ./run.sh）
  3. 点击「开始安装」，按提示完成 5 个步骤：
     检测环境 → 安装 Rime 引擎（pkexec 提权）→ 写入用户配置
     → 下载 plum 词库方案 → rime_deployer 编译并重启 fcitx5；
  4. 完成后用 fcitx5-configtool（或 ibus-setup）确认 Rime 已启用。

用户配置目录：~/.local/share/fcitx5/rime（fcitx5）或 ~/.config/ibus/rime（ibus）
共享配置来源：rime-config/default.custom.yaml
TXT

TARBALL="$OUT_DIR/SquirrelSetup-$VERSION-$SUFFIX.tar.gz"
tar -czf "$TARBALL" -C "$STAGE" .
echo "  $TARBALL"

say "生成校验和"
( cd "$OUT_DIR" && shasum -a 256 ./SquirrelSetup-*.tar.gz >> SHA256SUMS-linux.txt )

say "产物："
ls -lh "$OUT_DIR" | sed 's/^/    /'
