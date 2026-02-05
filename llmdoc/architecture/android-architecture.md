# Android 端架构

## 1. Identity

- **What it is**: 基于 Flutter 的移动端应用，作为语音输入客户端与 PC 端通信。
- **Purpose**: 通过 WebSocket 接收用户的语音/文本输入并实时同步到 PC 端，支持 UDP 自动发现 PC 服务器。

## 2. Core Components

- `android/voice_coding/lib/main.dart` (VoiceCodingApp, MainPage, _MainPageState): Flutter 应用入口和主页面状态管理，包含所有核心逻辑。
- `android/voice_coding/lib/main.dart` (_connect): WebSocket 连接方法，连接到 PC 端服务器。
- `android/voice_coding/lib/main.dart` (_handleMessage): WebSocket 消息处理，处理 connected/ack/sync_state/pong 消息类型。
- `android/voice_coding/lib/main.dart` (_startUdpDiscovery, _handleUdpDiscovery): UDP 监听服务，自动发现局域网内的 PC 服务器。
- `android/voice_coding/lib/main.dart` (_sendText, _sendShadowIncrement): 文本发送逻辑，包括普通发送和自动发送增量模式。
- `android/voice_coding/lib/main.dart` (_onTextControllerChanged): 监听文本输入变化，检测 composing 状态实现自动发送。
- `android/voice_coding/lib/main.dart` (_buildDropdownMenuOverlay, _buildMenuItem): 下拉菜单 UI 组件。
- `android/voice_coding/lib/main.dart` (_buildInputArea): 文本输入框组件。
- `android/voice_coding/pubspec.yaml`: Flutter 依赖配置（web_socket_channel, shared_preferences）。
- `android/voice_coding/android/app/src/main/AndroidManifest.xml`: Android 权限配置（INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE）。

## 3. Execution Flow (LLM Retrieval Map)

### 应用启动流程

1. **入口**: `main()` 函数调用 `runApp(VoiceCodingApp())` 启动应用 (`main.dart:9-11`)。
2. **主题配置**: `VoiceCodingApp.build()` 配置 Material 3 深色主题 (`main.dart:16-54`)。
3. **状态初始化**: `_MainPageState.initState()` 执行初始化 (`main.dart:90-120`)：
   - 初始化菜单动画控制器
   - 添加文本控制器监听器
   - 加载 SharedPreferences（自动发送开关状态）
   - 启动 UDP 发现监听
   - 开始 WebSocket 连接

### UDP 自动发现流程

1. **启动监听**: `_startUdpDiscovery()` 绑定 UDP 端口 9530 (`main.dart:231-252`)。
2. **接收广播**: `_udpSocket.listen()` 监听 `RawSocketEvent.read` 事件 (`main.dart:239-247`)。
3. **解析消息**: `_handleUdpDiscovery()` 解析 `voice_coding_server` 类型的 JSON (`main.dart:255-282`)。
4. **更新配置**: 提取 IP 和 Port，更新 `_serverIp` 和 `_serverPort` (`main.dart:264-269`)。
5. **触发连接**: 如果未连接，调用 `_connect()` 立即连接 (`main.dart:272-275`)。

### WebSocket 连接流程

1. **发起连接**: `_connect()` 使用 `WebSocketChannel.connect()` 连接到 `ws://_serverIp:_serverPort` (`main.dart:161-188`)。
2. **监听消息**: `_channel.stream.listen()` 处理 incoming 消息 (`main.dart:172-183`)。
3. **处理 connected**: 收到 `type='connected'` 时更新状态和同步开关 (`main.dart:195-200`)。
4. **处理 ack**: 收到 `type='ack'` 时清空输入框 (`main.dart:201-202`)。
5. **处理 sync_state/pong**: 更新同步状态 `_syncEnabled` (`main.dart:203-206`)。
6. **断线重连**: `_handleDisconnect()` 设置 3 秒后自动重连 (`main.dart:220-227`)。

### 文本发送流程

1. **普通发送**: 用户按回车键触发 `_sendText()` (`main.dart:284-302`)：
   - 检查连接状态和同步开关
   - 发送 JSON: `{"type": "text", "content": text}`
   - 保存文本到 `_lastSentText` 用于撤回
   - 重置 `_lastSentLength`

2. **自动发送 (Shadow Mode)**: `_onTextControllerChanged()` 监听输入变化 (`main.dart:305-329`)：
   - 检测 `composing` 状态（组合文本/输入法下划线）
   - 从"有组合文本"变成"无组合文本"时触发增量发送
   - `_sendShadowIncrement()` 只发送新增部分 (`main.dart:332-352`)

### 应用生命周期处理

1. **前台恢复**: `didChangeAppLifecycleState(resumed)` 取消待处理的重连并立即连接 (`main.dart:152-159`)。

## 4. Design Rationale

**状态管理**: 使用 `setState()` 进行局部状态更新，无需外部状态管理库（如 Provider/Riverpod），保持项目轻量。

**自动发送核心原理**: 利用 Flutter 的 `TextEditingController.value.composing` 检测输入法完成状态。`composing.isValid && !composing.isCollapsed` 表示输入法正在输入（下划线状态），从"有组合文本"变成"无组合文本"时表示输入完成，此时发送增量文本。

**消息格式**: 统一使用 JSON，`type` 字段区分消息类型（text/connected/ack/sync_state/ping/pong）。

**网络权限**: Android 端需要 INTERNET/ACCESS_NETWORK_STATE/ACCESS_WIFI_STATE 权限，已在 AndroidManifest.xml 中配置。

**UI 框架**: Material 3 + 自定义动画，无第三方 UI 库依赖，保持最小依赖。
