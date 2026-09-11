#!/usr/bin/env bash
# 将本目录的 Rime 用户配置部署到 Omarchy 虚机（Arch Linux + fcitx5-rime）：
# 推送 default.custom.yaml -> 远程 rime_deployer 编译 -> 重启 fcitx5。
# 用法：./install-linux.sh [user@host]
set -euo pipefail

HOST="${1:-omarchy@10.211.55.12}"
REMOTE_DIR="/home/omarchy/.local/share/fcitx5/rime"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> 推送 default.custom.yaml 到 $HOST:$REMOTE_DIR/"
ssh "$HOST" "mkdir -p '$REMOTE_DIR'"
scp -q "$SCRIPT_DIR/default.custom.yaml" "$HOST:$REMOTE_DIR/default.custom.yaml"

echo "==> 远程编译 Rime 配置并重启 fcitx5"
ssh "$HOST" bash -s -- "$REMOTE_DIR" <<'REMOTE'
set -e
cd "$1"
rime_deployer --build . /usr/share/rime-data .
# ssh 非交互 shell 没有 D-Bus 会话总线地址，fcitx5 连不上会话就起不来，这里补上
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$XDG_RUNTIME_DIR/bus}"
nohup fcitx5 -r -d </dev/null >/dev/null 2>&1 &
REMOTE

echo "==> 完成。在虚机上执行 fcitx5-remote -n 验证，应输出 rime。"
