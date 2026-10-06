#!/usr/bin/env bash
# 中文输入法健康检查：一条命令看清整条链路的每一层。
# 覆盖 app 本体 → 系统输入源注册 → 输入菜单 → Rime 配置 → 引擎行为。
# 用法： bash tools/ime-healthcheck.sh

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; DIM=$'\033[2m'; RST=$'\033[0m'
PASS=0; FAIL=0; WARN=0

ck() { # ck <描述> <实际> <期望>
  if [ "$2" = "$3" ]; then
    printf "  ${GRN}✓${RST} %-46s %s\n" "$1" "$2"; PASS=$((PASS+1))
  else
    printf "  ${RED}✗${RST} %-46s 实际=%s 期望=%s\n" "$1" "$2" "$3"; FAIL=$((FAIL+1))
  fi
}
ckc() { # ckc <描述> <条件结果0/1> <备注>
  if [ "$2" = "1" ]; then
    printf "  ${GRN}✓${RST} %-46s %s\n" "$1" "$3"; PASS=$((PASS+1))
  else
    printf "  ${RED}✗${RST} %-46s %s\n" "$1" "$3"; FAIL=$((FAIL+1))
  fi
}
warn() { printf "  ${YEL}!${RST} %-46s %s\n" "$1" "$2"; WARN=$((WARN+1)); }

USER_APP="$HOME/Library/Input Methods/Squirrel.app"
SYS_APP="/Library/Input Methods/Squirrel.app"
RIME="$HOME/Library/Rime"
LOGDIR="$(ls -td /var/folders/*/*/T/rime.squirrel 2>/dev/null | head -1)"

echo
echo "════ 1. 应用本体 ════"
# app 可能装在用户目录或系统目录。系统级 /Library/Input Methods 是
# macOS 对第三方输入法认可的正式位置，登录时会被扫描注册；用户目录则
# 不稳定（曾出现被系统踢出输入法列表的情况）。优先系统目录。
APP=""
if [ -d "$SYS_APP" ]; then APP="$SYS_APP"; LOC="系统目录"; fi
if [ -z "$APP" ] && [ -d "$USER_APP" ]; then APP="$USER_APP"; LOC="用户目录"; fi

if [ -n "$APP" ]; then
  printf "  ${DIM}安装位置%s\n" "$APP"
  if [ "$LOC" = "系统目录" ]; then
    ck "安装在系统级目录" "是" "是"
  else
    warn "装在用户目录" "$USER_APP（建议迁到 /Library/Input Methods）"
  fi
  codesign --verify --deep --strict "$APP" >/dev/null 2>&1 \
    && ck "代码签名封印" "完好" "完好" \
    || ck "代码签名封印" "损坏" "完好"
  if ls "$APP/Contents/SharedSupport" 2>/dev/null | grep -qxE 'build|user.yaml|installation.yaml'; then
    ck "bundle 未被 deploy 污染" "有污染" "干净"
  else
    ck "bundle 未被 deploy 污染" "干净" "干净"
  fi
  printf "  ${DIM}文件数%s\n" "$(find "$APP" -type f 2>/dev/null | wc -l | tr -d ' ')"
else
  ck "应用已安装" "缺失" "已安装"
fi

# 两处同时存在 = 同 bundle id 重复注册，输入菜单会出现两项
if [ -d "$USER_APP" ] && [ -d "$SYS_APP" ]; then
  ck "无重复副本" "两处都有" "只留一处"
else
  ck "无重复副本" "单一副本" "单一副本"
fi

echo
echo "════ 2. 系统输入源 ════"
if [ -x /tmp/tis-list ]; then
  CURLINE="$(/tmp/tis-list 2>/dev/null | tail -1)"
  CUR="$(echo "$CURLINE" | grep -oE 'im\.[A-Za-z0-9._-]+' | head -1)"
  printf "  ${DIM}当前源%s\n" "$CURLINE"
  case "$CUR" in
    im.rime.inputmethod.Squirrel*) HIT=1 ;;
    *) HIT=0 ;;
  esac
  ckc "当前源是鼠鬚管" "$HIT" "$CUR"
  N="$(/tmp/tis-list 2>/dev/null | sed -n '/== enabled input methods ==/,/== current/p' | grep -ci squirrel)"
  if [ "$N" -le 2 ]; then
    ckc "TIS 中 Squirrel 条目数正常" 1 "$N 条（标准 2）"
  else
    # 历史遗留的重复注册行数量稳定、不随重启增长（实验验证过），只影响
    # 输入菜单显示杂项，不影响输入；macOS 对第三方源也无公开的反注册 API。
    warn "TIS 中 Squirrel 条目偏多" "$N 条（标准 2，历史重复行，无害）"
  fi
  ENB="$(/tmp/tis-list 2>/dev/null | sed -n '/== enabled input methods ==/,/== current/p' | grep -c 'im\.rime')"
  ckc "TIS 启用列表含鼠鬚管（重启后仍可用）" "$([ "$ENB" -ge 1 ] && echo 1 || echo 0)" "$ENB 条"
else
  warn "缺少 /tmp/tis-list" "无法检查输入源"
fi

# macOS 26：系统设置的输入法列表、菜单栏图标只认 com.apple.HIToolbox 的
# AppleEnabledInputSources。TIS 数据库的 enabled 状态与它脱钩——DB 已启用时
# TISEnableInputSource 不补写 plist，缺记录则"打字正常但列表/图标里没有
# 鼠须管"（tools/fix-ime.sh 第 3 步可幂等补写）。
MENU="$(defaults read com.apple.HIToolbox AppleEnabledInputSources 2>/dev/null)"
ckc "输入法列表含鼠须管（plist）" \
  "$(echo "$MENU" | grep -q 'im\.rime\.inputmethod\.Squirrel' && echo 1 || echo 0)" \
  "设置/图标/菜单的显示依据"
if echo "$MENU" | grep -q 'CharacterPaletteIM'; then
  warn "菜单 plist 里有 CharacterPaletteIM" "系统自带表情面板的正常条目，非故障"
fi
LOG5="$(log show --predicate 'process == "TextInputMenuAgent"' --last 5m --style compact 2>/dev/null)"
# 致命条件只有两个：菜单里出现「no input source available」（当前无可用源），
# 或 Squirrel 自身的源 id 被判为 unknown（我们的源装坏了）。
FATAL="$(echo "$LOG5" | grep -cE 'no input source available|unknown input source id:im\.rime')"
ckc "输入菜单代理无致命错误" "$([ "$FATAL" -eq 0 ] && echo 1 || echo 0)" "$FATAL 次"
# com.apple.CharacterPaletteIM 是 macOS 自带表情/字符面板的系统源 id。系统自身
# 对它的重解析会产生 Fault 级 'unknown input source id:com.apple.CharacterPaletteIM'，
# 属于内部噪音，与 Squirrel 无关，不影响输入；单独降级为警告而非失败。
if echo "$LOG5" | grep -q 'unknown input source id:com\.apple\.CharacterPaletteIM'; then
  warn "菜单代理有 CharacterPaletteIM 系统噪音" "macOS 内置表情面板重解析，与鼠鬚管无关"
fi

echo
echo "════ 3. 进程与引擎 ════"
if pgrep -x Squirrel >/dev/null; then
  UPT="$(ps -o etime= -p "$(pgrep -x Squirrel | head -1)" | tr -d ' ')"
  printf "  ${DIM}已运行%s  路径=%s\n" "$UPT" "$(ps -o command= -p "$(pgrep -x Squirrel|head -1)" | cut -c1-60)"
  ck "Squirrel 进程存活" "是" "是"
else
  ck "Squirrel 进程存活" "否" "是"
fi
if [ -n "$LOGDIR" ]; then
  LOG="$(ls -t "$LOGDIR"/*.log.INFO.* 2>/dev/null | head -1)"
  E="$(grep -cE '^[EF][0-9]' "$LOG" 2>/dev/null | head -1)"
  [ -n "$E" ] || E=0
  ck "引擎 ERROR/FATAL 行数" "$E" "0"
fi

echo
echo "════ 4. Rime 配置 ════"
[ -f "$RIME/build/default.yaml" ] || echo "  ${YEL}! 尚未部署，配置检查跳过${RST}"
[ -f "$RIME/build/default.yaml" ] && {
  FIRST="$(grep -A1 '^schema_list:' "$RIME/build/default.yaml" | tail -1 | sed 's/.*schema: //')"
  ckc "默认方案是五笔·拼音混输" "$([ "$FIRST" = "wubi_pinyin" ] && echo 1 || echo 0)" "$FIRST"
  SH="$(grep 'Shift_L:' "$RIME/build/default.yaml" | tr -d ' ')"
  ck "左 Shift 绑定" "$SH" "Shift_L:commit_code"
}
[ -f "$RIME/build/squirrel.yaml" ] && {
  LOCK="$(grep -c 'ascii_mode: true' "$RIME/build/squirrel.yaml")"
  ck "强制英文的应用数" "$LOCK" "0"
  FM="$(grep -c 'force_marked_text_for_direct_commit: true' "$RIME/build/squirrel.yaml")"
  printf "  ${DIM}Electron 强制标记文本应用数: %s${RST}\n" "$FM"
}
printf "  ${DIM}previously_selected_schema: %s${RST}\n" "$(grep previously_selected_schema "$RIME/user.yaml" 2>/dev/null | tr -d ' ')"

echo
echo "════ 5. 引擎端到端测试 ════"
TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rime-shifttest"
if [ -x "$TEST" ] && [ -n "$APP" ]; then
  cp "$RIME/user.yaml" /tmp/.user.yaml.hc 2>/dev/null || true
  # 不能 cd 进 SharedSupport 跑：librime 会把部署产物写进进程工作目录，
  # 曾把 build/、installation.yaml、user.yaml 写进 app 包内（"deploy 污染"）。
  # 测试程序通过参数自行定位 shared_data_dir，在 /tmp 下运行即可。
  OUTT="$(cd /tmp && "$TEST" "$APP/Contents" 2>/dev/null)"
  [ -f /tmp/.user.yaml.hc ] && cp /tmp/.user.yaml.hc "$RIME/user.yaml"
  echo "$OUTT" | grep -E "PASS|FAIL" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/  /'
  if echo "$OUTT" | grep -q "全部通过"; then ck "端到端测试" "全部通过" "全部通过"
  else ck "端到端测试" "有失败" "全部通过"; fi
else
  warn "缺少 $TEST" "该文件不在，或先执行 bash tools/build-user.sh 重建"
fi

echo
echo "════ 汇总 ════"
printf "  通过 %s%d%s   失败 %s%d%s   警告 %s%d%s\n" \
  "$GRN" "$PASS" "$RST" "$([ "$FAIL" -gt 0 ] && echo "$RED" || echo "$GRN")" "$FAIL" "$RST" \
  "$([ "$WARN" -gt 0 ] && echo "$YEL" || echo "$GRN")" "$WARN" "$RST"
echo
echo "  ${DIM}说明：以上全部为自动化检查。屏幕上的实际输入结果仍需你手动确认——${RST}"
echo "  ${DIM}在编辑器里打 nihao 按空格，再轻点左 Shift 试试。${RST}"
echo
