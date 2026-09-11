# rime-config — 三端通用 Rime 用户配置

本目录保存我们跨 macOS / Windows / Linux 三端共用的 Rime 用户配置：
macOS（鼠鬚管 / Squirrel）、Windows（小狼毫 / Weasel 0.17.4）、Linux（fcitx5-rime / ibus-rime），
同一套 librime 配置格式。

## 内容

- `default.custom.yaml` — 全局用户配置补丁：
  - 启用输入方案：`wubi_pinyin`（五笔·拼音混输，默认）、`luna_pinyin_simp`（朙月拼音·简化字）、`wubi86`（五笔86）；
  - **中英文切换改为仅右 Shift**（`Shift_R: commit_code`），左 Shift 不再触发切换（`Shift_L: noop`）。
- `install-linux.sh` — Linux（fcitx5-rime）一键部署脚本，见下文。

## 应用方法（Windows / 小狼毫）

1. 将本文件复制到 Rime 用户目录（默认 `%APPDATA%\Rime`）：

   ```bat
   copy rime-config\default.custom.yaml "%APPDATA%\Rime\default.custom.yaml"
   ```

2. 重新部署：任务栏托盘右键小狼毫图标 →「重新部署」，
   或运行 `"C:\Program Files\Rime\weasel-0.17.4\WeaselDeployer.exe" /deploy`。

## 应用方法（macOS / 鼠鬚管）

把 `default.custom.yaml` 放入 Rime 用户目录 `~/Library/Rime/`，
然后点击菜单栏鼠鬚管图标 →「重新部署」。

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

- 按 **F4** / **Ctrl+`** 呼出方案选单，可在五笔86 / 五笔·拼音 / 简体拼音之间切换；
- 按 **右 Shift** 在中文 / 英文之间切换（若打字中途按右 Shift，已输入的编码以字母原样上屏）；
- 左 Shift 不再切换中英文。
