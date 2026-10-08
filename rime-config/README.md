# rime-config — 三端通用 Rime 用户配置

本目录保存我们跨 macOS / Windows / Linux 三端共用的 Rime 用户配置：
macOS（鼠鬚管 / Squirrel）、Windows（小狼毫 / Weasel 0.17.4）、Linux（fcitx5-rime / ibus-rime），
同一套 librime 配置格式。

## 内容

- `default.custom.yaml` — 全局用户配置补丁：
  - 启用输入方案：`wubi_pinyin`（五笔·拼音混输，**默认**）、`luna_pinyin_simp`（朙月拼音·简化字）、`wubi86`（五笔86）；
  - **中英文切换：左 Shift 快速切换**（打字中途按下则编码原样上屏），右 Shift 同
    （`Shift_L` / `Shift_R` 均为 `commit_code`）。
- `wubi_pinyin.schema.yaml` — 升级版「五笔·拼音」混输方案（覆盖上游同名方案）：
  - 五笔码与全拼**同一个方案内直接混打**，无需切换；
  - **英文单词候选**：直接敲英文单词（如 `hello`、`world`），单词本身出现在候选
    里，选中即上屏，无需先切英文态；`enable_completion` 还提供前缀补全
    （敲 `hel` 即可补全 `hello`/`help`…）。大写同样支持（`iPhone`、`USA`）；
  - 拼音改用 `luna_pinyin` 全词库 + `script_translator`（上游用袖珍拼音反查，
    词库小、无整句），支持词组与整句；
  - 默认**简体输出**（`simplifier` + t2s，同 `luna_pinyin_simp` 的机制）；
  - 关闭五笔侧 `enable_sentence`：混输时字母串会被五笔造句引擎拼成乱词
    （`nihao`→「悄虚」）并排到拼音整句之前；英文侧同样关闭造句，只出单词候选；
  - 保留 `` ` `` 前缀拼音反查（袖珍拼音词库）。
- `easy_en.dict.yaml` / `easy_en.schema.yaml` — Easy English 英文词库（约 74.5 万
  行，含大小写映射）。**来源**：`BlindingDark/rime-easy-en`（master，
  LGPL-3.0），与上游逐字节一致，勿手改。词库即编码（`hello → hello`）。
  `easy_en.schema.yaml` 本身不进方案选单，部署时负责编译 `easy_en.prism.bin`
  （`table_translator@easy_en` 的检索索引必须依赖它，缺它英文候选会静默失效）。

> **混输的关键认知**：`wubi86` 是纯五笔——排到 schema_list 首位时，打拼音会
> 被五笔引擎拼成乱词上屏（如 `nihao`→「悄虚」），表现就是"拼音不行"。
> 混合输入 = 默认用 `wubi_pinyin` 这**一个**方案即可；Rime 还会记住 F4 选单里
> 最后手选的方案（`previously_selected_schema`），若发现拼音打不出，先用 F4
> 切回「五笔·拼音」。

> **⚠️ 用 plum（东风破）装包会覆盖升级版方案**：`rime-install rime-wubi` 会把
> 上游原版 `wubi_pinyin.schema.yaml`（拼音走反查小词库、繁体输出）拷进用户目录，
> 覆盖本目录的升级版。装完任何 plum 包后，重新拷贝本目录的
> `wubi_pinyin.schema.yaml` 到 Rime 用户目录再重新部署。
> （macOS 安装程序已内置升级版并在 presets 下载**之前**写入，不会被覆盖。）

> **五笔词库版本**：`wubi86.dict.yaml` v0.7 即 rime/rime-wubi 上游最新
> （极点五笔6 底表 + google 词频，已逐字节核对），不存在更新的官方版本；
> `build/` 下的 prism/table 由该词库编译。勿引入未经确认的第三方大词库。
> （Easy English 词库是唯一例外：纯英文词→词编码，不参与五笔/拼音检索，
> `initial_quality: -1` 保证它恒排在中文候选之后。）

> **英文候选的部署前提**：`~/Library/Rime` 里必须同时有
> `easy_en.dict.yaml`（词库）与 `easy_en.schema.yaml`（部署时编译
> `easy_en.prism.bin` 用的索引方案）。只拷词库不拷方案，英文候选会
> 静默失效（librime 找不到 prism，翻译器直接不加载）。

> 左 Shift 切换同时是**引擎出厂默认**：`data/plum/default.yaml` 里
> `ascii_composer/switch_key/Shift_L` 已经是 `commit_code`，所以即使没有这个补丁
> （用户删掉了 `default.custom.yaml`）左 Shift 依然切换中英文。补丁保留是为了让
> 右 Shift 也变成切换键（引擎默认的 `commit_text` 是"原样上屏"，不是切换）。
- `install-linux.sh` — Linux（fcitx5-rime）一键部署脚本，见下文。
- `install-windows.sh` — Windows（小狼毫 / Weasel，Parallels 虚机）一键部署脚本，见下文。

## 应用方法（Windows / 小狼毫）

本机的 Windows 11（Parallels 虚机）已安装小狼毫 Weasel 0.17.4，
Rime 用户目录为 `%APPDATA%\Rime`（即 `C:\<用户>\AppData\Roaming\Rime`）。

推荐：在 Mac 上运行 `install-windows.sh` 一键推送并重新部署（经 Parallels 共享文件夹
`\\Mac\Home` 复制文件，用计划任务以登录用户身份触发 WeaselDeployer）：

```bash
./install-windows.sh [虚机名称] [虚机内用户名]    # 默认 "Windows 11"、xutaohuang
```

手动等价操作：

```bat
copy rime-config\default.custom.yaml "%APPDATA%\Rime\default.custom.yaml"
"C:\Program Files\Rime\weasel-0.17.4\WeaselDeployer.exe" /deploy
```

## 应用方法（macOS / 鼠鬚管）

把 `default.custom.yaml` 与 `wubi_pinyin.schema.yaml` 放入 Rime 用户目录
`~/Library/Rime/`，然后点击菜单栏鼠鬚管图标 →「重新部署」。
验证：`bash tools/ime-healthcheck.sh`（仓库根目录）。

## 应用方法（Linux / fcitx5-rime）

已在一台 Omarchy（Arch Linux ARM，Parallels 虚机）上部署验证。先安装所需包：

```bash
sudo pacman -S fcitx5-rime rime-wubi rime-luna-pinyin
```

fcitx5-rime 的用户配置目录为 `~/.local/share/fcitx5/rime`。推荐用本目录的
`install-linux.sh` 一键部署：通过 ssh 推送 `default.custom.yaml`，远程执行
`rime_deployer --build . /usr/share/rime-data .` 完成编译，并重启 fcitx5：

```bash
./install-linux.sh [user@host]    # 默认 omarchy@10.211.55.12
```

等价的手动操作：

```bash
scp default.custom.yaml omarchy@10.211.55.12:/home/omarchy/.local/share/fcitx5/rime/
ssh omarchy@10.211.55.12 'cd ~/.local/share/fcitx5/rime \
  && rime_deployer --build . /usr/share/rime-data . \
  && fcitx5 -r -d'
```

部署完成后在虚机上验证：

```bash
fcitx5-remote -n   # 应输出 rime
```

（ibus-rime 用户请把配置放到 `~/.config/ibus/rime/`，然后用 ibus 托盘菜单
或 `ibus restart` 重新部署。）

## 效果

- 默认方案「五笔·拼音」：**五笔码与全拼直接混打**——`wq`→你、`vb`→好、
  `wqvb`→你好（五笔），`nihao`→你好、`shiweishuji`→市委书记（拼音整句），均简体输出；
- **英文单词直接出候选**：中文态下敲 `hello`，候选里就有 `hello`，选中上屏；
  敲 `hel` 可前缀补全 `hello`/`help`…（排在五笔/拼音候选之后，翻页即见）；
- 按 **F4** / **Ctrl+`** 呼出方案选单，可在五笔·拼音 / 简体拼音 / 五笔86之间临时切换
  （Rime 会记住最后选择，新会话沿用）；
- 按 **左 Shift** 或 **右 Shift** 在中文 / 英文之间切换
  （打字中途按下时，已输入的编码以字母原样上屏）；
- `` ` `` 前缀反查拼音（袖珍拼音词库），如 `` `nihao ``。
