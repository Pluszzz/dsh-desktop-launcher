# DSH Desktop Launcher

DeepSeek Harness Web GUI 的 Windows 桌面启动器套件。

双击桌面快捷方式：服务未启动则自动拉起（最小化窗口运行，可恢复查看日志、关闭即停服），然后打开浏览器进入 GUI；服务已在运行则直接秒开页面。

## 文件说明

| 文件 | 作用 |
|---|---|
| `launch-dsh-web.ps1` | 便携启动器：自动探测仓库位置，幂等启动服务 + 打开浏览器 |
| `install-shortcut.cmd` | 双击即可安装/重建桌面快捷方式（推荐入口） |
| `install-shortcut.ps1` | 安装脚本本体，支持参数：`-Repo` `-Port` `-ShortcutName` |
| `make-icon.mjs` | 图标生成器（零依赖 Node）：SVG 路径 → 多尺寸 `.ico` |
| `dsh-web.ico` 等 | 预生成图标资源（6 尺寸多分辨率 ICO） |
| `whale-path.txt` | 从 favicon.svg 提取的鲸鱼路径数据（图标重建用） |

## 使用

1. 把整个文件夹放进 deepseek-harness 仓库目录，如 `<repo>\dsh-launcher\`
2. 双击 `install-shortcut.cmd` → 自动识别仓库路径，在桌面生成带 Logo 的快捷方式
3. 之后双击桌面 **DeepSeek Harness** 快捷方式即可打开

也可以把文件夹放在任意位置直接运行 `launch-dsh-web.ps1`，启动器会按以下顺序自动探测仓库：

1. 父目录就是仓库（文件夹放在 checkout 内）
2. `repo-path.txt` 记忆文件（安装时写入，或手动选择一次后记住）
3. 安装时内置的路径
4. 用户目录下的常见位置（`~\deepseek-harness`、`~\code\`、`~\CodeWork\`、`~\Documents\` 等）
5. 各固定磁盘根目录浅扫
6. 弹窗手动选择（选择结果会写入 `repo-path.txt` 记住）

## 前提条件

- Windows + PowerShell 5.1（`.ps1` 为 UTF-8 with BOM，中文脚本必须）
- Node.js ≥ 22.19
- 仓库内已执行过 `pnpm install`（启动命令依赖 `node_modules/tsx`，源码启动走 tsx）
- 默认端口 3080 空闲（安装时可用 `-Port` 调整）

## 图标重新生成

图标 = 深蓝圆角底（#4D6BFE）+ 白色鲸鱼。鲸鱼路径取自 deepseek-harness 仓库的 `apps/web/public/favicon.svg`（DeepSeek 品牌 Logo）。

删除 `dsh-web.ico` 后重跑 `install-shortcut.ps1` 会自动重建（需要本机有 Edge 用于无头渲染）；也可手动执行 `node make-icon.mjs` → Edge 渲染 512 PNG → System.Drawing 缩放 → `node make-icon.mjs --pack`。

## 备注

- `repo-path.txt` 与 `launcher-error.log` 是本机运行时文件，不入库（已 gitignore）
- 本套件仅供个人使用，与 DeepSeek Harness 官方无关
