# 部署更新源到 files.kxpms.cn

## 目录结构（上传到站点根，使最终 URL 为 https://files.kxpms.cn/squirrel/...）

```
squirrel/
├── appcast.xml              # Sparkle 更新源（app 内 SUFeedURL 指向这里）
├── Squirrel-1.1.2.zip       # Sparkle 升级包（只含 Squirrel.app，EdDSA 已签名）
├── rime-config/             # 最新混输配置（default.custom.yaml + wubi_pinyin.schema.yaml）
├── 1.0.0/                   # 三平台安装包（Windows/Linux 配置拉自上游）
├── 1.1.0/                   # macOS 安装包（内嵌完整修复版 app）
└── SHA256SUMS.txt
```

## 首次/日常发版

1. 构建 app：`bash tools/build-user.sh "/Library/Input Methods/Squirrel.app"`
2. 构建安装包：`cd setup && VERSION=x.y.z ./build-all.sh`（各平台按工具链可用性）
3. 组装发布目录（含 EdDSA 签名与 appcast）：`bash setup/upload/make-release.sh <app版本> <安装包版本...>`
4. 将 `setup/upload/squirrel/` 整个目录上传到 files.kxpms.cn 的 `squirrel/` 路径
   （Web 管理界面上传；服务器仅开放 80/443，SSH/FTP 不通。若日后拿到上传
   API 凭据，可在本文件追加 curl 命令实现一键部署）
5. 验证：`curl -s https://files.kxpms.cn/squirrel/appcast.xml | head`
   客户端：Squirrel 菜单 → 检查新版本

## Sparkle 签名密钥（setup/sparkle/）

- `ed25519.key` 私钥（已 gitignore，**务必备份**，丢失则无法再发更新）
- `SUPublicEDKey.b64` 公钥（已写入 app 的 Info.plist `SUPublicEDKey`）
- 公钥必须与签 appcast/zip 的私钥配对；换密钥对后所有已装 app 需重装才认新源
