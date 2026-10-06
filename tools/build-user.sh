#!/usr/bin/env bash
# 在不依赖 xcodebuild、不需要接受 Xcode 许可的前提下，从源码构建 Squirrel。
#
# 为什么不用 make / xcodebuild：
#   /usr/bin/xcodebuild 与 /usr/bin/swiftc 都是 xcrun shim，会被 "You have not agreed
#   to the Xcode license agreements" 拦住，而接受许可需要 sudo + 交互，本脚本无法完成。
#   /usr/bin/clang 在本机实际是 Linux 交叉编译器（产出 ELF），同样不可用。
#   但 CommandLineTools 里真正的编译器二进制只要显式指定 -sdk / -isysroot 就能用。
#
# 额外处理：
#   - librime 源码未 checkout，rime/key_table.h 缺失 → 用 tools/rime-shim 提供
#   - 源码用了 Swift 5.7 的裸斜杠正则 → 加 -enable-bare-slash-regex
#
# 用法： bash tools/build-user.sh [安装目录]
#        不传安装目录则只构建，不安装。默认安装到 ~/Library/Input Methods。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/sources"
APP="$ROOT/build-manual/Squirrel.app"
OUT="${1:-}"

CLANG=/Library/Developer/CommandLineTools/usr/bin/clang
SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc

# 1) 定位 SDK
SDK="$(ls -d /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/*.sdk 2>/dev/null | tail -1)"
[ -n "$SDK" ] || { echo "找不到 macOS SDK"; exit 1; }
echo "SDK: $SDK"

for t in "$CLANG" "$SWIFTC"; do
  [ -x "$t" ] || { echo "缺少编译器: $t"; exit 1; }
done

# 2) 编译主程序
BIN="$(mktemp -t squirrel-build).app"
# mktemp -t 只创建同名普通文件，追加的 .app 及其内部目录并不存在。
# 少了这一步，swiftc 链接阶段会以
#   ld: open() failed, errno=2 ... for '.../Squirrel.app/Contents/MacOS/Squirrel'
# 失败——错误信息指向可执行文件缺失，掩盖了真实原因是目录没建。
mkdir -p "$BIN/Contents/MacOS"
echo "编译 Squirrel 主程序…"
"$SWIFTC" \
  -sdk "$SDK" -target arm64-apple-macos14 \
  -enable-bare-slash-regex \
  -import-objc-header "$SRC/Squirrel-Bridging-Header.h" \
  -I "$ROOT/tools/rime-shim" \
  -I "$ROOT/download/dist/include" \
  -I "$ROOT/download/include" \
  -F "$APP/Contents/Frameworks" \
  -L "$APP/Contents/Frameworks" -lrime.1 -framework Sparkle \
  -Xlinker -rpath -Xlinker "@loader_path/../Frameworks" \
  -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
  -o "$BIN/Contents/MacOS/Squirrel" \
  "$SRC"/*.swift

# 3) 组装 bundle（复用 build-manual 里已就位的 Frameworks / Resources / SharedSupport）
#    注意：STAGE 目标路径不能预先 mkdir。若先建目录，cp -R "$APP" "$STAGE" 会把
#    app 套进 $STAGE/Squirrel.app/，后续对 $STAGE/Contents/... 的操作全部落空。
STAGE="$(mktemp -d)/Squirrel.app"
cp -R "$APP" "$STAGE"
# 刚编出来的可执行文件在 $BIN，骨架目录里没有，必须显式放进去，
# 否则会沿用上一次的旧二进制（症状：改了源码却毫无变化）。
cp "$BIN/Contents/MacOS/Squirrel" "$STAGE/Contents/MacOS/Squirrel"
chmod +x "$STAGE/Contents/MacOS/Squirrel"

# 3b) 图标资源：Info.plist 声明的 RimeIcon.icns（app 图标）与 menu-icon.png
#     （输入法菜单栏图标；TIS 对 rime.pdf 矢量渲染会丢"中"字显示成空框）。
#     骨架缺失时从仓库 resources/ 补齐，避免重装后菜单栏变回空框。
for icon in RimeIcon.icns menu-icon.png; do
  if [ ! -f "$STAGE/Contents/Resources/$icon" ] && [ -f "$ROOT/resources/$icon" ]; then
    cp "$ROOT/resources/$icon" "$STAGE/Contents/Resources/$icon"
    echo "已补图标: $icon"
  fi
done

# 3.5) 补版本号：骨架的 Info.plist 没有 CFBundleShortVersionString，
#      安装程序（setup/）的引擎一致比对取不到版本时会退化为"永远不一致"，
#      导致每次重跑都重装引擎、弹一次管理员授权框。
VERSION="${SQUIRREL_VERSION:-$(grep -m1 'CURRENT_PROJECT_VERSION' "$ROOT/Squirrel.xcodeproj/project.pbxproj" \
  | sed -E 's/.*= *([0-9][^;]*);.*/\1/' | tr -d ' ')}"
[ -n "$VERSION" ] || VERSION="0.0.0"
for KEY in CFBundleShortVersionString CFBundleVersion; do
  /usr/libexec/PlistBuddy -c "Add :$KEY string $VERSION" "$STAGE/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :$KEY $VERSION" "$STAGE/Contents/Info.plist"
done
echo "版本号: $VERSION"

# 4) 签名并校验封印
echo "签名…"
codesign --force --deep --sign - "$STAGE" >/dev/null 2>&1
codesign --verify --deep --strict "$STAGE" >/dev/null 2>&1 \
  || { echo "签名校验失败"; exit 1; }
echo "签名封印: 完好"

if [ -z "$OUT" ]; then
  echo "构建完成（未安装）: $STAGE"
  exit 0
fi

# 5) 安装
mkdir -p "$(dirname "$OUT")"
rm -rf "$OUT"
cp -R "$STAGE" "$OUT"
echo "已安装: $OUT"
echo
echo "接下来运行 tools/ime-healthcheck.sh 确认状态，"
echo "并用 tools/rime-shifttest 跑引擎端到端测试。"
