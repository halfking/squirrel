# Squirrel 安装程序 / Squirrel Setup

本目录是 Squirrel（[鼠鬚管](https://github.com/rime/squirrel)）的**跨平台带 UI 安装程序**。
三个平台各有一份**原生实现**（不是 Electron 打包），共用同一份配置负载，界面与流程完全一致：

| 平台 | 技术栈 | 产物 | 大小 |
| --- | --- | --- | --- |
| macOS 13+ | Swift + AppKit | `SquirrelSetup-<v>-macos-universal.dmg` / `.zip` | ~13 MB / ~11 MB |
| Windows 10/11 x64 | C# + WPF（.NET 10 自包含单文件） | `SquirrelSetup-<v>-windows-x64.exe` | ~59 MB |
| Linux x86_64 / aarch64 | C + GTK 3（glibc ≥ 2.34） | `SquirrelSetup-<v>-linux-{x86_64,aarch64}.tar.gz` | ~42 KB |

## 五步流程（三端一致）

1. **检测运行环境** — 系统版本 / 架构 / 已安装的 Rime / 用户配置目录 / 网络与镜像可达性。
2. **安装 Rime 引擎**（需管理员权限）
   - macOS：把安装包内置的 `Squirrel.app` 写入 `/Library/Input Methods/`，并 `chown root:wheel`；
   - Windows：下载官方小狼毫 Weasel 0.17.4 安装包并以 `/S` 静默安装（UAC 提权）；
     从安装目录名（`weasel-X.Y.Z`）解析已装版本，**低于目标版本也会走安装流程升级**；
   - Linux：按发行版选择包管理器（apt / dnf / pacman / zypper / apk）经 `pkexec`
     安装 fcitx5-rime。Ubuntu/Debian 的包列表是 `fcitx5-rime librime-bin`
     （noble 仓库没有 `fcitx5-rime-extra`，列进去整条 apt 会失败；`librime-bin`
     提供第 5 步要用的 `rime_deployer`，`fcitx5-rime` 不依赖它）。
   - 仅当「已安装版本 + `Contents/SharedSupport/default.yaml`」与安装包负载一致时才跳过；
     只看「目录存在」会漏掉引擎更新（负载换了、版本号没变时永远装不上新版）。
3. **写入用户配置** — 把 `rime-config/default.custom.yaml` 写入 Rime 用户目录（先自动备份）：
   - macOS `~/Library/Rime/`、Windows `%APPDATA%\Rime`、Linux `~/.local/share/fcitx5/rime`（或 `~/.config/ibus/rime`）。
4. **安装词库与方案** — 按 `setup/shared/presets.json` 从 plum 上游仓库下载
   wubi86、五笔·拼音（`wubi_pinyin`）、朙月拼音·简体（`luna_pinyin_simp`）及其依赖
   `pinyin_simp`、`luna_pinyin`（基础词库，朙月拼音·简体的 `translator.dictionary`
   指向它；Ubuntu 的 `librime-data` 是空过渡包不带词库，不下载则该方案编译失败），
   内置 jsDelivr / gh-proxy / raw.githubusercontent / gitcode 四个镜像依次回退。
5. **编译并启用输入法**
   - macOS `Squirrel --build` → `--install` → `--enable-input-source`；
   - Windows `WeaselDeployer.exe /deploy`；
   - Linux `rime_deployer --build` 并重启 fcitx5 / ibus。Ubuntu 默认框架是 ibus，
     会用 `im-config -n fcitx5` 把会话框架切到 fcitx5（已是 ibus-rime 用户则不动）。
   编译后校验 `build/default.yaml` 里是否**存在 `Shift_L: commit_code` 这一行**
   （左 Shift 中英切换）。注意不能只 grep `commit_code` 子串：任何键映射到
   `commit_code` 都会让那种检查误判通过。

## 中英文切换：左 Shift 是出厂默认

`Shift_L: commit_code` 同时写在两处，互为冗余：

| 位置 | 作用 |
| --- | --- |
| `data/plum/default.yaml`（随引擎分发的 `default.yaml`） | 出厂默认，**不依赖任何用户配置** |
| `rime-config/default.custom.yaml` | 安装程序写入用户目录，额外把右 Shift 也设成切换键 |

`data/plum/default.yaml` 是生成物（`make plum-data` 从 plum 覆盖，且该目录被 gitignore），
所以引擎默认值由 `scripts/patch-default-switch-key.sh` 在 `copy-plum-data` 这一步打补丁，
而不是手改生成物——手改会被下一次 `make plum-data` 静默还原。脚本幂等，且只改
`switch_key` 里的 `Shift_L` 一项。

两处都生效时，删掉 `default.custom.yaml` 左 Shift 依然是切换键。

## 目录结构

```
setup/
├── build-all.sh              # 一键构建三端
├── shared/presets.json       # plum 方案清单 + 镜像列表（三端共用）
├── macos/                    # Swift/AppKit
│   ├── Package.swift
│   ├── Sources/SquirrelSetup/{main,AppDelegate,MainWindow,Installer,Net,Payload,Shell,Steps}.swift
│   └── build.sh
├── windows/                  # C#/WPF
│   ├── SquirrelSetup.csproj  # EnableWindowsTargeting，可在 macOS/Linux 上交叉发布
│   ├── App.xaml, MainWindow.xaml(.cs)
│   ├── Core/{InstallerEngine,Support}.cs
│   ├── tools/make_icon.py
│   └── build.sh
└── linux/                    # C/GTK 3
    ├── src/squirrel_setup.c
    ├── tools/{make_sysroot,embed,elfinfo}.py
    └── build.sh
```

## 构建

```bash
# macOS（需要 Xcode Command Line Tools）
SWIFT=swift ./build-all.sh

# Windows（在 macOS 上交叉发布 WPF）
DOTNET=/path/to/dotnet ./windows/build.sh

# Linux：在 Linux 上直接用 gcc + libgtk-3-dev
./linux/build.sh

# Linux：从 macOS 交叉编译（zig cc + Debian sysroot）
python3 linux/tools/make_sysroot.py                       # 生成 /tmp/sysroot
ZIG=/path/to/zig SYSROOT=/tmp/sysroot ./linux/build.sh   # x86_64
DEB_ARCH=arm64 SYSROOT=/tmp/sysroot-arm64 python3 linux/tools/make_sysroot.py
TARGET=aarch64-linux-gnu ZIG=/path/to/zig SYSROOT=/tmp/sysroot-arm64 ./linux/build.sh
```

## 使用

- **macOS**：挂载 DMG → 拖入「应用程序」→ 双击运行；或在终端执行
  `SquirrelSetup.app/Contents/MacOS/SquirrelSetup --auto` 无界面完成全部步骤。
- **Windows**：双击 exe（自包含，无需预装 .NET）→ 「开始安装」。
- **Linux**：解压后 `./squirrel-setup`（系统需有 `libgtk-3.so.0`；也可用 `./run.sh`）。

## 已验证 / 未验证

- **macOS：已在本机实机验证** —— 图形界面启动、检测步骤、以及 `--auto` 全流程跑通
  （引擎负载一致→跳过、配置已是最新→跳过、方案文件校验通过、`Squirrel --build` 编译出
  40 个文件且 `build/default.yaml` 校验到 `Shift_L: commit_code`、输入源已注册并启用）。
  2026-10-04 另验证了引擎更新的实际路径：手动换掉 `/Library/Input Methods/Squirrel.app`
  后重跑 `--auto`，第 2 步能识别负载不一致并重新安装（旧逻辑只看目录存在，会静默跳过）。
- **Windows / Linux：源码复查修正后已重新构建**（2026-10-06，见下方改动记录），
  产物结构与三端逻辑一致性已校验，但仍未在对应系统上实跑过完整安装流程——
  需要在 Windows / Ubuntu 真机上各执行一次确认。
- 2026-10-06 复查修正的三端问题：
  - **Linux（Ubuntu 实锤）**：apt 包列表含 noble 仓库不存在的 `fcitx5-rime-extra`
    （整条 apt-get 直接失败）→ 改为 `fcitx5-rime librime-bin`，并在装不上时自动
    `apt-get update` 重试；缺 `librime-bin` 会让第 5 步找不到 `rime_deployer`；
    `sudo -A` 在没有 askpass 时必败 → 提权链改为 `pkexec sh -c …`，
    无 pkexec 时回退 `sudo -A … || sudo …`；安装/编译命令补 `2>&1` 把报错收进日志；
    配置备份文件名加时间戳（原来固定 `.bak-backup` 会互相覆盖）；新增
    `im-config -n fcitx5` 切换默认输入法框架（Ubuntu 默认 ibus，不切的话装完也用不上）。
  - **Windows**：第 2 步只看 `WeaselDeployer.exe` 存在就跳过，旧版引擎（0.16.x）
    会被静默留下 → 从 `weasel-X.Y.Z` 目录名解析版本，低于 0.17.4 走升级；
    第 1 步补上 README 声称的网络/镜像探测（15 秒超时，失败仅警告）。
  - **共享负载**：`presets.json` 补 `luna_pinyin.dict.yaml`（朙月拼音·简体的基础词库，
    Ubuntu 的 `librime-data` 是空过渡包，缺它第 5 步编译该方案必失败）；
    macOS 第 2 步日志的 `du -sh ''path''` 双重引号在带空格路径下会拆词 → 修正。
