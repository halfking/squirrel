#!/usr/bin/env bash
# install-official-base.sh — 用官方签名版 Squirrel 做引擎底座，再部署本仓库的
# Rime 用户配置（五笔·拼音混输 + 左 Shift 中英切换 + 英文单词候选）。
#
# 为什么引擎用官方包而不是手工构建（详见 tools/IME-REGISTRATION.md）：
#   macOS 26 的输入法扫描器只收录可信签名链（Developer ID 级）的输入法。
#   官方 Squirrel-1.1.2.pkg 经验证为
#     "Developer ID Application: Yuncao Liu (28HU5A7B46)" + Apple 公证，
#   而手工构建只能 ad-hoc 签名——对照实验（tools/ 下可复现）表明 ad-hoc
#   输入法连 TIS 注册表都进不去，系统设置/状态栏自然无从显示。
#   本仓库的全部功能改动都在 Rime 用户配置层（~/Library/Rime），不依赖
#   改 app 二进制，因此"官方签名底座 + 我们的配置"即可达成全部功能目标。
#
# 已知坑（本脚本已处理）：官方 pkg 的 postinstall 会在包内 SharedSupport
#   跑一次 --build，把 build/、installation.yaml、user.yaml 写进 bundle，
#   破坏 Developer ID 封印（codesign 报 sealed resource missing）。
#   安装后必须清理这三个产物，封印才能恢复。
#
# 用法：bash tools/install-official-base.sh
#   幂等：重复执行安全。需要两次管理员授权（安装 pkg、清理污染）。
#   完成后注销/重启一次（官方 pkg 自己也提示 requires logging out），
#   登录后 LaunchAgent（cn.kxpms.squirrel-autoselect）会自动注册并选中。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REL_TAG="1.1.2"
PKG="/tmp/Squirrel-${REL_TAG}.pkg"
APP="/Library/Input Methods/Squirrel.app"
RIME="$HOME/Library/Rime"

echo "==> 1/5 下载官方安装包 Squirrel-${REL_TAG}.pkg"
if [ ! -s "$PKG" ]; then
  curl -sL --max-time 600 -o "$PKG" \
    "https://github.com/rime/squirrel/releases/download/${REL_TAG}/Squirrel-${REL_TAG}.pkg"
fi
pkgutil --check-signature "$PKG" | grep -E "Status|Developer ID" || {
  echo "✗ 官方包签名校验失败"; exit 1; }

echo "==> 2/5 安装（弹一次管理员授权框）"
osascript -e "do shell script \"/usr/sbin/installer -pkg '$PKG' -target /\" with administrator privileges"

echo "==> 3/5 清理 postinstall 污染（恢复 Developer ID 封印，弹一次授权框）"
osascript -e "do shell script \"rm -rf '$APP/Contents/SharedSupport/build' '$APP/Contents/SharedSupport/installation.yaml' '$APP/Contents/SharedSupport/user.yaml'\" with administrator privileges"
codesign --verify --deep --strict "$APP" || { echo "✗ 封印仍损坏"; exit 1; }
echo "   官方签名封印: 完好"

echo "==> 4/5 部署本仓库的 Rime 用户配置（混输 / 左 Shift / 英文候选）"
mkdir -p "$RIME"
cp "$ROOT/rime-config/default.custom.yaml" \
   "$ROOT/rime-config/wubi_pinyin.schema.yaml" \
   "$ROOT/rime-config/easy_en.dict.yaml" \
   "$ROOT/rime-config/easy_en.schema.yaml" "$RIME/"
cd /tmp   # 绝不在包内跑部署：产物会写进进程工作目录污染 bundle
"$APP/Contents/MacOS/rime_deployer" --build "$RIME" \
  "$APP/Contents/SharedSupport" "$RIME/build" > /tmp/squirrel-official-deploy.log 2>&1
grep -q 'Shift_L:[[:space:]]*commit_code' "$RIME/build/default.yaml" \
  || { echo "✗ 编译产物缺 Shift_L: commit_code"; exit 1; }
[ -f "$RIME/build/wubi_pinyin.prism.bin" ] && [ -f "$RIME/build/easy_en.prism.bin" ] \
  || { echo "✗ 词库 prism 编译缺失"; exit 1; }
echo "   部署完成：Shift_L=commit_code ✓  wubi_pinyin/easy_en prism ✓"

echo "==> 5/5 注册并启用（立即；正式收录需注销/重启后的开机扫描）"
killall Squirrel 2>/dev/null || true
open "$APP"; sleep 3
"$ROOT/tools/tis-register" "$APP" || true
"$APP/Contents/MacOS/Squirrel" --enable-input-source >/dev/null 2>&1 || true
bash "$ROOT/tools/sync-inputmenu.sh" || true

cat <<'NEXT'

完成。下一步（必须）：
  注销并重新登录（或重启）——开机扫描收录官方签名输入法后，
  LaunchAgent 会自动选中鼠须管；菜单栏出现 🐿️ 即可用：
    nihao→你好   wq/vb→你/好（五笔）   hello→候选含英文单词
    轻点左 Shift → 中英切换（引擎端到端已 14/14 验证）
  若登录后仍未出现：系统设置 → 键盘 → 输入法 → 编辑 → + → 添加 Squirrel。
NEXT
