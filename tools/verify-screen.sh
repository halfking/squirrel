#!/bin/bash
# verify-screen.sh — 真机屏幕层验证（IMK 客户端层）
#
# 前置条件：系统设置 → 隐私与安全性 → 辅助功能 中打开「MiniMax Code」
#
# 原理：用具备辅助功能权限的 System Events 向真实 TextEdit 投递合成按键，
#       再用 TextEdit 自身的脚本接口读回文档文本——不依赖截图或像素识别。
#
# 已知的两个测试工件（都不是输入法故障）：
#   1) TextEdit 的拼写检查会弹 NSCorrectionPanel，它在自己的嵌套事件循环里
#      拦截全部 AppleEvent 与后续按键，导致 osascript 超时(-1712)、读回恒为空。
#      本脚本会先关掉它。
#   2) 若 Squirrel 根本不在系统输入源列表里，合成按键会直接穿透到客户端，
#      读回的自然是原始拉丁字母。脚本会先核对当前输入源。

set -uo pipefail
cd "$(dirname "$0")" || exit 1

echo "════════ 0/4 IMK 连接 ════════"
# 分两层查，缺一不可：
#  a) 进程在不在 —— TIS 只报告「哪个输入源被选中」，不保证系统真的拉起了它
#  b) 系统有没有真的接上 —— 进程活着但没客户端，是另一种更隐蔽的坏法
# 曾经两种都坏过：TISSelectInputSource 返回 0 而进程始终不存在；
# 也有进程加载完 librime 却在 rime 日志里从头到尾没有任何客户端连接事件。
if ! pgrep -x Squirrel >/dev/null 2>&1; then
  echo "✗ Squirrel 进程未运行——输入源已选中，系统却不拉起进程。"
  echo ""
  echo "  注意：输入源的启用与选中本身是正常的（TISEnableInputSource /"
  echo "  TISSelectInputSource 均返回 0，且对 ABC、SCIM、Squirrel 都生效）。"
  echo "  缺的是「选中它 ⇒ 启动它」这一步，且行为不稳定——同一套操作有时"
  echo "  能拉起、有时不能。重启 imklaunchagent / TextInputMenuAgent、"
  echo "  lsregister -f 强制重注册都试过，均无效。"
  echo ""
  echo "  → 请注销并重新登录，然后重跑本脚本。"
  exit 4
fi
pid=$(pgrep -x Squirrel | head -1)
echo "✓ Squirrel 进程在 (pid $pid)"

# 判据说明：--getascii 返回 nascii 是有歧义的，session==0 时同样会返回 nascii，
# 所以它只能当参考、不能单独定性。真正无歧义的信号是菜单栏状态项——
# applyStatusIcon 只在 activateServer 里 session != 0 时才调用，
# 有状态项就说明控制器已建立且 rime 会话有效。
icon=$(osascript -e 'tell application "System Events" to tell process "Squirrel"
if (count of menu bars) is 0 then return "none"
set t to ""
repeat with mb in menu bars
repeat with mi in menu bar items of mb
try
if (title of mi) is not "" then set t to (title of mi)
end try
end repeat
end repeat
return t
end tell' 2>/dev/null)

ga=$("/Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel" --getascii 2>/dev/null)
echo "  --getascii = $ga   状态项 = ${icon:-none}"

if [ -z "${icon// /}" ] || [ "${icon// /}" = "none" ]; then
  echo "✗ 进程活着，但没有菜单栏状态项 → 输入控制器未建立或 rime 会话为 0。"
  echo ""
  echo "  librime 已初始化，IMK 客户端却从未接入 → 需注销重登以重建登录会话。"
  exit 5
fi
echo "✓ 状态项存在（${icon}），控制器已建立且 rime 会话有效"

echo ""
echo "════════ 1/4 辅助功能授权 ════════"
if ! ./axtest >/dev/null 2>&1; then
  echo "✗ MiniMax Code 尚未获得辅助功能权限，合成按键会被系统丢弃。"
  echo "  请打开：系统设置 → 隐私与安全性 → 辅助功能 → 打开「MiniMax Code」"
  exit 3
fi
echo "✓ 已授权"

echo ""
echo "════════ 2/4 当前输入源 ════════"
cur=$(./tis-enable 2>/dev/null | grep "当前输入源" | sed 's/.*: //')
echo "  TIS 报告: ${cur:-未知}"
case "$cur" in
  *Squirrel*)
    echo "✓ 当前是 Squirrel，结果可作为中文输入的判据"
    ;;
  *)
    echo "✗ 当前不是 Squirrel。"
    echo "  合成按键会绕过输入法链直达客户端，读回原始字母——"
    echo "  这种情况下出现英文不代表输入法有问题，而是输入法没被启用。"
    echo "  请先在系统设置 → 键盘 → 文字输入 → 输入法 中确认 Squirrel 存在，"
    echo "  再运行：./tis-enable"
    ;;
esac

echo ""
echo "════════ 3/4 准备 TextEdit ════════"
for k in SpellCheckingEnabled TextAutoCorrectEnabled TextReplacementEnabled \
         NSAutomaticSpellingCorrectionEnabled NSAutomaticTextReplacementEnabled; do
  defaults write com.apple.TextEdit "$k" -bool false 2>/dev/null
done
echo "✓ 已关闭 TextEdit 拼写检查与自动更正（测试工件规避）"

echo ""
echo "════════ 4/4 真机输入测试 ════════"
osascript imk-e2e.applescript
rc=$?
echo ""
echo "退出码: $rc"
exit $rc
