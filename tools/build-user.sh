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
#   - SDK 优先取 CommandLineTools 自带的（本机可无完整 Xcode），Xcode 在则用 Xcode 的
#   - bundle 骨架完全自举：Info.plist 由 resources/Info.plist 替换构建占位符生成，
#     SharedSupport / Frameworks / 工具二进制从 make 产物（action-install.sh + plum-data）
#     组装，不再依赖上次构建的残留目录；本地化 .strings 取自已安装 app（.xcstrings
#     需要 xcstringstool 编译，CLT 没有）。
#
# 用法： bash tools/build-user.sh [安装目录]
#        不传参数默认安装到 /Library/Input Methods/Squirrel.app；
#        传空字符串（""）则只构建、不安装。
#        系统目录里 .app 的父目录归 root 所有、删不掉，安装采用"原位换 Contents"：
#        /Library/Input Methods/Squirrel.app 目录本身保留，Contents 整体替换。
#        用户目录（如 ~/Library/Input Methods）则整包替换。

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/sources"
APP="$ROOT/build-manual/Squirrel.app"
OUT="${1:-/Library/Input Methods/Squirrel.app}"

CLANG=/Library/Developer/CommandLineTools/usr/bin/clang
SWIFTC=/Library/Developer/CommandLineTools/usr/bin/swiftc

# 1) 定位 SDK：CommandLineTools 自带 SDK 兜底，Xcode 安装时用 Xcode 的
SDK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk 2>/dev/null || true)"
[ -n "$SDK" ] || SDK="$(ls -d /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/*.sdk 2>/dev/null | tail -1)"
[ -n "$SDK" ] || { echo "找不到 macOS SDK"; exit 1; }
echo "SDK: $SDK"

for t in "$CLANG" "$SWIFTC"; do
  [ -x "$t" ] || { echo "缺少编译器: $t"; exit 1; }
done

# 2) 依赖产物检查（由 action-install.sh / make plum-data 生成）
for dep in "$ROOT/lib/librime.1.dylib" "$ROOT/Frameworks/Sparkle.framework" \
           "$ROOT/data/plum/default.yaml" "$ROOT/data/squirrel.yaml" \
           "$ROOT/bin/rime-install"; do
  [ -e "$dep" ] || { echo "缺少构建依赖: ${dep}（先跑 bash action-install.sh && make plum-data）"; exit 1; }
done

# 3) 组装 bundle 骨架
echo "组装 bundle 骨架…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" \
         "$APP/Contents/SharedSupport"

# 版本号：pbxproj 的 CURRENT_PROJECT_VERSION，替换 Info.plist 占位符。
# SQUIRREL_VERSION 环境变量可覆盖——换版本号是打散 TIS 输入源缓存的有效手段
# （bundle id 不变时，TIS 会按"id+版本"缓存输入源元数据，原位换内容不换版本
# 会导致 TISSelectInputSource 以 paramErr(-50) 拒绝选中，见 tools/tis-register.c）。
VERSION="${SQUIRREL_VERSION:-$(grep -m1 'CURRENT_PROJECT_VERSION' "$ROOT/Squirrel.xcodeproj/project.pbxproj" \
  | sed -E 's/.*= *([0-9][^;]*);.*/\1/' | tr -d ' ')}"
[ -n "$VERSION" ] || VERSION="0.0.0"
sed -e "s/\$(PRODUCT_BUNDLE_IDENTIFIER)/im.rime.inputmethod.Squirrel/g" \
    -e "s/\$(CURRENT_PROJECT_VERSION)/${VERSION}/g" \
    "$ROOT/resources/Info.plist" > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist" >/dev/null || { echo "Info.plist 无效"; exit 1; }

# Resources：Info.plist 引用的图标 + 说明文件。本地化 .strings 从已安装的 app
# 里取（那是 xcodebuild 产品，.strings 已编译）；没有就不带，界面退化为英文键名。
for f in RimeIcon.icns rime-menu-v4.png rime.pdf; do
  [ -f "$ROOT/resources/$f" ] && cp "$ROOT/resources/$f" "$APP/Contents/Resources/"
done
cp "$ROOT/LICENSE.txt" "$ROOT/README.md" "$APP/Contents/Resources/" 2>/dev/null || true
# xcodebuild 会生成 PkgInfo；缺它不影响运行，但保持与正规构建产物一致
printf 'APPL????' > "$APP/Contents/PkgInfo"
SYS_APP="/Library/Input Methods/Squirrel.app"
if [ -d "$SYS_APP/Contents/Resources" ]; then
  cp -R "$SYS_APP/Contents/Resources/en.lproj" "$SYS_APP/Contents/Resources/zh-Hans.lproj" \
        "$SYS_APP/Contents/Resources/zh-Hant.lproj" "$APP/Contents/Resources/" 2>/dev/null || true
  cp "$SYS_APP/Contents/Resources/Assets.car" "$APP/Contents/Resources/" 2>/dev/null || true
fi

# Frameworks：Sparkle + librime + 插件
cp -R "$ROOT/Frameworks/Sparkle.framework" "$APP/Contents/Frameworks/"
cp "$ROOT/lib/librime.1.dylib" "$APP/Contents/Frameworks/"
if [ -d "$ROOT/lib/rime-plugins" ] && ls "$ROOT/lib/rime-plugins"/*.dylib >/dev/null 2>&1; then
  mkdir -p "$APP/Contents/Frameworks/rime-plugins"
  cp "$ROOT/lib/rime-plugins"/*.dylib "$APP/Contents/Frameworks/rime-plugins/"
fi

# SharedSupport：plum 方案/词库 + squirrel.yaml + OpenCC 数据
cp "$ROOT/data/plum/"* "$APP/Contents/SharedSupport/"
cp "$ROOT/data/squirrel.yaml" "$APP/Contents/SharedSupport/"
mkdir -p "$APP/Contents/SharedSupport/opencc"
cp "$ROOT/data/opencc/"* "$APP/Contents/SharedSupport/opencc/"

# MacOS 目录：维护命令工具（rime-install 供 postinstall / 安装程序使用）
cp "$ROOT/bin/rime-install" "$APP/Contents/MacOS/"
for t in rime_deployer rime_dict_manager; do
  [ -f "$ROOT/bin/$t" ] && cp "$ROOT/bin/$t" "$APP/Contents/MacOS/"
done

# 4) 编译主程序
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

# 刚编出来的可执行文件放进骨架，不能沿用旧二进制
cp "$BIN/Contents/MacOS/Squirrel" "$APP/Contents/MacOS/Squirrel"
chmod +x "$APP/Contents/MacOS/Squirrel"
for t in rime-install rime_deployer rime_dict_manager; do
  [ -f "$APP/Contents/MacOS/$t" ] && chmod +x "$APP/Contents/MacOS/$t"
done

# 5) 补齐版本号两个键（Sparkle / 安装程序的版本识别用）
for KEY in CFBundleShortVersionString CFBundleVersion; do
  /usr/libexec/PlistBuddy -c "Add :$KEY string $VERSION" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Set :$KEY $VERSION" "$APP/Contents/Info.plist"
done
echo "版本号: $VERSION"

# 6) 签名并校验封印
# CODESIGN_IDENTITY 默认 ad-hoc（"-"）。⚠️ macOS 26 的输入法扫描器拒收
# ad-hoc 签名的输入法（AMFI -423）：装进 /Library/Input Methods 后系统设置
# 不显示、TISSelectInputSource -50、注销后手写的 plist 条目也会被重建掉。
# 有 Developer ID / Apple Development 证书时务必传入，详见
# tools/IME-REGISTRATION.md。
SIGN_ID="${CODESIGN_IDENTITY:--}"
echo "签名（${SIGN_ID}）…"
codesign --force --deep --sign "$SIGN_ID" "$APP" >/dev/null 2>&1
codesign --verify --deep --strict "$APP" >/dev/null 2>&1 \
  || { echo "签名校验失败"; exit 1; }
echo "签名封印: 完好"
if [ "$SIGN_ID" = "-" ]; then
  cat >&2 <<'WARN'
⚠️  当前为 ad-hoc 签名：macOS 26 不会正式注册该输入法（系统设置列表不显示、
    无法程序化选中）。每次注销重登后需要 bash tools/sync-inputmenu.sh 补回菜单。
    正解：CODESIGN_IDENTITY="Developer ID Application: …" 重新构建，
    见 tools/IME-REGISTRATION.md。
WARN
fi

if [ -z "$OUT" ]; then
  echo "构建完成（未安装）: $APP"
  exit 0
fi

# 7) 安装
#    系统目录（/Library/Input Methods）父目录归 root，.app 删不掉但内容可换
#    （上次 make install 后 .app 属主是当前用户）；用户目录整包替换。
if [ -d "$OUT" ]; then
  if [ -w "$(dirname "$OUT")" ]; then
    rm -rf "$OUT"
    mkdir -p "$(dirname "$OUT")"
    cp -R "$APP" "$OUT"
  else
    echo "原位更新 $OUT 的 Contents（父目录不可写，保留 .app 外壳）"
    rm -rf "$OUT/Contents"
    cp -R "$APP/Contents" "$OUT/Contents"
  fi
else
  mkdir -p "$(dirname "$OUT")"
  cp -R "$APP" "$OUT"
fi
echo "已安装: $OUT"
echo
echo "接下来运行 tools/ime-healthcheck.sh 确认状态，"
echo "并用 tools/rime-shifttest 跑引擎端到端测试。"
