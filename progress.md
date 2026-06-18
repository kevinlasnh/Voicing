# 进度日志

## 会话：2026-06-13 18:25 CST

### 阶段 1：仓库元信息与长期记忆
- **状态：** complete
- **开始时间：** 2026-06-13 18:25 CST
- 执行的操作：
  - 按启动规则确认当前目录不在 L2 vault 下。
  - 读取 planning-with-files-zh skill 说明。
  - 检查仓库根目录，确认此前缺少 `task_plan.md`、`progress.md`、`findings.md`。
  - 读取 PWF 模板并查看仓库顶层结构。
  - 查询 ByteRover 长期记忆，未找到相关仓库背景。
- 创建/修改的文件：
  - 新增 `task_plan.md`
  - 新增 `findings.md`
  - 新增 `progress.md`

## 测试结果
| 测试 | 输入 | 预期结果 | 实际结果 | 状态 |
|------|------|---------|---------|------|
| Python 语法编译 | `python3 -m py_compile pc/voice_coding.py pc/voicing_protocol.py pc/device_identity.py pc/network_recovery.py pc/platform_utils.py pc/platform_keyboard.py pc/platform_autostart.py pc/platform_instance.py` | 无语法错误 | 通过，无输出 | pass |
| PC 单元测试 | `python3 -m unittest discover -s pc/tests` | 全部测试通过 | 29 个测试运行，27 个通过，2 个因缺少 `PyQt5` 导入失败 | blocked |
| Android 本地测试环境 | `command -v flutter` / `command -v dart` / `java -version` | 工具链可用 | Flutter、Dart、Java 未在 PATH 中发现 | blocked |

## 错误日志
| 时间戳 | 错误 | 尝试次数 | 解决方案 |
|--------|------|---------|---------|
| 2026-06-13 18:25 CST | 更新 PWF 时补丁上下文未匹配 | 1 | 重新读取三件套后使用更精确补丁 |
| 2026-06-13 18:25 CST | PC 单元测试导入 `voice_coding.py` 时缺少 `PyQt5` | 1 | 未安装依赖；记录为当前环境限制 |

## 五问重启检查
| 问题 | 答案 |
|------|------|
| 我在哪里？ | 阶段 5：交付总结 |
| 我要去哪里？ | 目录结构、核心代码、验证与总结 |
| 目标是什么？ | 全面说明当前仓库是在做什么 |
| 我学到了什么？ | 见 findings.md |
| 我做了什么？ | 见上方记录 |

### 阶段 2：目录结构与依赖梳理
- **状态：** complete
- 执行的操作：
  - 读取 `README.md`、`README.zh-CN.md`、`android/README.md`、`android/README.zh-CN.md`。
  - 读取 `pc/requirements.txt`、`android/voice_coding/pubspec.yaml`、`android/voice_coding/android/app/build.gradle`。
  - 读取 `protocol/voicing_protocol_contract.json`。
  - 查看 Android、PC 顶层文件列表和代码行数。
- 创建/修改的文件：
  - 更新 `findings.md`
  - 更新 `progress.md`
  - 更新 `task_plan.md`

### 阶段 3：核心代码阅读
- **状态：** complete
- 执行的操作：
  - 阅读 PC 端 `voice_coding.py` 中文本输入、WebSocket server、QR payload、主入口相关逻辑。
  - 阅读 PC 端 `voicing_protocol.py`、`device_identity.py`、`network_recovery.py`、`platform_utils.py`。
  - 阅读 Android 端 `voicing_connection_controller.dart`、`saved_server.dart`、`voicing_websocket.dart`、`connection_recovery_policy.dart`。
  - 阅读 Android 原生层 `MainActivity.kt` 和 Manifest。
  - 阅读协议契约测试、网络接口测试、保存设备测试。

### 阶段 4：验证与风险检查
- **状态：** complete
- 执行的操作：
  - 检查本地工具链：`python3` 可用；`python`、Java、Flutter/Dart 未在 PATH 中发现。
  - 检查 Python 依赖：当前环境缺少 `PyQt5`、`websockets`、`pyautogui`、`pyperclip`、`qrcode`、`psutil`，`PIL` 可用。
  - 执行 `python3 -m py_compile`，PC 端主要 Python 文件语法编译通过。
  - 执行 `python3 -m unittest discover -s pc/tests`，29 个测试中 27 个通过，2 个因缺少 `PyQt5` 导入失败。
  - 检查 `.gitignore`，发现 PWF 和仓库 agent markdown 当前被忽略。

### 阶段 5：交付总结
- **状态：** complete
- 执行的操作：
  - 准备向用户汇总项目用途、架构、运行方式、验证结果和风险点。
  - 完成中文总结交付。

### 阶段 6：初始化仓库级 Agent 配置
- **状态：** complete
- 执行的操作：
  - 确认仓库根此前没有 `CLAUDE.md` / `AGENTS.md`。
  - 新增 `CLAUDE.md` 与 `AGENTS.md`，内容基于已完成的仓库检查结果。
  - 配置内容覆盖项目定位、目录结构、核心运行行为、协议、开发命令、测试期望、发布规则和 agent 工作注意事项。
  - 运行 `diff -u <(tail -n +2 CLAUDE.md) <(tail -n +2 AGENTS.md)`，确认除 H1 外正文一致。
  - 运行 `git status --short --ignored --untracked-files=all`，确认两份文件当前被 `.gitignore` 忽略。
- 创建/修改的文件：
  - 新增 `CLAUDE.md`
  - 新增 `AGENTS.md`
  - 更新 `task_plan.md`
  - 更新 `findings.md`
  - 更新 `progress.md`

### 阶段 7：Ubuntu/Linux 可用性 Review
- **状态：** complete
- 执行的操作：
  - 阅读 `pc/platform_utils.py`、`pc/platform_keyboard.py`、`pc/platform_autostart.py`、`pc/voice_coding.py` 中 Linux 相关逻辑。
  - 阅读 README 中 Linux 支持说明和 GitHub Actions Linux 构建步骤。
  - 检查当前系统：Ubuntu 24.04.4 LTS、GNOME、Wayland，会话不满足项目当前 X11 运行前提。
  - 检查 X11 登录项，确认系统存在 `Ubuntu on Xorg`。
  - 检查 Python 依赖，确认当前环境缺少 PC 端 runtime 依赖且没有 `python3 -m pip`。
  - 检查系统依赖，确认 `libxcb-cursor0`、`xclip`、`xsel` 缺失。
  - 执行 `python3 pc/voice_coding.py --dev`，失败于缺少 `PyQt5`。
  - 执行 `PYTHONPATH=pc python3` 调用 `ensure_runtime_supported()`，确认 Wayland 下会主动报错。
  - 执行 Linux 相关纯单元测试 27 个，通过。
- 测试结果：
  - `python3 pc/voice_coding.py --dev`：blocked，缺少 `PyQt5`。
  - `ensure_runtime_supported()`：blocked，当前会话是 Wayland。
  - `python3 -m unittest pc.tests.test_platform_utils pc.tests.test_platform_autostart pc.tests.test_platform_keyboard pc.tests.test_network_recovery pc.tests.test_device_identity pc.tests.test_protocol_contract`：27 tests OK。

### 阶段 8：下次继续 Ubuntu 实机可用性修复
- **状态：** pending
- **记录时间：** 2026-06-13 19:28 CST
- 待做事项：
  - 用户决定本次先记录进度，下次继续完成 Ubuntu 可用性修复。
  - 下次应先让用户切换到 `Ubuntu on Xorg` 会话，再验证 `XDG_SESSION_TYPE=x11`。
  - 需要补齐系统依赖：至少 `libxcb-cursor0`，建议同时安装 `xclip` 或 `xsel`。
  - 需要建立可用 Python 运行环境并安装 `pc/requirements.txt`。
  - 完成后运行 `python3 pc/voice_coding.py --dev`，再用 Android 端扫码配对做端到端验证。
- 本次未执行的操作：
  - 未使用 sudo 安装系统包。
  - 未修改系统登录会话。
  - 未创建 Python 虚拟环境或安装 Python 包。

### 阶段 8：Ubuntu 环境复查
- **状态：** in_progress
- **记录时间：** 2026-06-17 CST
- 执行的操作：
  - 检查当前桌面会话变量，确认仍为 `XDG_SESSION_TYPE=wayland`、`DESKTOP_SESSION=ubuntu`。
  - 检查 Python 工具链，确认 `python3`、`pip3`、`python3 -m pip` 已可用。
  - 检查系统包，确认 `python3-pip`、`python3-venv`、`python3-pyqt5`、`python3-psutil`、`python3-pil` 已安装。
  - 检查 Linux 运行依赖，确认 `libxcb-cursor0`、`xclip`、`xsel` 仍未安装。
  - 检查 `pc/requirements.txt` 对应 Python 包导入和版本约束。
- 当前结论：
  - 仍需切换到 X11 会话。
  - 仍建议建立项目 venv 并安装 `pc/requirements.txt`，当前系统 Python 包版本与项目约束不完全一致。

### 阶段 8：Linux 当前系统代码适配讨论
- **状态：** in_progress
- **记录时间：** 2026-06-17 CST
- 执行的操作：
  - 阅读 `pc/platform_utils.py`，确认 Wayland 启动门禁集中在 `ensure_runtime_supported()`。
  - 阅读 `pc/platform_keyboard.py`，确认粘贴和 Enter 当前走 `pyautogui` 模拟按键。
  - 阅读 `pc/voice_coding.py::type_text()` 和 WebSocket 文本处理路径，确认手机端发送协议无需改动。
  - 搜索 README 和 Android 目录，确认现有文档明确 Linux 为 `Ubuntu 22.04+ GNOME X11`，Android 前端不参与桌面输入实现。
- 当前结论：
  - 为当前 Linux/Wayland 运行而改动时，优先范围是 PC 端后端/平台适配层。
  - 不应先动 Android Flutter UI 或协议。
  - 仅删除 Wayland 检查不够，必须替换或扩展 Linux 文本注入实现。

### 阶段 9：GNOME Wayland 同等 Windows 体验改造方案
- **状态：** in_progress
- **记录时间：** 2026-06-17 CST
- 执行的操作：
  - 使用 plan 工具拆解任务：现状确认、网络调研、方案对比、改造计划、PWF 同步。
  - 采样当前系统：Ubuntu 24.04.4 LTS、GNOME Shell 46.0、Wayland；portal 服务均已运行。
  - 通过 D-Bus introspection 确认 RemoteDesktop portal 支持键盘/鼠标/触摸，版本为 2。
  - 使用宿主 Web Search 与 `tavily-search` fallback 检索 XDG RemoteDesktop portal、libei、ydotool、wtype、GNOME Remote Desktop 相关资料。
  - 对照当前代码行号，确认现有输入链路为 `pyperclip` 写剪贴板 + `pyautogui` 触发 Ctrl+V/Enter。
- 当前结论：
  - Windows 同等效果要求自动写入当前光标、可自动 Enter、对 Android 端透明。
  - GNOME Wayland 下不应只删除启动门禁；必须引入新的 Linux 输入后端。
  - 推荐产品化方案是 RemoteDesktop portal 键盘会话；快速本机方案是 `wl-copy` + `ydotool` fallback。

#### 阶段 9 详细方案记录：让 Voicing 在当前 GNOME Wayland 上达到 Windows 同等效果
- **目标定义：**
  - 手机端扫码、连接、发送文本的行为保持不变。
  - PC 端在当前光标所在应用中自动输入手机发来的中文/英文文本。
  - Android 端 Auto Enter 语义保持不变：需要提交时，PC 端自动补发一次 Enter。
  - 尽量保持现有剪贴板恢复行为：写入临时文本、粘贴、短暂等待后恢复原剪贴板。
  - 对 Android Flutter UI、双端协议和 WebSocket/QR 连接模型透明，不引入新的手机端交互。

- **为什么不能只删除 Wayland 检查：**
  - 当前 `pc/platform_utils.py::ensure_runtime_supported()` 会在 Wayland 下直接阻断启动。
  - 即便删除这个阻断，`pc/voice_coding.py::type_text()` 仍依赖 `pyperclip.copy/paste` 写剪贴板，并调用 `platform_keyboard.paste_from_clipboard()`。
  - `pc/platform_keyboard.py` 当前用 `pyautogui.hotkey("ctrl", "v")` 和 `pyautogui.press("enter")` 模拟全局按键；这条路径适合 X11/Windows/macOS，但在 GNOME Wayland 下不可靠。
  - 因此核心不是“允许程序启动”，而是“替换 Linux Wayland 文本注入后端”。

- **代码改造边界：**
  - 主要修改 PC 端：
    - `pc/platform_utils.py`：把 Wayland 一刀切拒绝改为输入后端能力检测。
    - `pc/platform_keyboard.py`：从固定 `pyautogui` 改为可选择的输入 backend。
    - `pc/voice_coding.py::type_text()`：把剪贴板写入、粘贴、回车、恢复剪贴板封装到平台输入层，避免主业务函数知道 X11/Wayland 差异。
    - `pc/tests/test_platform_utils.py`、`pc/tests/test_platform_keyboard.py`：更新 Wayland 测试预期和新增 backend 选择测试。
  - 暂不修改：
    - Android Flutter UI。
    - Android 连接状态机。
    - `protocol/voicing_protocol_contract.json`。
    - QR payload/WebSocket 消息结构。

- **推荐架构：输入后端分层：**
  - 新增或重构为 `TextInputBackend`/`ClipboardBackend`/`KeyboardBackend` 组合。
  - 提供统一能力：
    - `type_text(text: str, auto_enter: bool)`
    - `paste_from_clipboard()`
    - `press_enter()`
    - `is_available()`
    - `describe_unavailable_reason()`
  - 后端选择顺序建议：
    - Windows：保留现有剪贴板 + Windows SendInput/pyautogui fallback。
    - macOS：保留现有剪贴板 + Command+V/Enter。
    - Linux X11：保留现有 `pyperclip + pyautogui`。
    - Linux GNOME Wayland：优先 RemoteDesktop portal keyboard backend。
    - Linux GNOME Wayland fallback：可选 `wl-copy`/剪贴板 + `ydotool` 发送 Ctrl+V/Enter。

- **产品化首选方案：XDG RemoteDesktop portal backend：**
  - 当前系统已经暴露 `org.freedesktop.portal.RemoteDesktop`，`AvailableDeviceTypes=7`，其中 bitmask `1` 是 KEYBOARD。
  - RemoteDesktop portal 支持 `NotifyKeyboardKeycode`、`NotifyKeyboardKeysym` 和 `ConnectToEIS`。
  - 第一版可优先使用 portal 的 `NotifyKeyboardKeycode`/`NotifyKeyboardKeysym` 发送 Ctrl+V 与 Enter，不直接接入 libei。
  - 典型流程：
    - 创建 RemoteDesktop session。
    - `SelectDevices` 请求 KEYBOARD。
    - `Start` session，接受 GNOME 授权提示。
    - 持有 session handle，后续粘贴时发送 Ctrl 按下、V 按下、V 释放、Ctrl 释放；Auto Enter 时发送 Enter 按下/释放。
  - 优点：
    - 符合 GNOME Wayland 安全模型。
    - 不需要 root，也不需要全局 `/dev/uinput` 权限。
    - 更适合作为 Voicing 的正式 Linux Wayland 支持方向。
  - 风险：
    - 首次启动或首次输入可能出现 GNOME 授权提示。
    - session 生命周期要处理好：portal session 被关闭、用户拒绝授权、锁屏/注销后断开。
    - D-Bus Request/Response 是异步模型，Python 实现要谨慎处理超时和错误。
    - `NotifyKeyboardKeysym`/`NotifyKeyboardKeycode` 对组合键和键码映射要做实机验证。

- **后续增强方案：libei / ConnectToEIS：**
  - 当前系统已有 `libei1` 和 `liboeffis1`，Ubuntu 包说明里 `libei` 是 Wayland emulated input client library，`oeffis` 用于 XDG RemoteDesktop portal D-Bus 通信。
  - `ConnectToEIS` 是更现代的输入事件通道；官方文档说明建立 EIS connection 后应只通过 EIS 发送输入事件，不能再混用 Notify*。
  - 不建议第一版直接做，因为 Python binding/ctypes/cffi 接入成本更高，测试面更大。
  - 可在 portal Notify* 后端跑通后作为第二阶段优化。

- **快速本机 fallback：`wl-copy` + `ydotool`：**
  - `wl-copy` 已存在，可用于 Wayland 剪贴板写入。
  - Ubuntu 仓库有 `ydotool`，它通过 Linux `/dev/uinput` 创建设备，能在 X11/Wayland 上模拟键盘输入。
  - 使用方式上可以让 Voicing 写剪贴板，然后调用 `ydotool key` 发送 Ctrl+V，Auto Enter 时发送 Enter。
  - 优点：
    - 实现快。
    - 效果最接近 Windows：全局当前焦点、自动粘贴、自动回车。
  - 风险：
    - 需要 `ydotoold` 常驻。
    - `ydotoold` 通常需要 `/dev/uinput` 权限，可能涉及 root、udev/group 或 systemd service 配置。
    - 安全边界较粗，因为它是系统级虚拟输入设备。
    - 不适合作为默认产品方案，但适合当前本机快速验证。

- **不推荐方案：`wtype`：**
  - `wtype` 依赖 Wayland compositor 支持 `virtual-keyboard` 协议。
  - 当前资料和 GNOME Mutter issue 均显示 GNOME 不支持该协议，因此不适合作为 Ubuntu GNOME 46 的主路径。

- **剪贴板实现建议：**
  - 第一版可以保留 `pyperclip`，但 Wayland 下优先探测 `wl-copy`/`wl-paste` 或 Qt Clipboard。
  - 更理想是把剪贴板读写抽象进 PC 平台层：
    - X11/Windows/macOS：现有 `pyperclip`。
    - Wayland：优先 `wl-copy`/`wl-paste` 或 Qt clipboard。
    - 若读取旧剪贴板失败，只记录 warning，不影响输入。
  - 粘贴本身不应由剪贴板模块触发，而应由 keyboard backend 负责。

- **启动检查改造建议：**
  - 当前 `ensure_runtime_supported()` 不应继续表达为“Wayland 不支持”。
  - 改为：
    - 检测当前平台和 session。
    - 在 Linux Wayland 下检查是否存在可用输入后端：RemoteDesktop portal 可用，或 fallback `ydotool` 可用。
    - 若没有可用后端，报明确错误：当前是 Wayland，但未能初始化 RemoteDesktop portal 键盘授权，也未找到可用 fallback。
  - 错误信息应指导用户如何处理，但不再默认要求切 X11。

- **测试计划：**
  - 单元测试：
    - Wayland 不再直接触发 RuntimeError。
    - RemoteDesktop portal 可用时 backend 选择 portal。
    - portal 不可用但 `ydotool` 可用时选择 fallback。
    - 两者都不可用时返回明确不可用原因。
    - `paste_from_clipboard()` 对不同 backend 调用正确。
    - `press_enter()` 对不同 backend 调用正确。
  - 本机集成测试：
    - 启动 PC 端，不再因 Wayland 直接退出。
    - Android 扫码连接成功。
    - VS Code 输入框、浏览器输入框、终端至少各测试一次文本输入。
    - 中文文本、英文文本、标点、换行/Auto Enter 分别测试。
    - 剪贴板恢复测试：输入前复制一段文本，Voicing 输入后确认剪贴板内容恢复。
    - 锁屏/解锁或 portal session 失效后，确认能重新初始化或给出清晰错误。

- **执行顺序建议：**
  - 第一步：先做输入后端抽象，不改变 Android 和协议。
  - 第二步：实现并 mock 测试 RemoteDesktop portal backend。
  - 第三步：实现 `ydotool` fallback，作为本机验证和失败兜底。
  - 第四步：修改 `ensure_runtime_supported()` 为能力检测。
  - 第五步：实机跑 PC 端 + Android 端端到端验证。
  - 第六步：若确认体验达标，再更新 README/CHANGELOG，把 Linux 支持从 “GNOME X11” 调整为 “GNOME X11 + GNOME Wayland beta” 或类似表述。

### 阶段 9：记录方案后准备提交与推送
- **状态：** in_progress
- **记录时间：** 2026-06-17 CST
- 执行的操作：
  - 用户要求“完成之后 push”。
  - 检查 Git 状态，确认当前 `task_plan.md`、`progress.md`、`findings.md` 被 `.gitignore` 忽略且未被 Git 跟踪。
  - 根据仓库全局 PWF 规则和本次 push 要求，准备从 `.gitignore` 中移除 PWF 三件套忽略规则。
  - 保持 `CLAUDE.md`、`AGENTS.md`、`.brv/`、Python cache 等本地 agent/config/artifact 文件继续忽略，不纳入提交。

### 阶段 9：GNOME Wayland 输入后端实现
- **状态：** complete
- **记录时间：** 2026-06-18 CST
- 执行的操作：
  - 按用户确认的稳定推荐方案，在 PC 端实现 GNOME Wayland RemoteDesktop portal 键盘后端。
  - `pc/platform_keyboard.py` 新增统一 `type_text_at_cursor()`、Wayland `wl-copy`/`wl-paste` 剪贴板路径、RemoteDesktop portal Ctrl+V/Enter 后端。
  - `pc/platform_utils.py` 将 Wayland 启动门禁改为 RemoteDesktop portal 键盘能力检测，不再一刀切阻断 Wayland。
  - `pc/voice_coding.py` 移除业务层直接 `pyperclip` 操作，改为调用平台输入层。
  - 更新 `pc/tests/test_platform_keyboard.py`、`pc/tests/test_platform_utils.py` 覆盖 Wayland portal、剪贴板恢复、后端分支和启动能力检测。
  - 更新 `README.md`、`README.zh-CN.md`、`CHANGELOG.md` 记录 GNOME Wayland 支持与首次 RemoteDesktop 授权提示。
  - 建立 `.venv` 并安装 `pc/requirements.txt`；系统级安装 `libxcb-cursor0`、`xclip`、`xsel`。
  - 安装 Flutter 3.27.0 到 `~/development/flutter-3.27.0`，安装 Android SDK 到 `~/Android/Sdk`。
- 测试结果：
  - `.venv/bin/python -m py_compile pc/voice_coding.py pc/platform_utils.py pc/platform_keyboard.py pc/platform_autostart.py pc/platform_instance.py pc/network_recovery.py pc/voicing_protocol.py pc/device_identity.py`：通过。
  - `.venv/bin/python -m unittest discover -s pc/tests`：63 tests OK。
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`：通过，仍有 4 个既有 `withOpacity` info。
  - `flutter test`：通过。
  - `timeout 5s .venv/bin/python pc/voice_coding.py --dev`：启动到 WebSocket 监听 `192.168.50.113:9527` 后被 timeout 主动结束，证明当前 Wayland 会话下启动前置已通过。
  - `git diff --check`：通过。
  - `flutter build apk --debug`：用户询问后确认本次未改 Android native/Gradle，不需要继续；后台构建已停止，并还原由工具造成的 `pubspec.lock` 与 `gradlew` 权限变化。
- 当前结论：
  - 代码与前置验证已到 Android 实机扫码配对测试之前的状态。
  - 下一步应运行 PC 端常驻进程，并用 Android 手机验证扫码连接、文本输入、Auto Enter 与剪贴板恢复。

### 阶段 10：Android 实机扫码与端到端输入验证
- **状态：** pending
- **记录时间：** 2026-06-18 CST
- 待做事项：
  - 启动 `.venv/bin/python pc/voice_coding.py --dev` 并保持运行。
  - Android 端扫码当前 PC QR 或使用已保存设备连接。
  - 验证普通文本、中文文本、Auto Enter、空 commit 回车与剪贴板恢复。
  - 首次 Wayland 输入时如出现 GNOME RemoteDesktop 键盘授权提示，需要用户批准。

### 阶段 10：托盘菜单弹出修复
- **状态：** complete
- **记录时间：** 2026-06-18 CST
- 问题：
  - 用户反馈 PC 端启动后右键托盘不弹菜单。
- 执行的操作：
  - 检查 `ModernTrayIcon`，发现此前只在 `QSystemTrayIcon.Context` 激活原因下弹出自定义菜单。
  - GNOME/Ubuntu 托盘宿主不稳定地把托盘点击映射为 `Trigger` / `DoubleClick` / `Context`，只监听 `Context` 会导致右键或点击完全无反应。
  - 在 Linux 下为 `QSystemTrayIcon` 设置原生 `QMenu` 作为右键 fallback。
  - 将自定义菜单触发兼容 `Trigger`、`DoubleClick`、`Context`。
  - 新增 `pc/tests/test_voice_coding_tray.py` 覆盖托盘激活原因判断。
- 测试结果：
  - `.venv/bin/python -m py_compile pc/voice_coding.py pc/tests/test_voice_coding_tray.py`：通过。
  - `.venv/bin/python -m unittest pc.tests.test_voice_coding_tray pc.tests.test_platform_keyboard pc.tests.test_platform_utils`：37 tests OK。
  - `.venv/bin/python -m unittest discover -s pc/tests`：65 tests OK。
  - `git diff --check`：通过。
- 注意：
  - 当前 9527 端口被 `python` pid 136115 占用，说明已有旧 PC 端实例在运行；需要重启 PC 端才能加载托盘修复。

### 阶段 10：记录进度并准备提交推送
- **状态：** in_progress
- **记录时间：** 2026-06-18 CST
- 执行的操作：
  - 用户要求先记录进度，然后 push。
  - 检查当前分支为 `main`，远端为 `origin`。
  - 检查待提交改动集中在 GNOME Wayland 输入后端、托盘菜单 fallback、测试、README/CHANGELOG 和 PWF 三件套。
  - 运行 `git diff --check`，结果通过。
- 待完成：
  - 创建 Git commit。
  - 推送到 `origin/main`。

## 会话：2026-06-18（晚）CST

### Linux 托盘前端交互修复（自定义菜单 → 原生菜单）
- **状态：** complete
- 问题：GNOME Wayland 上托盘右键弹两个菜单、图标每 200ms 抖动、启动左上角闪黑框。
- 执行的操作：
  - 细颗粒度审查 `pc/voice_coding.py` 托盘链路；定位 P0 双菜单回归来自上次 `c2bcf71` 同时设 `setContextMenu` + Context 触发自定义菜单。
  - 决策（用户选定）：Linux 改用系统原生 `QMenu`，自定义 Fluent 菜单仅 Windows/macOS 保留。
  - `on_tray_activated` 平台分流：Linux 右键交给 `setContextMenu`/宿主，左键/双击才 `_popup_native_menu()`，杜绝双菜单。
  - `update_icon` 加 `_current_icon_key` 去重，状态未变不 `setIcon`，消除 Linux SNI/AppIndicator 每 200ms 抖动。
  - Linux 跳过自定义菜单预热；QR 预热改为 `ensurePolished()` 不 `show()`，消除 Wayland 启动黑闪。
- 测试结果：
  - `unittest discover -s pc/tests` 69 OK；新增/更新托盘原生菜单路径测试。
  - 用户实机确认托盘交互正常（右键单菜单、左键同菜单、无黑闪）。

### GNOME Wayland portal 输入修复（D-Bus uint32 序列化）
- **状态：** complete
- 问题：手机端发文本触发 `RuntimeError: RemoteDesktop portal SelectDevices 调用失败: Expected type 'u' for option 'types', got 'i'`；后续 `NotifyKeyboardKeysym` 的 `state` 也有同样 `'u' vs 'i'` 问题。
- 执行的操作：
  - 探测 PyQt5 QtDBus：`QDBusArgument.add(value, QMetaType.UInt)` 生成 uint32。
  - 实证（对 live portal）：`SelectDevices.types` 用 `QVariant(QDBusArgument(uint))`；`NotifyKeyboardKeysym.state` 用裸 `QDBusArgument(uint)`，keysym 保持普通 int（本机 portal 内省期望 `(oa{sv}iu)`）。两者均经 live portal 验证通过。
  - 新增 `_dbus_uint()` / `_dbus_uint_variant()` 助手；更新 `pc/tests/test_platform_keyboard.py` 锁定新的类型化传参。
- 测试结果：
  - `py_compile` 通过；`unittest discover -s pc/tests` 69 OK。
  - 实机：portal 授权弹窗出现 = SelectDevices→Start 链路成功，uint 修复有效。

### GNOME portal 永久授权调研与决策
- **状态：** complete
- 调研（修好 tvly SSL 后联网）：GNOME `xdg-desktop-portal-gnome` 不保留 RemoteDesktop 授权，每次启动/重启必弹授权；无 `persist_mode`、无预授权 API（`persist_mode` 只对屏幕捕获生效）。GNOME 官方 issue #175 确认；KDE Plasma 6.3+ 已有预授权；GNOME 尚无，Chrome Remote Desktop 团队在推进标准 API。
- 决策（用户选定）：保持 portal 原样，接受每次启动一次授权点击。综合评估 portal 全面优于 ydotool（安全/零部署/可分发/跨发行版/前瞻性）；ydotool 仅"无弹窗"占优，代价是 `/dev/uinput` 权限降级 + 每用户都要配，不可作为已发布应用默认。ydotool 仅作可选 opt-in 留记，未实现。

### tvly CLI 代理修复（仓库外）
- 现象：宿主自带 WebSearch 实际未联网；tavily 走 clash-verge（127.0.0.1:7897）对 `api.tavily.com` SSL EOF（分流劫持到坏出口），但 tavily 直连本就可达。
- 修复：`~/.bashrc` 增加 `tvly()` 包装函数去掉代理变量直连 tavily；不影响其他工具走代理。

---
*每个阶段完成后或遇到错误时更新此文件*
