# 连接工作流程指南

本文档描述 Android 端与 PC 端建立连接的完整流程。

## 典型连接流程

1. **PC 端启动**: PC 端启动后自动开启 WebSocket 服务器 (9527) 和 UDP 广播 (9530)
2. **Android 启动**: Android 端启动 UDP 监听服务，同时尝试连接默认 IP
3. **自动发现**: Android 收到 UDP 广播后，更新服务器地址并重新连接
4. **连接建立**: WebSocket 连接成功，PC 发送欢迎消息，Android 更新 UI 状态

## 自动发现工作原理

PC 端每 2 秒通过 UDP 广播以下消息：

```json
{"type": "voice_coding_server", "ip": "192.168.137.1", "port": 9527, "name": "主机名"}
```

Android 端监听 `0.0.0.0:9530`，收到广播后：
- 更新 `_serverIp` 和 `_serverPort`
- 如果当前未连接，立即触发 `_connect()`

相关代码: `pc/voice_coding.py:210-251`, `android/voice_coding/lib/main.dart:229-270`

## 断线重连机制

Android 端断线处理流程：
1. 触发 `onError` 或 `onDone` 回调
2. 调用 `_handleDisconnect()` 更新状态为 `disconnected`
3. 启动 3 秒倒计时定时器
4. 3 秒后自动调用 `_connect()` 重新连接

应用恢复前台时立即重连（取消待定重连）。

相关代码: `android/voice_coding/lib/main.dart:213-227`

## 心跳保活机制

心跳机制用于保持连接活跃并同步 PC 端同步开关状态：

- **Android → PC**: 定期发送 `{"type": "ping"}`
- **PC → Android**: 响应 `{"type": "pong", "sync_enabled": true}`

收到 `pong` 后，Android 端更新本地 `_syncEnabled` 状态。

相关代码: `pc/voice_coding.py:397-400`, `android/voice_coding/lib/main.dart:203-206`

## 验证连接状态

连接成功的标志：
- Android 端顶部状态栏显示绿色 "已连接"
- PC 端托盘图标显示为 "连接" 状态
- Android 端输入文字后能自动发送到 PC

相关代码: `android/voice_coding/lib/main.dart:195-200`
