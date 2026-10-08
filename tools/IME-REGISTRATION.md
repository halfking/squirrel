# Squirrel 在本机无法被系统正式注册（输入法列表/切换失效）— 问题记录

记录时间：2026-10-08。影响：macOS 26（Darwin 25.2.0，arm64）。
结论先行：**根因是引擎二进制只有 ad-hoc 签名，macOS 的输入法扫描器拒收；
不是 Squirrel 配置问题，也不是图标/显示缓存问题。**

## 一、症状

| # | 现象 | 状态 |
| --- | --- | --- |
| 1 | 「系统设置 → 键盘 → 输入法」列表里看不到 Squirrel（或加了条目但切换无效） | 持续 |
| 2 | `TISSelectInputSource` 选中 Squirrel 报 `paramErr(-50)`，系统源（ABC/SCIM）都正常 | 持续 |
| 3 | 手写 `com.apple.HIToolbox/AppleEnabledInputSources` 后菜单里能看到 Squirrel；**注销重登后条目被系统按内部注册表重建掉**，又消失 | 每次注销复现 |
| 4 | 原位替换 bundle 内容后（同 bundle id、新 CDHash），TIS 内部注册表留下"僵尸条目"：`tis-list`（活动列表）看不到它，怎么 enable/select 都 -50 | 持续 |

用户视角：注销重登后"没有变化"，容易误判为显示/图标缓存问题（本仓库
历史上确实有过图标缓存问题，见 b2057cc/955e51c），但这次不是。

## 二、根因证据

### 1. AMFI 明确拒绝（`log show` 原文）

```
kernel (AppleMobileFileIntegrity) AMFI: '/Library/Input Methods/Squirrel.app/
  Contents/MacOS/Squirrel' is adhoc signed.
amfid: /Library/Input Methods/Squirrel.app/Contents/MacOS/Squirrel not valid:
  Error Domain=AppleMobileFileIntegrityError Code=-423
  "The file is adhoc signed or signed by an unknown certificate chain"
```

对 `Contents/Frameworks/Sparkle.framework`、`librime.1.dylib` 同样报 -423。

### 2. 对照实验：全新的 ad-hoc 输入法同样不被收录

用 CLT 现做了一个最小 IMK 输入法（`im.test.testim`，结构与 Squirrel 一致，
ad-hoc 签名，放进 `~/Library/Input Methods/TestIM.app`）：
`TISRegisterInputSource` 返回成功，但 TIS 的**全量输入源列表里根本没有它**
（连 includeAll 列表都查不到），活动列表/系统设置自然也没有。
→ **macOS 26 的输入法扫描器直接无视 ad-hoc 签名的输入法**，与 Squirrel
本身的 bundle 结构无关。

### 3. 为什么"以前能用"是假象

旧会话（924fd63）靠**直接写 AppleEnabledInputSources plist** 让鼠鬚管出现在
菜单里，且当时 TIS 内部注册表里旧 CDHash 的条目还是健康的，点选/打字都正常。
但这个 plist 每次注销/重启都会被系统按内部注册表重建——注册表不认的条目
（ad-hoc → 扫描器拒收 → 注册表里没有）写多少遍都会被抹掉。

### 4. 排除项（都试过，无效）

- `PkgInfo` 缺失 → 补上无效；
- Gatekeeper → `spctl --status` 显示本机 assessments 已 disabled，`spctl --assess`
  通过，说明卡的不是 Gatekeeper 这层，是 AMFI 信任层；
- `TISRegisterInputSource` 强制重扫（tools/tis-register）→ 对僵尸条目和
  新 ad-hoc 包都无效；
- 注销重登 → 注册表不重建 ad-hoc 条目，反而把手写的 plist 抹掉。

## 三、修复路径（按推荐顺序）

### A. 正解：用真实的 Apple 签名证书（一劳永逸）

1. Apple Developer Program（付费账号）签发 **Developer ID Application** 证书，
   装进本机钥匙串；
2. `security find-identity -v -p codesigning` 能看到后，运行：

   ```bash
   CODESIGN_IDENTITY="Developer ID Application: <你的名字> (TEAMID)" \
     bash tools/build-user.sh
   ```

   构建脚本会用该身份深签（不再 ad-hoc）；
3. 注销重登（让扫描器重新收录），系统设置里选一次 Squirrel。

### B. 免费证书试验：Apple Development 证书（免费 Apple ID 即可签发）

Xcode 或 `codesign` 可用免费 Apple ID 生成 Apple Development 证书。
扫描器是否接受 Development 级签名未经验证（Developer ID 才是分发用途的
正式信任），值得一试：签完重复 A 的第 2–3 步。若无效，只能走 A。

### C. 临时可用（无证书时，每次注销重登后跑一次）

```bash
bash tools/sync-inputmenu.sh
```

把鼠鬚管补写回输入法菜单并刷新 TextInputMenuAgent。历史经验（924fd63）
表明此路径下打字可用；但切换输入源走 TIS 内部 API，若仍 -50 则点选无效，
只能等 A/B 解决。

## 四、左 Shift 中英切换的验证（引擎功能本身是好的）

引擎层不受签名问题影响，已由 `tools/rime-shifttest` 全量验证（部署产物
`~/Library/Rime/build/default.yaml` 中 `Shift_L: commit_code`）：

```
轻点左 Shift → ascii_mode=true（英文态）  [PASS]
再轻点     → ascii_mode=false（中文态）  [PASS]
英文态按键直通客户端（不被 rime 转换）    [PASS]
Shift+字母 打大写不会误切换               [PASS]
```

系统能选鼠鬚管之后的人工验证（TextEdit）：

1. 打 `nihao` 空格 →「你好」；`wq`/`vb` →「你」「好」；
2. 直接打 `hello` → 候选里有英文单词 hello，选中上屏；
3. 轻点左 Shift → 菜单栏图标变英文态（A）；打 `abc` 原样上屏；
4. 再轻点左 Shift → 回中文态；打 `ceshi` →「测试」。

## 五、相关工具

| 工具 | 用途 |
| --- | --- |
| `tools/tis-list` | 列 TIS 活动输入源 + 当前源（healthcheck 第 2 节依赖） |
| `tools/tis-register` | 强制 TIS 重扫指定 app 包（原位换包后用；对僵尸条目无效） |
| `tools/tis-select` | 按 id 选中输入源（对照实验/切源） |
| `tools/tis-reenable` | 完整 禁用→启用→选中 路径 |
| `tools/sync-inputmenu.sh` | 无证书时把鼠鬚管补写回输入法菜单（每次注销后跑） |
| `tools/ime-healthcheck.sh` | 整条链路体检（app → 注册 → 进程 → 配置 → 引擎端到端） |
