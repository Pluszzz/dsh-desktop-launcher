# DSH Desktop Launcher

DeepSeek Harness Web GUI 的 Windows 桌面启动器套件（适配 dsh 0.1.0-rc.7 全局安装）。

双击桌面快捷方式：服务未启动则自动拉起（最小化窗口运行，可恢复查看日志、关闭即停服），然后打开浏览器进入 GUI；服务已在运行则直接秒开页面。

## 文件说明

| 文件 | 作用 |
|---|---|
| `launch-dsh-web.ps1` | 便携启动器：通过全局安装的 `dsh` CLI（rc.7）幂等启动服务 + 打开浏览器，不依赖源码仓库 |
| `install-shortcut.cmd` | 双击即可安装/重建桌面快捷方式（推荐入口） |
| `install-shortcut.ps1` | 安装脚本本体，支持参数：`-Repo`（可选，仅用于重建图标）`-Port` `-ShortcutName` |
| `dsh-tray.ps1` | 系统托盘管理器：右键菜单可打开 GUI / 显示隐藏服务窗口 / 重启 / 停止服务，并带「开机自启」勾选项 |
| `dsh-tray.vbs` | 托盘隐藏启动包装（wscript 静默拉起，无控制台窗口）；安装脚本自动生成 |
| `make-icon.mjs` | 图标生成器（零依赖 Node）：SVG 路径 → 多尺寸 `.ico` |
| `dsh-web.ico` 等 | 预生成图标资源（6 尺寸多分辨率 ICO） |
| `whale-path.txt` | 从 favicon.svg 提取的鲸鱼路径数据（图标重建用） |

## 使用

1. 全局安装 dsh（rc.7）：`npm install -g @deepseek-ai/dsh`
2. 双击 `install-shortcut.cmd` → 自动检测 dsh CLI 并生成桌面快捷方式
3. 之后双击桌面 **DeepSeek Harness** 快捷方式即可打开

启动器查找 dsh 命令的顺序：安装时内置的路径 → PATH 中的 `dsh.cmd`/`dsh.exe` → `%APPDATA%\npm\dsh.cmd`。

## 系统托盘

安装脚本会生成桌面 **DSH Web 托盘** 快捷方式（wscript 静默启动，无窗口）。托盘右键菜单：

- 打开 Web GUI / 显示服务窗口 / 隐藏服务窗口 / 重启服务 / 停止服务
- **开机自启**：勾选项，勾上后在 Windows 登录时自动启动托盘并拉起 DSH 服务；取消勾选即移除自启。**默认不勾选，安装脚本不会自动设置自启。**

## 前提条件

- Windows + PowerShell 5.1（`.ps1` 为 UTF-8 with BOM，中文脚本必须）
- Node.js ≥ 22.19
- 全局安装 `@deepseek-ai/dsh`（rc.7）
- 默认端口 3080 空闲（安装时可用 `-Port` 调整）

## 图标重新生成

图标 = 深蓝圆角底（#4D6BFE）+ 白色鲸鱼。鲸鱼路径取自 deepseek-harness 仓库的 `apps/web/public/favicon.svg`（DeepSeek 品牌 Logo）。

删除 `dsh-web.ico` 后运行 `install-shortcut.ps1 -Repo <deepseek-harness 路径>` 会自动重建（需要本机有 Edge 用于无头渲染）；也可手动执行 `node make-icon.mjs` → Edge 渲染 512 PNG → System.Drawing 缩放 → `node make-icon.mjs --pack`。

## 备注

- `launcher-error.log` 是本机运行时文件，不入库（已 gitignore）
- 本套件仅供个人使用，与 DeepSeek Harness 官方无关
