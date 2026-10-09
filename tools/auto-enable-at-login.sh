#!/usr/bin/env bash
# auto-enable-at-login.sh — 登录后自动注册并把鼠须管选为当前输入源（一次性）。
#
# 背景见 tools/IME-REGISTRATION.md：macOS 26 上新装的输入法要等开机扫描
# 才进注册表（注销不够，#1132），装好后还常常需要手动到系统设置里添加。
# 本脚本由 LaunchAgent（cn.kxpms.squirrel-autoselect）在每次登录时触发：
#   1) 等输入子系统就绪；
#   2) TISRegisterInputSource 强制重扫 /Library/Input Methods/Squirrel.app；
#   3) 尝试把 im.rime.inputmethod.Squirrel.Hans 选为当前源；
#   4) 选不中则退回 sync-inputmenu.sh（把菜单条目补写回 plist）。
# 日志：~/.squirrel-autoselect.log
# 目标达成（能正常打字）后可卸载：launchctl unload ~/Library/LaunchAgents/
#   cn.kxpms.squirrel-autoselect.plist && rm 该 plist。
set -u

LOG="$HOME/.squirrel-autoselect.log"
TOOLS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="/Library/Input Methods/Squirrel.app"
MODE="im.rime.inputmethod.Squirrel.Hans"

{
  echo "=== $(date '+%F %T') 登录触发 ==="
  # 输入子系统（TextInputMenuAgent 等）在登录后需要若干秒才就绪
  sleep 20

  if [ ! -d "$APP" ]; then
    echo "✗ $APP 不存在"
    exit 1
  fi

  "$TOOLS/tis-register" "$APP"
  sleep 3

  if "$TOOLS/tis-select" "$MODE"; then
    echo "✓ 已自动选中鼠须管（$MODE）"
  else
    echo "! 自动选中失败；回退：把菜单条目补写回 plist（见 IME-REGISTRATION.md）"
    bash "$TOOLS/sync-inputmenu.sh" || true
  fi
} >> "$LOG" 2>&1
