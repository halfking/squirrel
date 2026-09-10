# rime-config — 本地输入法用户配置

本目录保存我们在 Windows（小狼毫 / Weasel 0.17.4）上使用的 Rime 用户配置，
与 Squirrel（macOS 鼠须管）共用同一套 librime 配置格式。

## 内容

- `default.custom.yaml` — 全局用户配置补丁：
  - 启用输入方案：`wubi_pinyin`（五笔·拼音混输，默认）、`luna_pinyin_simp`（朙月拼音·简化字）、`wubi86`（五笔86）；
  - **中英文切换改为仅右 Shift**（`Shift_R: commit_code`），左 Shift 不再触发切换（`Shift_L: noop`）。

## 应用方法（Windows / 小狼毫）

1. 将本文件复制到 Rime 用户目录（默认 `%APPDATA%\Rime`）：

   ```bat
   copy rime-config\default.custom.yaml "%APPDATA%\Rime\default.custom.yaml"
   ```

2. 重新部署：任务栏托盘右键小狼毫图标 →「重新部署」，
   或运行 `"C:\Program Files\Rime\weasel-0.17.4\WeaselDeployer.exe" /deploy`。

## 效果

- 按 **F4** / **Ctrl+`** 呼出方案选单，可在五笔86 / 五笔·拼音 / 简体拼音之间切换；
- 按 **右 Shift** 在中文 / 英文之间切换（若打字中途按右 Shift，已输入的编码以字母原样上屏）；
- 左 Shift 不再切换中英文。

（macOS / 鼠须管下同样把本文件放入 `~/Library/Rime/` 后重新部署即可，配置格式一致。）
