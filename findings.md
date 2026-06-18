# 发现与决策

## 需求
- 用户要求全面检查当前仓库是在做什么，需要输出仓库用途、主要组成、运行方式和风险点。

## 研究发现
- 初始顶层结构显示仓库包含 `pc/`、`android/`、`protocol/` 三个主要目录，并有中英文 README、CHANGELOG、CONTRIBUTING、LICENSE。
- PC 端目录包含 Python 文件：`voice_coding.py`、`voicing_protocol.py`、`network_recovery.py`、`platform_*` 等。
- Android 端目录包含 `voice_coding` 工程。
- 协议目录包含 `voicing_protocol_contract.json`。
- ByteRover 长期记忆对 `Voicing 仓库 用途 架构`、`voice coding PC Android protocol`、`Voicing voicing_protocol network recovery` 三个查询均无匹配记录，说明当前主题尚未沉淀到长期知识库。
- README 明确项目定位：Voicing 将手机语音输入法输出实时发送到电脑光标处，面向和桌面 AI Agent 对话时减少打字。
- 当前版本号为 2.9.4；桌面端支持 Windows/macOS/Linux，手机端为 Android；README 明确 macOS 和 Linux 桌面端仍处内测。
- PC 端是 Python + PyQt5 托盘应用：后台启动 WebSocket server，托盘菜单提供显示 QR、同步输入、开机自启、打开日志、退出。
- Android 端是 Flutter 应用：扫码 PC QR 后做 WebSocket probe，保存 `device_id` 和候选 IP 池；启动、恢复前台、手动刷新时按保存的 IP 候选重连，不再依赖 UDP 自动发现。
- 双端协议由 `protocol/voicing_protocol_contract.json` 固化：WebSocket 端口 9527，历史 UDP discovery 端口 9530，消息类型包括 `text`、`ping`、`connected`、`ack`、`pong`、`sync_state`、`sync_disabled`。
- PC 端收到文本后通过剪贴板粘贴到当前光标处；`auto_enter` 为真时延迟后补发 Enter。
- Android 端有 shadow/commit 发送模式：语音输入组合结束后发送增量文本，静默窗口后 finalize；Auto Enter 通过空内容 commit 消息触发。
- Android 原生层使用 OkHttp，并尝试绑定物理且非 VPN 的 WiFi Network，同时通过 EventChannel 回传键盘高度。
- Release 流程由 GitHub Actions tag `v*` 触发，构建 Android APK、Windows EXE、macOS DMG、Linux binary，并生成 SHA256SUMS。
- 当前本地环境缺少 `python` 命令、Java、Flutter/Dart；`python3` 可用。
- `python3 -m py_compile` 对 PC 端主要 Python 文件通过。
- `python3 -m unittest discover -s pc/tests` 运行 29 个测试，其中 27 个通过，2 个因当前环境缺少 `PyQt5` 导致导入失败。
- `.gitignore` 当前忽略 `findings.md`、`progress.md`、`task_plan.md`、`CLAUDE.md`、`AGENTS.md`，这与本仓 AGENTS 中“PWF 可本地 Git 跟踪、远端 push 拦截”的策略存在不一致。
- 已根据仓库用途初始化根目录 `CLAUDE.md` 与 `AGENTS.md`；两份文件均 165 行，除第一行 H1 外正文通过 `diff` 校验一致。
- Ubuntu/Linux review：当前系统是 Ubuntu 24.04.4 LTS、GNOME、Wayland 会话；仓库文档要求 Ubuntu 22.04+ GNOME X11，代码也会在 Linux Wayland 下主动拒绝启动。
- 当前系统已安装 `Ubuntu on Xorg` 会话入口，因此可以通过登出后选择 Xorg 会话满足会话前提。
- 当前全局 Python 环境缺少 `PyQt5`、`websockets`、`pyautogui`、`pyperclip`、`qrcode`、`psutil`；`python3 pc/voice_coding.py --dev` 直接失败于 `ModuleNotFoundError: No module named 'PyQt5'`。
- 当前系统没有 `python3 -m pip` / `ensurepip`，但 `venv` 模块存在；若走源码开发，需要先补 pip/依赖安装路径。
- 当前系统缺少 Linux CI 中安装的 `libxcb-cursor0`；`libegl1`、`libdbus-1-3`、`libxkbcommon-x11-0` 已安装。
- 当前系统有 `ip`、`xdg-open`、`wl-copy`、`gnome-shell`、`gsettings`、`loginctl`；没有 `xclip` / `xsel`。在 X11 下 `pyperclip` 通常需要 `xclip` 或 `xsel`，否则剪贴板粘贴路径可能失败。
- 当前网络接口 `wlp0s20f3` 有私有 IPv4 `192.168.43.3/24` 和 broadcast，符合代码对 Linux 可广播私有 IPv4 的筛选前提。
- Linux 相关且不依赖 PyQt 导入 `voice_coding.py` 的单元测试通过：`test_platform_utils`、`test_platform_autostart`、`test_platform_keyboard`、`test_network_recovery`、`test_device_identity`、`test_protocol_contract` 共 27 个测试通过。
- 下次继续任务已明确为“Ubuntu 实机可用性修复”：先切到 `Ubuntu on Xorg`，再补系统依赖和 Python runtime，最后做 PC 启动与 Android 扫码端到端验证。
- 2026-06-17 环境复查：`python3-pip`、`python3-venv`、`python3-pyqt5`、`python3-psutil`、`python3-pil` 已安装；`python3 -m pip` 可用；`PyQt5` 已可导入。
- 2026-06-17 环境复查：当前 shell 仍是 `XDG_SESSION_TYPE=wayland`，`platform_utils.ensure_runtime_supported()` 仍会阻止 Linux 桌面端启动，需切换到 `Ubuntu on Xorg`。
- 2026-06-17 环境复查：系统包仍缺 `libxcb-cursor0`、`xclip`、`xsel`；`libegl1`、`libdbus-1-3`、`libxkbcommon-x11-0` 已安装。
- 2026-06-17 环境复查：当前 Python 环境能导入 `PyQt5`、`psutil`、`PIL`，但缺少 `websockets`、`pyautogui`、`pyperclip`、`qrcode`；`pyinstaller` 也未安装。
- 2026-06-17 环境复查：按 `pc/requirements.txt` 版本约束，apt 版本的 `Pillow 10.2.0`、`PyQt5 5.15.10`、`psutil 5.9.8` 低于项目要求的 `Pillow~=12.2.0`、`PyQt5~=5.15.11`、`psutil~=7.2.0`，建议用项目 venv 安装 `pc/requirements.txt`，不要依赖系统 Python 包。
- 2026-06-17 代码层面检查：若目标是让 Voicing 在当前 Linux/Wayland 桌面上运行，主要改动集中在 PC 端后端/平台适配层，不需要修改 Android Flutter 前端或双端协议；PC 端 PyQt 托盘/QR UI 理论上可继续复用。
- 2026-06-17 代码层面检查：当前 Linux 阻断来自 `pc/platform_utils.py::ensure_runtime_supported()` 对 Wayland 的硬拒绝，以及 `pc/voice_coding.py::type_text()` 依赖 `pyperclip.copy/paste` + `pc/platform_keyboard.py::paste_from_clipboard()/press_enter()` 的 `pyautogui` 全局按键模拟路径。
- 2026-06-17 代码层面检查：若移除 Wayland 启动门禁而不替换输入后端，WebSocket/QR/托盘可能启动，但“文字进入当前光标”和 Auto Enter 仍很可能失败；真正需要设计的是 Linux Wayland 文本注入后端，而不是手机端 UI。
- 2026-06-17 GNOME Wayland 方案调研：当前系统是 Ubuntu 24.04.4 LTS、GNOME Shell 46.0、`XDG_SESSION_TYPE=wayland`；`xdg-desktop-portal`、`xdg-desktop-portal-gnome`、`xdg-desktop-portal-gtk` 均在运行。
- 2026-06-17 GNOME Wayland 方案调研：本机 `org.freedesktop.portal.RemoteDesktop` 暴露 `AvailableDeviceTypes=7`、`version=2`，包含 `NotifyKeyboardKeycode`、`NotifyKeyboardKeysym` 和 `ConnectToEIS`；键盘设备类型 bitmask 为 `1`。
- 2026-06-17 GNOME Wayland 方案调研：XDG RemoteDesktop portal 官方文档说明键盘事件必须在 Start 后且获得 KEYBOARD 权限后调用；`ConnectToEIS` 可返回 EIS fd，建立 EIS 后 Notify* 事件不可混用。
- 2026-06-17 GNOME Wayland 方案调研：Ubuntu 24.04 仓库包含 `libei1 1.2.1-1` 和 `liboeffis1 1.2.1-1`；包说明称 libei 面向 Wayland emulated input，oeffis 用于 XDG RemoteDesktop portal D-Bus 通信。
- 2026-06-17 GNOME Wayland 方案调研：`wtype` 只适用于支持 `virtual-keyboard` Wayland 协议的 compositor；GNOME Mutter 相关 issue 与搜索结果显示 GNOME 不支持该协议，因此不适合作为当前系统主方案。
- 2026-06-17 GNOME Wayland 方案调研：`ydotool` 通过 Linux `/dev/uinput` 创建设备，理论上可在 GNOME Wayland 下模拟 Ctrl+V/Enter，实现效果接近 Windows，但需要 `ydotoold` 和 `/dev/uinput` 权限/服务配置，安全边界更粗。
- 2026-06-17 推荐方向：长期/产品化优先使用 RemoteDesktop portal 的键盘权限来实现 GNOME Wayland 输入后端；快速本机可用可先实现 `wl-copy`/剪贴板 + `ydotool` 键盘事件 fallback。
- 2026-06-17 代码范围判断：改造应集中在 PC 端 `platform_keyboard.py`、`platform_utils.py`，并把 `voice_coding.py::type_text()` 里的剪贴板操作抽到平台输入后端；Android Flutter UI、协议 contract、QR/WebSocket 连接状态机无需先改。
- 2026-06-18 实现结果：已在 `pc/platform_keyboard.py` 落地 GNOME Wayland RemoteDesktop portal 键盘后端，Wayland 下粘贴与回车走 portal `NotifyKeyboardKeysym`，Windows/macOS/Linux X11 保持原有快捷键路径。
- 2026-06-18 实现结果：`pc/platform_utils.py` 的启动检查已改为能力检测；当前 GNOME Wayland 会话在 portal 键盘能力可用时可正常启动，不再被一刀切阻断。
- 2026-06-18 实现结果：`pc/voice_coding.py` 已把文本注入收口到平台键盘层，业务层不再直接操作 `pyperclip`。
- 2026-06-18 验证结果：`.venv/bin/python -m unittest discover -s pc/tests` 通过 63 项测试；`flutter analyze --no-fatal-infos --no-fatal-warnings` 与 `flutter test` 通过。
- 2026-06-18 验证结果：`timeout 5s .venv/bin/python pc/voice_coding.py --dev` 在当前 GNOME Wayland 会话下成功启动到 WebSocket 监听阶段，说明 Wayland 前置已具备可运行性。
- 2026-06-18 环境变更：已安装 `.venv`、`libxcb-cursor0`、`xclip`、`xsel`、Flutter 3.27.0 与 Android SDK command-line tools / platform-tools / android-35 / build-tools 35.0.0。

## 技术决策
| 决策 | 理由 |
|------|------|
| 先读 README/依赖/入口，再读核心代码 | 可以先建立项目边界，避免直接陷入实现细节 |
| 不安装缺失依赖 | 用户请求是仓库用途检查，不是环境修复；缺失依赖已作为验证限制记录 |
| `CLAUDE.md` 与 `AGENTS.md` 使用同一正文 | 满足仓库级跨工具同步约束，并让 Claude Code / Codex 读取到一致的项目规则 |
| 当前不安装依赖、不切换桌面会话 | 本次是 review；系统级安装和注销切换会话需要用户主动操作 |
| 将 Ubuntu 修复留作 Phase 8 pending | 用户要求下次再完成这些任务，当前只记录进度不做系统级改动 |

## 遇到的问题
| 问题 | 解决方案 |
|------|---------|
| 当前环境缺少 PyQt5 等 PC runtime 依赖，完整 PC 单元测试无法全部导入 | 记录失败原因；语法编译已通过，未做环境安装 |
| 当前环境缺少 Java、Flutter/Dart，无法本地执行 Android 测试和构建 | 记录环境限制；依据项目配置和 CI 工作流判断构建路径 |
| 当前 Ubuntu 会话是 Wayland | 切换到 `Ubuntu on Xorg`，否则 `ensure_runtime_supported()` 会主动报错 |
| 当前源码开发环境缺少 pip 和 PC runtime 依赖 | 安装 `python3-pip` 或创建可用 venv 后安装 `pc/requirements.txt` |
| 当前缺少 `xclip` / `xsel` | 在 X11 下补装其一，降低 `pyperclip` 剪贴板失败概率 |
| Android debug APK 构建缺 Android SDK | 已补 SDK；用户确认本次未改 Android native/Gradle，无需继续 APK 构建，因此中止构建并还原工具造成的 lock/权限变化 |

## 资源
- 本地仓库：`/home/kevinlasnh/Projects/Voicing`
- ByteRover 查询：无相关历史召回。

## 视觉/浏览器发现
- 未使用视觉或浏览器工具。

---
*每执行2次查看/浏览器/搜索操作后更新此文件*
*防止视觉信息丢失*
