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
# 只登记唯一一条「Input Mode」条目：早先版本同时写入 bundle 级条目，会在
# TIS 里多出一个无图标的 im.rime.inputmethod.Squirrel 输入源，菜单栏因此
# 出现两个指示器（上面空白、下面才是真图标）。本脚本会把已有条目收敛成
# 唯一一条 Input Mode 记录，并清掉重复项。
#
# 用法：bash tools/sync-inputmenu.sh
#   每次注销重登后跑一次；也可以挂成登录项自动执行。
set -uo pipefail

PLIST_DOMAIN=com.apple.HIToolbox
BUNDLE_ID=im.rime.inputmethod.Squirrel
MODE=$BUNDLE_ID.Hans

CUR="$(defaults read $PLIST_DOMAIN AppleEnabledInputSources 2>/dev/null)"
TMP=$(mktemp -d)
defaults export $PLIST_DOMAIN "$TMP/ht.plist" >/dev/null 2>&1 || { echo "✗ 读取 $PLIST_DOMAIN 失败"; exit 1; }
python3 - "$TMP/ht.plist" "$TMP/ht-new.plist" "$BUNDLE_ID" "$MODE" <<'PYEOF'
import plistlib, sys
src, dst, bundle, mode = sys.argv[1:5]
with open(src, 'rb') as f:
    d = plistlib.load(f)
arr = d.setdefault('AppleEnabledInputSources', [])

# 幂等 + 自愈：把鼠鬚管的条目收敛成唯一一条「Input Mode」。
#
# 只登记 Input Mode、不要 bundle 级条目。bundle 级（InputSourceKind =
# Keyboard Input Method 且没有 Input Mode）会让 TIS 额外注册出一个
# im.rime.inputmethod.Squirrel 输入源，它没有图标（kTISPropertyIconImageURL
# 为 NULL），与真正带图标的那条在菜单栏相邻排布——两者加起来正好是
# 「两个图标高、上面那条空白、下面那条才是正确图标」。
#
# 去重同样重要：重复的条目会让 TIS 里出现多个同 ID 输入源，
# 菜单栏指示器也会跟着重复。
kept, seen_mode = [], False
for e in arr:
    if not isinstance(e, dict) or e.get('Bundle ID') != bundle:
        kept.append(e)
        continue
    if 'Input Mode' in e:                      # 模式级：唯一需要的条目
        if seen_mode:
            continue                           # 丢掉重复项
        seen_mode = True
        e = {'Bundle ID': bundle, 'Input Mode': mode, 'InputSourceKind': 'Input Mode'}
        kept.append(e)
    # 无 Input Mode 的 bundle 级条目直接丢弃
if not seen_mode:
    kept.append({'Bundle ID': bundle, 'Input Mode': mode, 'InputSourceKind': 'Input Mode'})
d['AppleEnabledInputSources'] = kept
with open(dst, 'wb') as f:
    plistlib.dump(d, f)
PYEOF
[ $? -eq 0 ] || { echo "✗ 改写 plist 失败"; rm -rf "$TMP"; exit 1; }

BEFORE="$CUR"
defaults import $PLIST_DOMAIN "$TMP/ht-new.plist" && rm -rf "$TMP"
killall TextInputMenuAgent 2>/dev/null
sleep 2

AFTER="$(defaults read $PLIST_DOMAIN AppleEnabledInputSources 2>/dev/null)"
if [ "$AFTER" = "$BEFORE" ]; then
  echo "✓ 输入法菜单已含且仅含一条鼠鬚管条目，无需处理"
else
  echo "✓ 已收敛鼠鬚管条目为唯一一条 Input Mode 记录并刷新输入菜单"
  echo "  （下次注销后会再丢，重跑本脚本即可）"
fi
echo "$AFTER" | grep -A3 "$BUNDLE_ID" | sed 's/^/  /'

echo
echo "现在可以：点菜单栏输入法菜单选「Squirrel - Simplified」，然后："
echo "  · 打 nihao 空格 →「你好」（拼音）"
echo "  · 打 wq / vb →「你」「好」（五笔）"
echo "  · 打 hello → 候选里选 hello（英文单词候选）"
echo "  · 轻点左 Shift → 中英切换（菜单栏图标变 A）"
echo
echo "若点选后打字无反应，运行 bash tools/ime-healthcheck.sh 看整条链路。"
