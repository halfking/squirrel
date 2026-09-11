#!/usr/bin/env bash
# 将本目录的 Rime 用户配置部署到 Parallels 中的 Windows 虚机（小狼毫 / Weasel）：
# 通过共享文件夹（\\Mac\Home）推送 default.custom.yaml，再以登录用户身份触发
# WeaselDeployer /deploy 重新编译。
# 前提：虚机运行中且装有 Parallels Tools、已开启共享文件夹；宿主机装有 prlctl。
# 用法：./install-windows.sh [虚机名称] [虚机内用户名]
set -euo pipefail

VM="${1:-Windows 11}"
GUEST_USER="${2:-xutaohuang}"
GUEST_DEPLOYER="${GUEST_DEPLOYER:-C:\\Program Files\\Rime\\weasel-0.17.4\\WeaselDeployer.exe}"
GUEST_RIME_DIR="C:\\Users\\${GUEST_USER}\\AppData\\Roaming\\Rime"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

prlctl list "$VM" >/dev/null 2>&1 || { echo "找不到 Parallels 虚机：$VM" >&2; exit 1; }

# 虚机内以 \\Mac\Home 访问 Mac 家目录，因此配置文件按脚本相对家目录的路径引用
REL_DIR="${SCRIPT_DIR#"$HOME"/}"
if [ "$REL_DIR" = "$SCRIPT_DIR" ]; then
  echo "本脚本需位于 Mac 家目录（\$HOME）之内才能经共享文件夹访问" >&2
  exit 1
fi
SRC_UNC="\\\\Mac\\Home\\${REL_DIR//\//\\}\\default.custom.yaml"

echo "==> 推送 default.custom.yaml 到 $VM:$GUEST_RIME_DIR"
prlctl exec "$VM" cmd.exe /c "if not exist \"$GUEST_RIME_DIR\" mkdir \"$GUEST_RIME_DIR\""
prlctl exec "$VM" cmd.exe /c "copy /y \"$SRC_UNC\" \"$GUEST_RIME_DIR\\default.custom.yaml\" >nul && echo copied"

echo "==> 以虚机用户 $GUEST_USER 触发小狼毫重新部署"
# 小狼毫读取登录用户的注册表，WeaselDeployer 必须在用户会话中运行，
# 而 prlctl exec 以 SYSTEM 身份执行，故用计划任务转到用户上下文。
PS_SCRIPT="\$ProgressPreference = 'SilentlyContinue'
\$a = New-ScheduledTaskAction -Execute '$GUEST_DEPLOYER' -Argument '/deploy'
\$p = New-ScheduledTaskPrincipal -UserId '$GUEST_USER' -LogonType Interactive
Register-ScheduledTask -TaskName WeaselDeploy -Action \$a -Principal \$p -Force | Out-Null
Start-ScheduledTask -TaskName WeaselDeploy"
ENC=$(printf '%s' "$PS_SCRIPT" | iconv -f UTF-8 -t UTF-16LE | base64 | tr -d '\n')
prlctl exec "$VM" powershell.exe -NoProfile -EncodedCommand "$ENC"

echo "==> 等待编译完成并验证部署输出"
for _ in 1 2 3 4 5 6; do
  sleep 3
  if prlctl exec "$VM" cmd.exe /c "findstr /c:\"Shift_L: commit_code\" \"$GUEST_RIME_DIR\\build\\default.yaml\"" >/dev/null 2>&1; then
    echo "==> 完成：build/default.yaml 已包含 Shift_L: commit_code"
    exit 0
  fi
done
echo "警告：未确认到编译输出，WeaselDeployer 可能仍在运行，请在虚机托盘图标确认" >&2
exit 1
