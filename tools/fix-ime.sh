#!/usr/bin/env bash
# fix-ime.sh — 一键修复"切到中文输入法却打不出中文"。
#
# 用法：bash tools/fix-ime.sh
#
# 两个独立根因，本脚本各修一处：
#   1) 当前输入源停在 com.apple.keylayout.ABC（纯英文键盘布局）——按 TIS 正路
#      启用并选中 im.rime.inputmethod.Squirrel.Hans。
#   2) 默认方案核对为 wubi_pinyin（五笔·拼音混输：直接敲五笔码或全拼都有候选，
#      拼音由方案内置 reverse_lookup_translator + pinyin_simp 词库响应）。
#   3) AppleEnabledInputSources plist 缺鼠须管条目——系统设置列表/菜单栏图标
#      只认 plist，缺记录则"打字正常但列表里没有鼠须管"。幂等补写。
#
# 幂等：重复执行只会重新断言同一状态，不会产生副作用。
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

RIME="$HOME/Library/Rime"
BUILT="$RIME/build/default.yaml"
RC=0
say() { printf '%s\n' "$*"; }

# ---- 第 1 步：核对引擎配置 --------------------------------------------------
say "════ 1/2 引擎配置 ════"
if [ -f "$BUILT" ]; then
  # 注意：变量后紧跟全角标点时必须写成 ${VAR}。bash 按字节判断变量名是否结束，
  # UTF-8 的高位字节会被算进变量名，`$FIRST（全拼）` 会被解析成一个不存在的
  # 超长变量名，在 set -u 下直接报错退出。
  FIRST="$(grep -A1 '^schema_list:' "$BUILT" | tail -1 | sed 's/.*schema: //')"
  if [ "$FIRST" = "wubi_pinyin" ]; then
    say "  ✓ 默认方案 = ${FIRST}（五笔·拼音混输）"
  else
    say "  ✗ 默认方案 = ${FIRST:-空}，期望 wubi_pinyin"
    say "    修法：把 ${RIME}/default.custom.yaml 的 schema_list 首位改为 wubi_pinyin，"
    say "    再重新部署（菜单栏图标 → 重新部署）。"
    RC=1
  fi
  if grep -q '^[[:space:]]*Shift_L:[[:space:]]*commit_code' "$BUILT"; then
    say "  ✓ 左 Shift = commit_code（中英切换）"
  else
    say "  ✗ 未找到 Shift_L: commit_code，左 Shift 不能切换中英文"
    RC=1
  fi
  # 出厂自带一批 app_options（Terminal/VSCode 等默认英文态，上游有意的默认值）。
  # 只有超出出厂清单的锁定才会导致"该应用里打不出中文"。
  SYS_APP="/Library/Input Methods/Squirrel.app"
  LOCK="$(grep -c 'ascii_mode: true' "$RIME/build/squirrel.yaml" 2>/dev/null || true)"
  LOCK="${LOCK:-0}"
  STOCK="$(grep -c 'ascii_mode: true' "$SYS_APP/Contents/SharedSupport/squirrel.yaml" 2>/dev/null || true)"
  STOCK="${STOCK:-0}"
  if [ "$LOCK" -le "$STOCK" ]; then
    say "  ✓ 强制英文应用 $LOCK 个（≤ 出厂默认 ${STOCK}，英文环境应用的合理预设）"
  else
    say "  ✗ 有 $((LOCK - STOCK)) 个应用被额外锁 ascii_mode: true（超出出厂默认），会打不出中文"
    RC=1
  fi
else
  say "  ! 尚未部署（${BUILT} 不存在），先执行一次「重新部署」再运行本脚本"
  RC=1
fi

# ---- 第 2 步：把当前输入源切回鼠鬚管 ---------------------------------------
say ""
say "════ 2/3 系统输入源 ════"
if [ -x ./tools/tis-enable ]; then
  ./tools/tis-enable
  TIS_RC=$?
  [ "$TIS_RC" -ne 0 ] && RC=1
else
  say "  ✗ 缺少 tools/tis-enable，无法自动切换"
  RC=1
fi

# ---- 第 3 步：把鼠须管补进输入法列表 plist ---------------------------------
# macOS 26 上 TIS 数据库认为源"已启用"时 TISEnableInputSource 是 no-op，不会
# 补写 com.apple.HIToolbox 的 AppleEnabledInputSources；而系统设置的输入法
# 列表、菜单栏图标恰恰只认这个 plist——缺记录就会出现"打字正常但列表里
# 找不到鼠须管、图标消失"。这里幂等补写（已存在则不动）。
say ""
say "════ 3/3 输入法列表（AppleEnabledInputSources）════"
PLIST_OUT="$(defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null)"
if echo "$PLIST_OUT" | grep -q 'im\.rime\.inputmethod\.Squirrel'; then
  say "  ✓ 输入法列表已含鼠须管"
else
  defaults export com.apple.HIToolbox /tmp/.ht-fix.plist 2>/dev/null \
  && python3 - <<'PYEOF' && defaults import com.apple.HIToolbox /tmp/.ht-fixed.plist \
    && killall TextInputMenuAgent 2>/dev/null
import plistlib
with open('/tmp/.ht-fix.plist','rb') as f:
    d = plistlib.load(f)
arr = d.get('AppleEnabledInputSources', [])
if not any('rime' in str(e.get('Bundle ID',''))+str(e.get('Input Mode','')) for e in arr):
    arr.append({'Bundle ID':'im.rime.inputmethod.Squirrel','InputSourceKind':'Keyboard Input Method'})
    arr.append({'Bundle ID':'im.rime.inputmethod.Squirrel','Input Mode':'im.rime.inputmethod.Squirrel.Hans','InputSourceKind':'Input Mode'})
    d['AppleEnabledInputSources'] = arr
with open('/tmp/.ht-fixed.plist','wb') as f:
    plistlib.dump(d, f)
PYEOF
  sleep 2
  if defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null | grep -q 'im\.rime\.inputmethod\.Squirrel'; then
    say "  ✓ 已补写鼠须管条目（列表/图标应立即恢复）"
  else
    say "  ✗ 补写失败，请在 系统设置→键盘→输入法→编辑… 里手动添加 Squirrel - Simplified"
    RC=1
  fi
fi

say ""
if [ "$RC" -eq 0 ]; then
  say "✓ 修复完成。"
else
  say "✗ 仍有未解决项，见上面标 ✗ 的行。"
fi
exit "$RC"
