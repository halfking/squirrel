# 中文输入法验证清单

修复「切到中文输入法却打不出中文」后，按下面两步验收。

## 第一步：自动化检查（一条命令）

```bash
bash ~/workspace/squirrel/tools/ime-healthcheck.sh
```

覆盖应用本体 → 系统输入源注册 → 进程与引擎 → Rime 配置 → 引擎端到端。
引擎端到端用 librime 直接驱动**已安装 app 内**的真实配置，验证
`nihao` →「你好」（拼音）、`wq`/`vb` →「你」「好」（五笔混输）、
`hello` → 候选含「hello」且选中后原样上屏（英文单词候选）、左 Shift 切
英文/切回中文、英文态字母直通客户端。

## 第二步：真人在键盘上核对（必做）

自动化**无法**替代这一步，原因见下方「为什么不能自动验证」。

打开 TextEdit（或任意编辑器）新文档，依次确认：

| # | 操作 | 期望结果 |
| --- | --- | --- |
| 1 | 输入 `nihao`，按空格 | 上屏「你好」，并弹出候选窗 |
| 2 | 输入 `wq`，按空格 | 上屏「你」（五笔码直出，混输生效） |
| 3 | 输入 `vb`，按空格 | 上屏「好」 |
| 4 | 中文态直接输入 `hello` | 候选里出现英文单词「hello」（排在中文候选之后），数字键选中即上屏 |
| 5 | 输入 `hel` | 候选里出现 `hello`/`help` 等前缀补全 |
| 6 | 轻点一下**左 Shift** | 状态栏图标变为英文态 |
| 7 | 输入 `abc` | 原样显示 `abc`，不弹候选 |
| 8 | 再轻点一下**左 Shift** | 状态栏图标变回中文态 |
| 9 | 输入 `ceshi`，按空格 | 上屏「测试」 |

只要 1–3 成立就说明五笔·拼音混输已修好；4–5 成立说明英文单词候选生效；
6–8 成立说明左 Shift 中英切换已修好。

## 出问题时先跑这一条

```bash
bash ~/workspace/squirrel/tools/fix-ime.sh
```

它会核对引擎配置并把当前输入源切回鼠鬚管，然后复核。

若仍打不出中文，检查当前输入源是不是停在了 `com.apple.keylayout.ABC`
（纯英文键盘布局）——那会完全绕过鼠鬚管：

```bash
bash tools/tis-list | tail -3
# 期望：[Squirrel - Simplified] im.rime.inputmethod.Squirrel.Hans
```

注意：**原位替换过 app 包内容（升级/重装）后**，TIS 的输入源注册表里可能
残留旧版本的"僵尸条目"——`tis-list` 里看不到 Squirrel、`TISSelectInputSource`
报 -50。这类问题只能等系统在**注销/重启后重扫** `/Library/Input Methods`
解决：注销一次再登录，到「系统设置 → 键盘 → 输入法」里选一次 Squirrel。
（`tools/tis-register` 可强制重扫描，但对已成僵尸的条目无效。）

更严重的情况——**系统设置列表里始终没有/无法选中 Squirrel，注销后手写的
菜单条目又被抹掉**——这是 macOS 26（Tahoe）的已知安装流程问题：注销不够、
需要**完整重启**，重启后先 `open "/Library/Input Methods/Squirrel.app"`
运行一次，再到系统设置输入法列表里用 `+` 手动添加（上游官方包同样如此，
见 rime/squirrel#1132）。完整证据链、操作序列与兜底方案见
**[tools/IME-REGISTRATION.md](IME-REGISTRATION.md)**；
菜单条目丢失时 `bash tools/sync-inputmenu.sh` 一键补回。

## 为什么不能自动验证"能打出中文"

`tools/imk-e2e.applescript` 用 AppleScript `keystroke` 投递按键，走的是
`CGEventPost(kCGHIDEventTap)` 注入的**合成事件**。这类事件绕过输入法链，
直接投递给前台控件，librime 收不到：

- 在 TextEdit 里投递 `nihao`+空格，文件里得到原样 ASCII `Nihao`；
- 同一时刻 Squirrel 的引擎日志**没有任何新记录**，说明 librime 根本没被调用；
- 输入源确认为 `im.rime.inputmethod.Squirrel.Hans`，且 Squirrel 确实为该
  客户端激活过 IMK 服务器（XPC peer 连接建立），链路本身是通的。

所以自动化结果里出现英文是**测试方法的必然产物**，不能据此判断输入法故障。
任何输入法做这套合成测试都会得到同样的英文。
