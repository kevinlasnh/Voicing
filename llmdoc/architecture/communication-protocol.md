# 通信协议架构

## 1. Identity

- **What it is**: PC 端与 Android 端之间的双层网络通信协议
- **Purpose**: 实现设备自动发现、实时数据传输和状态同步

## 2. Core Components

- `pc/voice_coding.py:82-148` (WS_PORT, UDP_BROADCAST_PORT, get_hotspot_ip): 网络配置常量和 IP 检测逻辑
- `pc/voice_coding.py:210-251` (start_udp_broadcast): UDP 广播服务，每 2 秒发送服务器信息
- `pc/voice_coding.py:345-414` (handle_client): WebSocket 服务器处理客户端连接和消息
- `pc/voice_coding.py:417-431` (broadcast_sync_state): 同步状态广播到所有客户端
- `android/voice_coding/lib/main.dart:161-188` (_connect): WebSocket 客户端连接逻辑
- `android/voice_coding/lib/main.dart:190-211` (_handleMessage): 服务端消息处理
- `android/voice_coding/lib/main.dart:229-252` (_startUdpDiscovery): UDP 发现监听服务
- `android/voice_coding/lib/main.dart:254-270` (_handleUdpDiscovery): UDP 广播消息解析

## 3. Execution Flow (LLM Retrieval Map)

### UDP 发现流程 (端口 9530)

1. **PC 端启动**: `pc/voice_coding.py:1102-1104` 启动 UDP 广播线程
2. **广播发送**: `pc/voice_coding.py:222-227` 每 2 秒发送 JSON 到 `<broadcast>:9530`
3. **Android 监听**: `main.dart:233-252` 绑定 `0.0.0.0:9530` 接收广播
4. **解析更新**: `main.dart:255-270` 解析 JSON，更新 `_serverIp` 和 `_serverPort`

### WebSocket 连接流程 (端口 9527)

1. **Android 发起连接**: `main.dart:168-170` 连接到 `ws://$_serverIp:9527`
2. **PC 接受连接**: `pc/voice_coding.py:437-444` WebSocket 服务器接受连接
3. **发送欢迎消息**: `pc/voice_coding.py:351-356` 发送 `connected` 消息
4. **Android 更新状态**: `main.dart:195-200` 更新连接状态和同步开关

### 文本传输流程

1. **Android 发送**: `main.dart:284-302` 发送 `{"type": "text", "content": "..."}`
2. **PC 接收处理**: `pc/voice_coding.py:372-385` 检查同步状态，调用 `type_text()`
3. **PC 确认**: `pc/voice_coding.py:387-390` 发送 `ack` 消息
4. **Android 清空**: `main.dart:201-202` 收到 `ack` 后清空文本框

### 心跳保活流程

1. **Android 发送 ping**: 通过定时器发送 `{"type": "ping"}`
2. **PC 响应 pong**: `pc/voice_coding.py:397-400` 返回 `{"type": "pong", "sync_enabled": bool}`
3. **状态同步**: `main.dart:203-206` 更新本地同步状态

### 状态同步流程

1. **PC 用户切换**: 通过托盘菜单切换"同步输入"
2. **广播状态**: `pc/voice_coding.py:417-431` 向所有客户端发送 `sync_state`
3. **Android 更新**: `main.dart:203-206` 更新 UI 显示

## 4. Design Rationale

- **双层设计**: UDP 用于发现（无状态），WebSocket 用于传输（有状态），分离关注点
- **单向广播**: PC 端主动广播，Android 端被动监听，简化设备发现逻辑
- **JSON 统一格式**: 所有消息使用 JSON，易于扩展和调试
- **心跳合并状态**: pong 消息携带 `sync_enabled`，减少消息数量
