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
  # grep -c 在零匹配时会"打印 0 并返回非 0"，所以 `|| echo 0` 会多补一行 0，
  # 变量变成 "0\n0"。这里用 || true 并对空值兜底。
  LOCK="$(grep -c 'ascii_mode: true' "$RIME/build/squirrel.yaml" 2>/dev/null || true)"
  LOCK="${LOCK:-0}"
  if [ "$LOCK" = "0" ]; then
    say "  ✓ 没有应用被强制锁成英文态"
  else
    say "  ✗ 有 ${LOCK} 个应用被锁 ascii_mode: true，会打不出中文"
    RC=1
  fi
else
  say "  ! 尚未部署（${BUILT} 不存在），先执行一次「重新部署」再运行本脚本"
  RC=1
fi

# ---- 第 2 步：把当前输入源切回鼠鬚管 ---------------------------------------
say ""
say "════ 2/2 系统输入源 ════"
if [ -x ./tools/tis-enable ]; then
  ./tools/tis-enable
  TIS_RC=$?
  [ "$TIS_RC" -ne 0 ] && RC=1
else
  say "  ✗ 缺少 tools/tis-enable，无法自动切换"
  RC=1
fi

say ""
if [ "$RC" -eq 0 ]; then
  say "✓ 修复完成。"
else
  say "✗ 仍有未解决项，见上面标 ✗ 的行。"
fi
exit "$RC"
