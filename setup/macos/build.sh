#!/usr/bin/env bash
#  build.sh — assemble SquirrelSetup.app, a .dmg and a .zip for macOS.
#
#  Produces a universal (arm64 + x86_64) AppKit setup program that carries the
#  repository's Squirrel.app as its payload plus the shared Rime user config.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SETUP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$SETUP_DIR/.." && pwd)"
OUT_DIR="${OUT_DIR:-$SETUP_DIR/dist}"
APP_NAME="SquirrelSetup"
APP_BUNDLE="$OUT_DIR/$APP_NAME.app"
VERSION="${VERSION:-1.0.0}"

# Squirrel.app payload: prefer a locally built app, fall back to a build.
PAYLOAD_APP="${PAYLOAD_APP:-$REPO_DIR/build-manual/Squirrel.app}"

say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

mkdir -p "$OUT_DIR"
# dist/ is shared with the Windows and Linux builds: only remove our own outputs
rm -f "$OUT_DIR/SquirrelSetup-$VERSION-macos-universal.dmg" \
      "$OUT_DIR/SquirrelSetup-$VERSION-macos-universal.zip" \
      "$OUT_DIR/SquirrelSetup-$VERSION-macos-universal.dmg.blockmap"
rm -rf "$APP_BUNDLE"

SWIFT="${SWIFT:-swift}"
command -v "$SWIFT" >/dev/null 2>&1 || SWIFT="/Library/Developer/CommandLineTools/usr/bin/swift"

say "编译 Swift/AppKit 前端 (universal, arm64 + x86_64)"
cd "$SCRIPT_DIR"
"$SWIFT" build -c release --arch arm64 --arch x86_64
BIN_PATH="$("$SWIFT" build -c release --arch arm64 --arch x86_64 --show-bin-path)/$APP_NAME"
lipo -info "$BIN_PATH"

say "组装 $APP_NAME.app"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cp "$REPO_DIR/rime-config/default.custom.yaml" "$APP_BUNDLE/Contents/Resources/default.custom.yaml"
cp "$REPO_DIR/rime-config/wubi_pinyin.schema.yaml" "$APP_BUNDLE/Contents/Resources/wubi_pinyin.schema.yaml"
cp "$SETUP_DIR/shared/presets.json" "$APP_BUNDLE/Contents/Resources/presets.json"

if [ -d "$PAYLOAD_APP" ]; then
  say "内置 Squirrel.app 负载：$PAYLOAD_APP"
  rm -rf "$APP_BUNDLE/Contents/Resources/Squirrel.app"
  cp -R "$PAYLOAD_APP" "$APP_BUNDLE/Contents/Resources/Squirrel.app"
  # The bundled engine must not carry the quarantine flag from this build machine.
  xattr -cr "$APP_BUNDLE/Contents/Resources/Squirrel.app" 2>/dev/null || true
  SQUIRREL_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "$APP_BUNDLE/Contents/Resources/Squirrel.app/Contents/Info.plist" 2>/dev/null || echo unknown)"
else
  echo "错误：找不到 Squirrel.app 负载（可用 PAYLOAD_APP= 指定）" >&2
  exit 1
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>Squirrel 鼠鬚管安装程序</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>com.rime.squirrel.setup</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSSupportsAutomaticGraphicsSwitching</key><true/>
  <key>CFBundleLocalizations</key><array><string>zh_CN</string><string>en</string></array>
</dict>
</plist>
PLIST

printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

say "生成图标"
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
if [ -x "$SCRIPT_DIR/make-icon.swift" ]; then
  if "$SWIFT" "$SCRIPT_DIR/make-icon.swift" "$ICONSET" 2>/dev/null; then
    iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
  fi
fi
rm -rf "$(dirname "$ICONSET")"

say "签名（ad-hoc）"
xattr -cr "$APP_BUNDLE" 2>/dev/null || true
codesign --force --deep --sign - "$APP_BUNDLE" 2>&1 | sed 's/^/    /'
codesign --verify --deep --strict "$APP_BUNDLE" && echo "    签名校验通过"

say "打包 DMG"
DMG_STAGE="$(mktemp -d)/dmg"
mkdir -p "$DMG_STAGE"
cp -R "$APP_BUNDLE" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
cat > "$DMG_STAGE/使用说明.txt" <<TXT
Squirrel 鼠鬚管安装程序 (macOS)

1. 把 $APP_NAME 拖到「应用程序」文件夹；
2. 双击运行，按提示完成 5 个步骤（安装引擎 / 写入配置 / 下载词库 / 编译启用）；
3. 安装完成后请到「系统设置 › 键盘 › 输入法」确认已勾选 Squirrel。

内置负载：Squirrel $SQUIRREL_VERSION (universal)
共享配置：rime-config/default.custom.yaml
TXT
hdiutil create -volname "Squirrel 安装程序" -srcfolder "$DMG_STAGE" -ov -format UDZO \
  "$OUT_DIR/SquirrelSetup-$VERSION-macos-universal.dmg" >/dev/null
rm -rf "$(dirname "$DMG_STAGE")"

say "打包 ZIP"
ditto -c -k --keepParent "$APP_BUNDLE" "$OUT_DIR/SquirrelSetup-$VERSION-macos-universal.zip"

say "生成校验和"
( cd "$OUT_DIR" && shasum -a 256 ./*.dmg ./*.zip > SHA256SUMS.txt )

say "产物："
ls -lh "$OUT_DIR" | sed 's/^/    /'
