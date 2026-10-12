# Squirrel 在 macOS 26 上无法注册/显示/切换 — 问题记录与最终结论

记录时间：2026-10-08/10。影响：macOS 26（Darwin 25.2.0，arm64）。

> **✅ 最终结论（2026-10-10，证据闭环）**
> **macOS 26 的输入法扫描器只收录可信签名链（Developer ID 级）的输入法；
> ad-hoc 签名的输入法（含我们全部手工构建版本）根本进不了 TIS 注册表**
> ——系统设置/状态栏无从显示，TISSelectInputSource 一律 -50，左 Shift 自然
> 无从谈起（引擎层功能本身一直是好的）。
> **修复：官方签名版做引擎底座 + 本仓库的 Rime 用户配置层实现全部功能**
> （`bash tools/install-official-base.sh` 一条命令完成）。

## 一、证据闭环（三条独立证据相互印证）

### 1. 官方发行版签名验证（决定性）

`pkgutil --check-signature Squirrel-1.1.2.pkg`：

```
Status: signed by a developer certificate issued by Apple for distribution
Notarization: trusted by the Apple notary service
Certificate Chain:
  1. Developer ID Installer: Yuncao Liu (28HU5A7B46)
```

包内 Squirrel.app 与 librime.1.dylib 均为
`Authority=Developer ID Application: Yuncao Liu (28HU5A7B46)`。

**修正**：此前依据 rime/squirrel#1132 推断"官方包也是 ad-hoc，所以
ad-hoc 应该能注册"——错误。#1132（装完要重启才出现）是 Developer ID
包的**注册时机**问题；我们遇到的是**签名信任**问题，更深一层。

### 2. amfid 拒绝 ad-hoc（系统日志原文）

```
kernel (AppleMobileFileIntegrity) AMFI: '.../Squirrel.app/Contents/MacOS/Squirrel' is adhoc signed.
amfid: ... not valid: AppleMobileFileIntegrityError Code=-423
  "The file is adhoc signed or signed by an unknown certificate chain"
```

### 3. 对照实验：全新 ad-hoc 输入法同样不可注册

用 CLT 现做的最小 IMK 输入法（TestIM，ad-hoc，`~/Library/Input Methods`）：
`TISRegisterInputSource` 返回成功，但 TIS **全量**输入源列表里没有它——
注册表层面直接拒收，与 bundle 结构、PkgInfo、Gatekeeper（本机已 disabled）、
属主、重扫时机均无关（逐一排除过）。

时间线自洽：注册表里的"僵尸条目"来自本机更早的官方 pkg 安装；后被手工
构建（ad-hoc）原位覆盖 → 条目失效 → "曾可用"（10 月 6 日，靠残留 +
plist 补写的半工作状态）→ 注销/重启后彻底失效。期间系统**没有**升级
（`softwareupdate --history` 核实），排除"系统更新收紧"假设。

## 二、修复方案：官方签名底座 + 用户配置层功能

本仓库的功能改动（五笔·拼音混输、左 Shift 中英切换、英文单词候选）
**全部在 Rime 用户配置层**（`~/Library/Rime`：`default.custom.yaml`、
`wubi_pinyin.schema.yaml`、`easy_en.*`），不依赖改动 app 二进制。
因此引擎换成官方签名版毫无功能损失，却换来系统的正式注册。

一条命令（幂等，两次管理员授权）：

```bash
bash tools/install-official-base.sh
```

它做五件事：下载官方 pkg（校验签名）→ installer 安装 → **清理 postinstall
污染** → 部署用户配置并编译 → 注册/启用/补菜单。完成注销重登，
LaunchAgent 自动选中。

### 已知坑：官方 pkg 的 postinstall 破坏封印

官方 pkg 安装时 postinstall 在包内 SharedSupport 跑 `--build`，把
`build/`、`installation.yaml`、`user.yaml` 写进 bundle，Developer ID 封印
随即失效（codesign 报 sealed resource missing）。**安装后必须清理这三个
产物**（脚本第 3 步），封印恢复完好。部署用户配置时也绝不能在包内目录
跑 deployer（产物会写进进程工作目录），须在 /tmp 等无关目录执行。

## 三、本机最终状态（2026-10-10，注册已打通）

| 项 | 状态 |
| --- | --- |
| 引擎 | 官方 1.1.2（Developer ID 签名，封印完好，root:wheel） |
| TIS 注册 | ✓ 已收录、已启用（healthcheck 第 2 节两条 ✓，此前长期为 0） |
| 用户配置 | 已部署编译：`Shift_L: commit_code` ✓、wubi_pinyin/easy_en prism ✓ |
| 引擎端到端 | rime-shifttest 14/14 全过（左 Shift 双向、不误触、英文候选、混输） |
| 翻页 | `,`/`.` 上下翻页（has_menu 绑定，第一页生效），schematest 实测 ✓ |
| 人工验证 | 用户已通过界面选中并确认输入法生效 |

### 注册打通后的两个收尾现象

1. **AppleEnabledInputSources plist 仍缺条目**：TIS 数据库已启用，但 macOS 26
   不自动补写 plist（924fd63 记录的脱钩）→ 跑 `bash tools/sync-inputmenu.sh`
   幂等补写，否则注销重登后菜单里会暂时看不到。
2. **程序化选中不保持**：`TISSelectInputSource` 返回 0（成功），但系统级
   "当前源"立即回跳、IMK controller 不激活——上游 #1140/#1162 记录的
   Tahoe 回归。**GUI 手动选择（系统设置或输入菜单点选）不受影响**，
   自动化脚本里的选中步骤只能作辅助，不能依赖。

## 四、历史排查记录（保留供参考）

- 注销重登不触发重扫（#1132 同款）；官方 pkg 也提示 requires logging out。
- TIS 全量列表里的旧条目（僵尸）：同 ID 不同 CDHash 的历史残留，select -50。
- 排除项：PkgInfo 缺失、Gatekeeper（assessments disabled）、bundle 属主
  （root:wheel 后中途重扫仍不行——因为签名才是门槛）、TISRegisterInputSource
  强制重扫、开机扫描（对 ad-hoc 同样拒收）、直接写 AppleEnabledInputSources
  （每次登录被系统按内部注册表重建）。
- 相关上游 issue：#1132（首次安装不自动出现，需重启）、#1140/#1162
  （Tahoe 程序化切换的 controller 激活回归——选中超时/不激活时参考）。

## 四之二、菜单栏「两个图标」与重复注册（已确认的缺陷 + 尚未证实的归因）

### 已确认：注册重复

`AppleEnabledInputSources` 里曾同时存在两条 Squirrel 记录：

- bundle 级（`InputSourceKind = Keyboard Input Method`，无 `Input Mode`）
- 模式级（`Input Mode = …Squirrel.Hans`）

bundle 级那条会让 TIS 多注册出一个 `im.rime.inputmethod.Squirrel` 输入源，
其 `kTISPropertyIconImageURL` 为 **NULL**（实测确认）。重复注册本身是
要清理的缺陷——`tools/sync-inputmenu.sh` 现在只保留唯一一条 Input Mode
记录，并清掉 bundle 级条目与重复项（幂等自愈）；`fix-ime.sh` 第 3 步复用
同一份逻辑。

### 已排除：不是图标资源画错

用 `tools/tis-icon.c` 实测：`.Hans` 的 icon 正常解析到已安装的
`rime-menu-v4.png`，alpha 包围盒 64×62（画布 64×64，上下各 1px 透明边），
**几何无异常**。Swift 侧也不参与：`applyStatusIcon` 只赋值 `button.title`
（「中」/「Ａ」），从不设置 `button.image`。

### 尚未证实：重复注册就是「上下错位」症状的成因

上报的症状是「占两个图标高度，上面空白、下面才是正确图标」——这是**垂直**
描述。但菜单栏是**水平**排布的：状态项实测为 `y=3, h=24`（单行），各指示器
按 x 递增并排。两个重复输入源会表现为**两个图标并排**，而不是一个在上、
一个在下。

因此重复注册**不足以解释**该症状，真正的垂直错位成因仍未定位。

### 下一嫌疑：图标画布尺寸超出系统惯例（未验证）

系统自带输入法图标**一律是 16×16 或 32×32 的 TIFF**（实测遍历
`/System/Library/Input Methods`：`SCIM.tiff`/`Korean.tiff`/`Ainu.tiff`
= 16×16，`Hiragana.tiff`/`Katakana.tiff`/`Tamil.tiff` = 32×32，
均为 72dpi，即 1px = 1pt）。本仓库的 `rime-menu-v4.png` 是 **64×64**，
比惯例大 2–4 倍。

菜单栏槽位实测约 22pt（状态项 h=24）。64×64 PNG 自然尺寸为 64pt，
必须被压缩到 0.344 倍才能放进槽位；一旦某条路径按原始尺寸绘制或
非等比适配，就会**垂直溢出/裁切**——这正好是"上下错位"这种垂直症状的
形状，也和 99fcd78 记下的"48px+@2x 组合在 1x 屏上被裁成碎片"同类。

已做的验证与限制：把 16×16 版本临时装进 bundle 并重签后，TIS 能立即
读到新尺寸（`tools/tis-icon.c` 报 `canvas=16x16`），但**当时的登录会话
里菜单栏截不出任何图标**，无法确认渲染结果，因此**没有把 16px 版本
落库**，已把 bundle 还原为原 64×64（MD5 与仓库一致）。

下次复现时按这个顺序验：

1. 先确认症状仍在（TIS 按登录会话缓存，见下）。
2. 临时把 `rime-menu-v4.png` 换成 16×16 或 32×32（**同名**替换，避免
   触发"换路径要重登"的缓存问题），重签后注销重登。
   `tools/switch-menu-icon.sh` 就是干这个的。
3. 若换尺寸后症状消失 → 确认是画布尺寸问题，再正式把资源改成合规尺寸
   并同步 `Info.plist`、`build-user.sh`、构建骨架三处。

若症状消失但图标偏糊，说明该尺寸在此 artwork 下不理想，可改用 32×32
或补一份 `rime-menu-v4@2x.png`（64×64）走 Retina 路径。

若再遇到，请截图并记录：菜单栏整体高度、输入法指示器的 y 范围与高度，
以及是否恰逢注销重登后首次出现。

**注意**：plist 改完不等于立刻生效。TIS 的输入源列表**按登录会话缓存**，
`killall TextInputMenuAgent` 不足以刷新，必须**注销重登**后菜单栏才会按新
条目重建。这也是本仓库反复记录的那个 TIS 图标/输入源缓存问题。

## 五、已知外观问题：菜单栏图标显示为"多国语言"（地球）

官方 1.1.2 的菜单图标键指向 **rime.pdf**（矢量），macOS 26 的 TIS 渲染
PDF 菜单图标失败，退化成系统占位的地球图标。本仓库手工构建时代用
`resources/rime-menu-v3.png`（PNG 位图）修过（b2057cc/955e51c）。

**在官方底座上不能修**：换图标必须改包内 Resources/Info.plist → Developer ID
封印失效 → 输入法又无法注册（外观换功能，不值得）。等上游发布修了图标的
新版本后，重跑 `bash tools/install-official-base.sh` 即可获得；也可把
PNG 图标方案（rime-menu-v3.png + Info.plist 三键指向它）作为 patch 贡献给上游。

## 六、工具清单

| 工具 | 用途 |
| --- | --- |
| `tools/install-official-base.sh` | **一键修复**：官方底座 + 配置部署 + 验证 |
| `tools/tis-list` | 列 TIS 活动输入源 + 当前源 |
| `tools/tis-register` | 强制 TIS 重扫指定 app 包 |
| `tools/tis-select` / `tis-reenable` | 选中输入源 / 完整禁用-启用-选中 |
| `tools/auto-enable-at-login.sh` + LaunchAgent | 登录后自动注册并选中 |
| `tools/sync-inputmenu.sh` | 补写/收敛输入菜单条目（幂等自愈，只留一条 Input Mode） |
| `tools/tis-icon.c` | 诊断：打印 TIS 解析出的图标路径与其 alpha 包围盒几何 |
| `tools/ime-healthcheck.sh` | 整条链路体检（含引擎端到端） |
| `tools/build-user.sh` | 手工构建（开发用；装机请用官方底座，ad-hoc 无法注册） |
