#!/usr/bin/env bash
# sync-inputmenu.sh — 把鼠鬚管重新写进输入法菜单（AppleEnabledInputSources）。
#
# 背景（详见 tools/IME-REGISTRATION.md）：
#   本机没有 Apple Developer ID 证书，Squirrel.app 只能 ad-hoc 签名。
#   macOS 26 的输入法扫描器拒绝收录 ad-hoc 签名的输入法，所以系统从不
#   "真正"注册它——系统设置列表、菜单栏都看不到。直接写
#   com.apple.HIToolbox/AppleEnabledInputSources 可以让鼠鬚管出现在
#   输入菜单里并正常打字（924fd63 验证过），但每次注销/重启后系统会按
#   内部注册表重建该 plist，手写的条目随即丢失。本脚本幂等地补写回来。
#
# 用法：bash tools/sync-inputmenu.sh
#   每次注销重登后跑一次；也可以挂成登录项自动执行。
set -uo pipefail

PLIST_DOMAIN=com.apple.HIToolbox
BUNDLE_ID=im.rime.inputmethod.Squirrel
MODE=$BUNDLE_ID.Hans

CUR="$(defaults read $PLIST_DOMAIN AppleEnabledInputSources 2>/dev/null)"
if echo "$CUR" | grep -q "$BUNDLE_ID"; then
  echo "✓ 输入法菜单已含鼠鬚管，无需处理"
else
  TMP=$(mktemp -d)
  defaults export $PLIST_DOMAIN "$TMP/ht.plist" || { echo "✗ 读取 $PLIST_DOMAIN 失败"; exit 1; }
  python3 - "$TMP/ht.plist" "$TMP/ht-new.plist" "$BUNDLE_ID" "$MODE" <<'PYEOF'
import plistlib, sys
src, dst, bundle, mode = sys.argv[1:5]
with open(src, 'rb') as f:
    d = plistlib.load(f)
arr = d.setdefault('AppleEnabledInputSources', [])
if not any(bundle in str(e) for e in arr):
    arr.append({'Bundle ID': bundle, 'InputSourceKind': 'Keyboard Input Method'})
    arr.append({'Bundle ID': bundle, 'Input Mode': mode, 'InputSourceKind': 'Input Mode'})
    d['AppleEnabledInputSources'] = arr
with open(dst, 'wb') as f:
    plistlib.dump(d, f)
PYEOF
  [ $? -eq 0 ] || { echo "✗ 改写 plist 失败"; rm -rf "$TMP"; exit 1; }
  defaults import $PLIST_DOMAIN "$TMP/ht-new.plist" && rm -rf "$TMP"
  killall TextInputMenuAgent 2>/dev/null
  sleep 2
  if defaults read $PLIST_DOMAIN AppleEnabledInputSources 2>/dev/null | grep -q "$BUNDLE_ID"; then
    echo "✓ 已补写鼠鬚管条目并刷新输入菜单（下次注销后会再丢，重跑本脚本即可）"
  else
    echo "✗ 补写失败"
    exit 1
  fi
fi

echo
echo "现在可以：点菜单栏输入法菜单选「Squirrel - Simplified」，然后："
echo "  · 打 nihao 空格 →「你好」（拼音）"
echo "  · 打 wq / vb →「你」「好」（五笔）"
echo "  · 打 hello → 候选里选 hello（英文单词候选）"
echo "  · 轻点左 Shift → 中英切换（菜单栏图标变 A）"
echo
echo "若点选后打字无反应，运行 bash tools/ime-healthcheck.sh 看整条链路。"
