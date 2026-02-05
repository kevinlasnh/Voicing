# PC 端架构

## 1. Identity

- **What it is:** Python 系统托盘应用，接收手机端文本并在光标位置输入。
- **Purpose:** 作为 WebSocket 服务器接收来自 Android 客户端的文本输入请求，通过剪贴板方式模拟键盘输入。

## 2. Core Components

- `pc/voice_coding.py:96-109` (AppState): 全局状态管理类，管理同步开关、运行状态、WebSocket 服务器实例、托盘图标实例、连接客户端集合、图标闪烁状态。
- `pc/voice_coding.py:457-563` (MenuItemWidget): PyQt5 菜单项组件，实现 Windows 11 Fluent Design 风格，使用 paintEvent 手动绘制悬停高亮效果。
- `pc/voice_coding.py:565-740` (ModernMenuWidget): PyQt5 自定义菜单窗口，FramelessWindowHint + 半透明背景，滑入动画，包含四个菜单项。
- `pc/voice_coding.py:742-851` (ModernTrayIcon): PyQt5 系统托盘图标，预缓存三种状态图标（normal/dim/paused），只响应右键菜单。
- `pc/voice_coding.py:345-415` (handle_client): WebSocket 客户端连接处理，接收 JSON 消息，发送连接确认、响应、同步状态。
- `pc/voice_coding.py:210-252` (start_udp_broadcast): UDP 广播服务，每 2 秒广播服务器信息供客户端发现。
- `pc/voice_coding.py:301-335` (type_text): 文本输入函数，使用剪贴板方式实现 Unicode 支持。
- `pc/voice_coding.py:115-139` (setup_logging): 日志系统配置，日志文件保存在 `%APPDATA%\Voicing\logs\`。

## 3. Execution Flow (LLM Retrieval Map)

### 应用启动流程

- **1. 初始化:** `main()` 调用 `setup_logging()` 初始化日志系统 (`pc/voice_coding.py:1092`)。
- **2. IP 检测:** `get_hotspot_ip()` 检测 Windows 移动热点实际 IP 地址 (`pc/voice_coding.py:1095`)。
- **3. WebSocket 启动:** 创建守护线程运行 `run_server()`，监听 0.0.0.0:9527 (`pc/voice_coding.py:1099-1100`)。
- **4. UDP 广播启动:** 创建守护线程运行 `start_udp_broadcast()`，每 2 秒广播一次 (`pc/voice_coding.py:1103-1104`)。
- **5. 托盘启动:** `run_tray()` 在主线程中创建 PyQt5 托盘应用 (`pc/voice_coding.py:1107`)。

### WebSocket 请求处理流程

- **1. 连接建立:** 新连接到达 `handle_client()` (`pc/voice_coding.py:345`)。
- **2. 状态更新:** 客户端加入 `state.connected_clients` 集合，调用 `update_tray_icon()` 更新图标 (`pc/voice_coding.py:348-356`)。
- **3. 欢迎消息:** 发送 `{"type": "connected", "sync_enabled": ..., "computer_name": ...}` (`pc/voice_coding.py:363-368`)。
- **4. 消息循环:** async for 循环接收客户端消息 (`pc/voice_coding.py:370-405`)。
- **5. 文本处理:** 收到 `{"type": "text", "content": "..."}` 后，检查 `state.sync_enabled`，调用 `type_text()` 执行输入 (`pc/voice_coding.py:375-392`)。
- **6. 连接断开:** 客户端从集合移除，更新托盘图标 (`pc/voice_coding.py:409-414`)。

### 文本输入流程

- **1. 状态检查:** `type_text()` 检查 `state.sync_enabled`，禁用时直接返回 (`pc/voice_coding.py:308-309`)。
- **2. 保存剪贴板:** 使用 `pyperclip.paste()` 保存当前剪贴板内容 (`pc/voice_coding.py:317-319`)。
- **3. 复制新文本:** `pyperclip.copy(text)` 将新文本复制到剪贴板 (`pc/voice_coding.py:322`)。
- **4. 模拟粘贴:** `pyautogui.hotkey('ctrl', 'v')` 发送 Ctrl+V (`pc/voice_coding.py:323`)。
- **5. 恢复剪贴板:** 等待 0.1 秒后恢复原剪贴板内容 (`pc/voice_coding.py:326-331`)。

### 托盘图标更新流程

- **1. 定时触发:** QTimer 每 200ms 调用 `update_tray_icon_pyqt()` (`pc/voice_coding.py:1043-1045`)。
- **2. 状态判断:** 根据 `state.sync_enabled` 和 `state.connected_clients` 判断当前状态 (`pc/voice_coding.py:1054-1060`)。
- **3. 图标选择:** 从 `_icon_cache` 获取预缓存的图标（normal/dim/paused）(`pc/voice_coding.py:842-850`)。

## 4. Design Rationale

### 多线程架构
- WebSocket 服务器和 UDP 广播在独立守护线程中运行，避免阻塞 PyQt5 主线程。
- 每个网络服务使用独立的 `asyncio.new_event_loop()`，避免事件循环冲突。

### 剪贴板输入方式
- 使用剪贴板而非 `pyautogui.write()` 确保中文等 Unicode 字符正确输入。
- 缺点是会覆盖用户剪贴板内容，但会尝试恢复。

### 图标预缓存
- 三种状态图标在启动时生成并缓存，避免每次切换时重新处理图像。
- 256px 高清源图标确保在高 DPI 屏幕上清晰显示。

### PyQt5 悬停高亮解决方案
- PyQt5 自定义 QWidget 不支持 CSS `:hover` 伪状态。
- 使用 `paintEvent` 手动绘制背景，子控件设置 `WA_TransparentForMouseEvents` 穿透鼠标事件。
- 通过 `enterEvent/leaveEvent` 追踪悬停状态。
