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

## 2026-06-18 GNOME Wayland 托盘改造与 portal 输入修复

- 决策：Linux 托盘改用系统原生 `QMenu`，自定义 Fluent 菜单仅 Windows/macOS 保留。原因：自定义 `Qt.Popup` 菜单在 GNOME/Wayland 下有定位（GNOME 顶栏方向与 Windows 底部任务栏相反）、半透明+`QGraphicsDropShadowEffect` 黑块、Esc 失焦、`QSystemTrayIcon.geometry()` 无效等一堆问题；上次 `c2bcf71` 同时设 `setContextMenu` + Context 触发自定义菜单导致右键弹两个菜单。改原生菜单后这些问题随架构切换自动消失。
- 关键：Linux 右键（Context）必须交给 `setContextMenu`/宿主，不能在 `activated` 里再 `_popup_native_menu()`，否则双菜单叠加；左键/双击才手动 `native_menu.popup(QCursor.pos())`。
- Linux SNI/AppIndicator 宿主每次 `setIcon` 都可能重建图标 → 已连接后图标每 200ms 抖动。修法：`update_icon` 记录 `_current_icon_key`，状态未变跳过 `setIcon`。
- Wayland 禁止客户端自由定位顶层窗口，`move(-10000,-10000)+show()+hide()` 预热会让窗口短暂可见闪在左上角。Linux 改为 `ensurePolished()` + `layout().activate()`，不 `show()`。
- PyQt5 D-Bus uint32 序列化：Python `int` 默认序列化成 `'i'`；XDG portal 多个字段要 `'u'`。强制 uint32：`QDBusArgument.add(value, QMetaType.UInt)`。顶层参数用裸 `QDBusArgument`；`a{sv}` map 值用 `QVariant(QDBusArgument)`。已对 live GNOME portal 验证：`SelectDevices.types` 与 `NotifyKeyboardKeysym.state` 用此法通过；keysym 保持普通 int（本机 portal 内省期望 `(oa{sv}iu)`，而非 spec 的 `(oa{sv}uu)`）。
- GNOME RemoteDesktop portal **不能**持久授权：每次启动/重启必弹授权，无 `persist_mode`/预授权 API（GNOME issue #175）。这是 GNOME 安全设计，非 bug。当前"每次启动授权一次、退出自动失效"已是 portal 极限。
- 决策：保持 portal 默认。ydotool（绕开 portal，`/dev/uinput`）可在无弹窗一项上占优，但代价是系统级虚拟键盘权限降级 + 每用户都要配 + 不可分发；Voicing 是已发布应用，综合选 portal。ydotool 仅作可选 opt-in 留记，未实现。
- tvly SSL 根因不是 tvly 配置：`api.tavily.com` 直连可达，但 clash-verge 分流劫持到坏出口导致 SSL EOF。修法：`~/.bashrc` 加 `tvly()` 去掉代理变量直连。

## 2026-06-18 自定义菜单宽度特性 + QR 动画与 Wayland surface

- **Linux 托盘用系统原生 `QMenu`（上轮已切）**：对 `ModernMenuWidget` 的宽度/分隔条改动在 Linux 不可见；Linux 的分隔条来自 `_setup_native_context_menu` 的 `addSeparator()`，已删除。GNOME 原生 QMenu 宽度理论按文字自适应，但用户反馈仍"不自适应"，需复核具体表现。
- **PyQt5 顶层 Popup 窗口 adjustSize 宽度偏大**：实测 `ModernMenuWidget` `sizeHint=164`、`minimumSizeHint=164`、`minimumSize=0`，但 `adjustSize()` 给出 `200`（多约 36px，原因疑似 Qt 对顶层 Popup 窗口的调整逻辑）。修法：`show_at_position` 里 `adjustSize()` 后追加 `self.setFixedWidth(self.sizeHint().width())` 强制收紧，宽度随最长文字自适应。offscreen 实测收紧到 164。
- **QR 弹窗"下方第二个 QR"闪动根因（Wayland/Mutter）**：打开动画期间顶层窗口是大 `canvas_rect`（横跨托盘锚点→屏幕中心），动画 pixmap 的 QR 位于该旧缓冲**中部**（约 y400）。收尾 `_finish_open_animation` 要从 `canvas_rect` 切到 `end_rect`（原点从托盘→中心），若在**可见状态下** resize+move，Mutter 会把上一帧旧缓冲按**新原点**重显 → QR 出现在「中心 + y400 偏移」= 中心下方。修法：收尾先 `hide()` 解除 surface 映射（unmap），在不可见时完成 resize/move，再 `show()` 出最终容器画面——Mutter 只显示最终一帧。需注意：hide/show 抖动可能触发 `focusOutEvent` → `_maybe_close_on_focus_loss`；修法里收尾期间保持 `_animation_mode=True` 让该检查直接 return（`_animation_mode` 判断在 `_maybe_close_on_focus_loss` 开头）。
- **遗留**：第二版修法消除"下方第二个 QR"，但用户反馈 QR 到达中心时**自身闪动一次**（pixmap→container 切换那一帧，或 hide/show 引入的再显）。待定位：可能是 hide/show 本身的再显、或 pixmap（全对话框渲染）与最终 container 在中心位置不完全对齐导致的一帧跳变。
- **QR 闪动整体结论（重读 QRSuccessOverlay + QRCodeDialog 全生命周期后）**：两个闪动同根——"从右上角飞入"效果要求打开动画期顶层窗口是大 `canvas_rect`（横跨托盘→中心），收尾从 canvas 缩到 `end_rect`；而 Wayland/Mutter 上**任何收尾的 resize（可见→下方重影）或 hide/show remap（→自身闪动）都会闪**，二者是同一根问题的两面。根治只能从架构上消除收尾几何变化：窗口恒定 end_rect 尺寸，动画只做位置移动+内容缩放+淡入（A 方案，保留飞入）；或砍飞入改原地缩放淡入（B 方案，最稳）。待用户选。
- **GNOME 原生 QMenu 宽度偏大根因**：`actionGeometry` 显示每项占满整菜单宽（实测 `sizeHint=168` vs 最长文本"显示 QR 码"仅 84px），是默认 QMenu item 水平 padding（左勾选框位 + 右留白）过大。修法：stylesheet 仅收紧 item 内边距（`QMenu::item { padding: 6px 12px 6px 20px; }`），不改 QMenu 背景边框以保 GTK 原生外观；offscreen 实测 168→134。注：offscreen 用 Qt 默认 style，GNOME GTK 实际宽度不同，但收紧幅度应一致。

## 2026-06-19 QR 弹窗中心直接出现

- 用户选择 B 方案：不保留 QR 从托盘/右上角飞入。产品行为改为点击「显示 QR 码」后，QR 弹窗直接出现在屏幕中心。
- 实现决策：`QRCodeDialog` 不再使用跨锚点和中心的大 `canvas_rect`，也不再在打开/关闭时做 widget 快照缩放动画。这样从根上避开 Wayland/Mutter 对可见 resize、hide/show remap、旧 buffer 重显的处理差异。
- 代码清理：移除 QR 弹窗旧飞行动画相关状态和方法，包括 start rect、动画 pixmap、`contentRect` 属性、快照捕获、`_start_dialog_animation()` 与 `_finish_open_animation()`；保留 `QRSuccessOverlay` 的扫码成功对勾动画。
- 焦点边界：打开后短暂设置 `_ignore_focus_loss`，120ms 后通过 generation 校验解除，避免 Wayland show/activate 过程中的 focus-out 把刚出现的弹窗关闭；若弹窗已关闭或新一轮打开，旧 timer 不会影响当前状态。
- 验证：`py_compile`、`unittest discover -s pc/tests`（72 OK）、`git diff --check` 均通过。视觉闪动仍需用户在真实 GNOME Wayland 会话中手动确认。

## 2026-06-19 整体前端逻辑 Review

- **Android native WebSocket 发送失败不可被上层捕获**：`VoicingWebSocketSink.add()` 接口是 `void`，native 实现 `_NativeWifiWebSocketSink.add()` 内部 `unawaited(_idFuture.then(... MethodChannel.invokeMethod('sendWebSocketMessage') ...))`。Kotlin `sendWebSocketMessage` 在未连接时会 `result.error("not_connected", ...)`，`webSocket.send(message)` 也可能返回 `false`；但 Dart 上层 `sendText()`、`_sendPing()`、`_sendShadowIncrement()`、commit 发送周围的 `try/catch` 都只包住同步调用，捕不到这些异步失败。结果是 UI/controller 可能记录已发送、清空输入或继续保持连接状态，但 native 实际未发出消息。
- **PC 同步开关即时广播有跨 event loop 风险**：`ModernMenuWidget.toggle_sync()` 开新线程和新 asyncio loop 调 `broadcast_sync_state()`，而 `state.connected_clients` 里的 websockets 连接对象由 server 线程/loop 创建。对这些对象在另一个 loop 调 `client.send()` 在 websockets 12 下不是可靠模型，可能抛异常后被静默吞掉，导致手机端不会立即收到 `sync_state`。不过 PC 端处理文本时仍会返回 `sync_disabled`，心跳 pong 也会带 `sync_enabled`，所以这是即时状态同步风险，不是核心输入路径完全失效。
- **Android QR 替换设备确认的时序语义不严谨**：`_finishQrPairing()` 在连通性 probe 成功后先设置 `_qrPairingSucceeded=true` 并展示成功态，再等待 `_qrSuccessHoldDelay` 后调用 `_confirmScannedServer()`。若扫到不同 `device_id` 且用户取消替换，会出现“先成功、再取消”的体验。数据不会被保存，属于 UX/状态语义问题；更严谨的流程是先确认替换，再展示最终成功态。
- **菜单宽度/居中检查结论**：Linux 当前走原生 `QMenu`，实际宽度约 110px；`QMenu::item { text-align: center; }` 不改变实际文字绘制位置。真正居中需要 `QWidgetAction` 或自绘项，会牺牲当前 Linux 托盘宿主兼容性，用户已决定暂不改。
- **验证状态**：PC 72 个单元测试通过；Android 22 个 Flutter tests 通过；Flutter analyze 仅报告既有 4 个 `withOpacity` info。当前 review 没有发现协议字段不一致或 QR-only reconnect 模型被破坏。

## 2026-06-19 整体前端 Review 问题修复决策

- **Android WebSocket 发送语义**：`VoicingWebSocketSink.add()` 改为 `Future<void>` 是必要的接口变化。原因是 native MethodChannel 发送本来就是异步边界，保持 `void` 会让 controller 的 `try/catch` 形成虚假保护，导致 UI 认为发送成功但 native 实际失败。Dart IO sink 虽然底层 `WebSocketSink.add()` 仍是同步 API，也用 `async` 包成同一接口，保持上层发送路径一致。
- **发送后状态更新顺序**：`sendText()`、shadow increment、commit auto-enter 必须在 `await sink.add()` 成功后再记录历史、推进 `_lastSentLength` 或清空输入。发送失败时保留输入并断开/重连，比“清空但未到达 PC”更符合用户可恢复性。
- **PC 同步广播 event loop**：`websockets` 连接对象由 server loop 创建，托盘 UI 线程切换同步状态时应使用 `asyncio.run_coroutine_threadsafe()` 投递回 `state.server_loop`。新建 event loop 后直接 `client.send()` 属于跨 loop 操作，不能作为即时状态同步实现。
- **QR 替换确认时序**：扫码 probe 成功不等于用户已接受替换已保存设备。对不同 `device_id` 的替换，应先确认，再展示最终成功态和保存重连；取消时应直接退出扫码锁定态，不展示“成功后取消”的矛盾状态。
- **验证边界**：本轮只做源码与单元/静态验证，按用户要求未编译 APK 或 deb。

## 2026-06-19 Linux terminal 输入失效调查

- **根因判断**：当前 GNOME Wayland portal 后端固定发送 `Ctrl+V`（`KEYSYM_CTRL_L + KEYSYM_V`）。普通 GTK/浏览器输入框会把 `Ctrl+V` 解释为粘贴；GNOME Terminal 默认粘贴快捷键是 `Ctrl+Shift+V`，所以终端里不触发粘贴。这与用户现象“普通输入框生效，terminal 不生效”一致。
- **本机证据**：`/usr/share/glib-2.0/schemas/org.gnome.Terminal.gschema.xml` 中 `org.gnome.Terminal.Legacy.Keybindings paste` 默认值为 `<Control><Shift>v`；`gsettings list-recursively` 也显示 `org.gnome.Terminal.Legacy.Keybindings paste '<Control><Shift>v'`。
- **联网证据**：GNOME Terminal 官方帮助页 `help.gnome.org/gnome-terminal/adv-keyboard-shortcuts.html` 记录 Edit/Paste 默认是 `Shift + Ctrl + V`；XDG RemoteDesktop portal 官方文档说明 `NotifyKeyboardKeysym` 只是发送键盘事件，不提供“粘贴文本到焦点应用”的高级 API。
- **窗口识别限制**：尝试调用 GNOME Shell `org.gnome.Shell.Introspect.GetWindows` / `GetRunningApplications` 返回 `AccessDenied: GetWindows is not allowed`。联网结果也说明普通进程不能直接访问该私有窗口 introspection，除非 unsafe mode/扩展/patch。因此不能把“自动检测当前焦点是不是 terminal”作为默认产品方案。
- **AT-SPI 探测**：本机 `gi.repository.Atspi` 可用，能列出应用并看到 `ghostty`，但当前焦点状态可能落在 `gnome-shell` window，不能作为无需授权且稳定的 terminal 检测依据。它可以作为后续增强/heuristic，但不应作为唯一修复。
- **wl-clipboard 探测**：`wl-copy --primary` 与 `wl-paste --primary` 在本机可用。`Shift+Insert` 在 Linux/终端生态中常用于粘贴 PRIMARY 或 CLIPBOARD，行为跨应用不完全一致；如果同时写 CLIPBOARD 和 PRIMARY，可作为 terminal 兼容 fallback，但相比直接按 terminal 配置发送 `Ctrl+Shift+V` 更像广义兼容策略。
- **推荐修复路径**：第一版优先在 Linux Wayland portal 后端增加“terminal 粘贴快捷键”能力：默认仍保留普通 `Ctrl+V`，但提供可切换策略或 heuristic；若要立即解决用户当前 terminal，最小改动是把 Wayland portal 粘贴序列改为 `Ctrl+Shift+V` 或增加一个 terminal 模式。更稳的产品化方案是：写剪贴板时同时写 CLIPBOARD/PRIMARY，然后在 portal 后端支持三种 paste strategy：`ctrl-v`、`ctrl-shift-v`、`shift-insert`，由配置/菜单/环境变量选择，后续再加 AT-SPI heuristic 自动选择。

## 2026-06-19 GNOME Wayland Terminal 粘贴模式实现发现

- **实现选择**：默认使用 Auto 模式，不强行把所有 Wayland 粘贴改成 `Ctrl+Shift+V`。理由：普通输入框仍以 `Ctrl+V` 最稳；只有检测到 terminal 时才切到 `Ctrl+Shift+V`。
- **手动兜底**：Auto 检测不是 100% 稳定，因此托盘新增可见“粘贴模式”项：自动粘贴 / 普通粘贴 / 终端粘贴 / 兼容粘贴。用户可在 Auto 未识别 terminal 时手动切到终端模式。
- **AT-SPI 运行环境**：项目 venv 缺少 `gi`，但系统 `/usr/bin/python3` 有 `gi.repository.Atspi`。检测器先尝试当前进程，失败后以 `/usr/bin/python3 -c` 执行只读查询；若失败或超时，回退普通 `Ctrl+V`。
- **焦点兜底**：GNOME Wayland 上当前 `FOCUSED` accessible 有时落到 `gnome-shell` window。实现中若 focused 对象不是 terminal，会继续扫描 `ACTIVE` 且 app/role 命中 terminal 的窗口，提升 Ghostty/GNOME terminal 等实际窗口识别概率。
- **PRIMARY 处理**：为了支持 `Shift+Insert` 兼容模式，Wayland 下会同时写 CLIPBOARD 和 PRIMARY。写入前尝试读取旧 PRIMARY，粘贴后尽量恢复；若读取失败则不恢复，避免阻断主粘贴路径。
- **实测结果**：用户在当前 Linux/GNOME Wayland 环境手动启动测试后确认，普通输入框和 terminal 均可自动输入；AT-SPI Auto 检测 + terminal `Ctrl+Shift+V` 路径在该环境下有效。

## 2026-06-19 最新 PC / Android 逻辑复查发现

- **PC 输入失败恢复**：`type_text_at_cursor()` 原先在剪贴板写入新文本后，如果 `paste_from_clipboard()` 或 `press_enter()` 抛异常，会跳过旧剪贴板/PRIMARY 恢复。修复为 `finally` 恢复，避免失败后污染用户剪贴板。
- **PC ACK 清空语义**：`handle_client()` 原先不区分 `type_text()` 是否真正注入成功，submit 文本失败后仍可能返回 `clear_input=true`。修复为 `type_text()` 返回 bool，只有成功注入时才让 Android 清空输入，失败时保留手机端文本便于重发。
- **Android native close 语义**：`_NativeWifiWebSocketSink.close()` 原先等待 `_idFuture`；如果 native 连接还没返回 id 或已经失败，重连/释放路径可能留下未处理 Future 错误。修复为 best-effort close，id 不可用时静默完成。

## 2026-06-19 v2.9.5 Release workflow 失败根因

- `v2.9.5` tag 已触发 release workflow，旧 run `27815558477` 中 Android APK、Windows EXE、macOS DMG 均构建成功，但 Linux job 在 `Run desktop validation` 阶段失败，导致最终 `Publish GitHub Release` 被跳过。
- Linux 失败根因不是打包脚本或 DEB 逻辑，而是 `python -m unittest discover -s tests` 在 GitHub `ubuntu-22.04` headless runner 中创建 `QApplication` 时尝试加载 Qt `xcb` 平台插件，因无图形会话 abort：`Could not load the Qt platform plugin "xcb"`。
- 修复决策：Linux release job 显式设置 `QT_QPA_PLATFORM=offscreen`，并在 `pc/tests/test_voice_coding_tray.py` 导入 PyQt 前设置同样默认值。该改动仅影响 CI/headless 测试环境，不改变用户机器上发布应用的运行平台选择。
- 发布策略：GitHub 上尚未创建 `v2.9.5` release，因此可把失败构建用过的 `v2.9.5` tag 移到修复提交后重新触发同版本 release workflow，避免为 CI 环境变量修复单独升版本。
- 最终结果：新 run `27815951469` 全部成功，GitHub Release `v2.9.5` 已发布，包含 Android APK、Linux DEB、Linux standalone binary、Windows EXE、macOS DMG 和 SHA256 校验文件。

## 2026-06-19 v2.9.5 Linux deb 运行时误报 portal 不可用

- 用户安装 `v2.9.5` 的 `voicing-linux-amd64.deb` 后，在 GNOME Wayland 启动时弹出“没有可用的 RemoteDesktop portal 键盘能力”。同一系统中 `/usr/bin/gdbus ... AvailableDeviceTypes` 返回 `(<uint32 7>,)`，portal 服务也在运行，说明 portal 本身正常。
- 本机复现 `/opt/voicing/voicing --dev`：打包版误报 portal 不可用；源码版和系统 `gdbus` 检测正常。根因是 PyInstaller frozen app 会把自身解包目录注入 `LD_LIBRARY_PATH`，外部系统命令 `gdbus` 被迫加载打包应用自带/不匹配的动态库后失败，而错误被 `has_remote_desktop_keyboard_portal()` 捕获为 false。
- 修复决策：新增 `system_subprocess_env()`，调用系统命令时恢复 `LD_LIBRARY_PATH_ORIG`，无原始值时在 frozen app 中移除 `LD_LIBRARY_PATH`。该环境清理用于 `gdbus` portal 探测、`wl-copy` / `wl-paste` Wayland 剪贴板，以及系统 Python AT-SPI helper，避免打包态后续输入路径继续受同一问题影响。
- 本机已用 `sudo -n apt-get remove -y voicing` 卸载错误的 `voicing 2.9.5` deb；未清理用户数据 `~/.local/share/Voicing`。
- 本地 frozen smoke test 结果：临时 PyInstaller 二进制在 GNOME Wayland 上能进入 WebSocket 监听阶段，不再失败于 portal 能力检查；`QT_QPA_PLATFORM=offscreen` 下的系统托盘不可用错误是无界面测试环境预期结果。
