#!/usr/bin/env bash
# 菜单栏输入法图标渲染修复的 Plan B 切换器：
# 重登后若 menu-icon.png 仍不渲染，切到经典 16pt TIFF 格式再重登验证。
# 用法： bash tools/switch-menu-icon.sh [menu-icon.png|rime-icon.tiff]
set -euo pipefail
cd "$(dirname "$0")/.."
APP="/Library/Input Methods/Squirrel.app"
TARGET="${1:-rime-icon.tiff}"
[ -f "$APP/Contents/Resources/$TARGET" ] || { echo "缺资源 $TARGET"; exit 1; }
for mode in im.rime.inputmethod.Squirrel.Hans im.rime.inputmethod.Squirrel.Hant; do
  for key in tsInputModeMenuIconFileKey tsInputModeAlternateMenuIconFileKey tsInputModePaletteIconFileKey; do
    /usr/libexec/PlistBuddy -c "Set :ComponentInputModeDict:tsInputModeListKey:$mode:$key $TARGET" \
      "$APP/Contents/Info.plist"
  done
done
codesign --force --deep --sign - "$APP" >/dev/null 2>&1
echo "图标已切换为 $TARGET，请注销重登后观察菜单栏"
