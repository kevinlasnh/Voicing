# Voicing 项目概览

## 1. 项目简介

Voicing 是一款跨平台语音输入工具，让用户通过手机语音输入，文字实时出现在电脑光标位置。主要解决了与 AI 对话时打字速度慢、思路被打断的问题。

**核心价值**：利用手机高准确率的语音识别引擎（讯飞、搜狗、百度），在任意电脑应用中实现语音输入。

## 2. 技术栈

### PC 端
- **语言**: Python 3.14
- **UI 框架**: PyQt5 (系统托盘 + 右键菜单)
- **网络**: websockets (WebSocket 服务器), socket (UDP 广播)
- **输入模拟**: pyautogui + pyperclip (剪贴板方式实现 Unicode 支持)
- **打包**: PyInstaller (单文件 EXE)

### Android 端
- **语言**: Dart
- **框架**: Flutter 3.27.0 (Material 3 深色主题)
- **网络**: web_socket_channel (WebSocket 客户端), RawDatagramSocket (UDP 监听)
- **持久化**: shared_preferences
- **包名**: com.voicecoding.app

### 通信协议
- **WebSocket (TCP 9527)**: 双向实时数据传输
- **UDP (9530)**: PC 端广播服务发现

## 3. 架构概览

### 双端架构
```
+-------------------+           +-------------------+
|   PC 端           |           |   Android 端      |
|   (Python)        |           |   (Flutter)       |
+-------------------+           +-------------------+
| WebSocket Server  |<--------->| WebSocket Client  |
| Port: 9527        |   JSON    | ws://IP:9527      |
+-------------------+           +-------------------+
| UDP Broadcast     |~+         | UDP Listener      |
| Port: 9530        | |         | Port: 9530        |
+-------------------+ |         +-------------------+
        |               |                  |
        v               v                  v
   局域网广播 (每 2 秒)      自动发现并连接
```

### 通信方式
1. **服务发现**: PC 端每 2 秒通过 UDP 广播服务器信息 (IP、端口、主机名)
2. **数据传输**: Android 端通过 WebSocket 连接 PC 端，发送文本内容
3. **输入模拟**: PC 端接收文本后，通过剪贴板方式模拟键盘输入

## 4. 核心功能

### 自动发现
- PC 端启动 UDP 广播服务 (端口 9530)
- Android 端监听广播，自动获取 PC 端 IP 地址
- 无需手动配置 IP，即开即用

### 实时传输
- WebSocket 长连接保持通信
- 支持心跳保活 (ping/pong)
- 自动断线重连 (3 秒延迟)

### 自动发送
- 监听输入法 composing 状态（带下划线的组合文本）
- 输入法完成输入后自动发送增量文本
- 实现语音输入实时同步

### 撤回功能
- 保存最后一次发送的文本
- 可通过手机端菜单恢复到输入框

### PC 端托盘功能
- 同步输入开关
- 开机自启设置
- 打开日志文件
- 退出应用

## 5. 项目结构

```
Voicing/
├── pc/                           # PC 端源码
│   ├── voice_coding.py           # 主程序 (单一文件架构)
│   ├── requirements.txt          # Python 依赖
│   ├── assets/
│   │   ├── icon_1024.png         # 托盘图标源文件
│   │   └── icon.ico              # EXE 文件图标
│   └── dist/                     # 打包输出目录
├── android/voice_coding/         # Android 端源码
│   ├── lib/
│   │   └── main.dart             # Flutter 主程序
│   ├── android/
│   │   └── app/
│   │       └── src/main/
│   │           ├── AndroidManifest.xml
│   │           └── res/          # 资源文件 (图标、颜色等)
│   ├── assets/icons/             # 应用图标源文件
│   └── pubspec.yaml              # Flutter 依赖配置
├── .github/workflows/
│   └── release.yml               # CI/CD 自动发布
├── CHANGELOG.md                  # 更新日志
├── CLAUDE.md                     # 开发规范
└── README.md                     # 用户文档
```

## 6. 系统要求

### 开发环境
- **Python**: 3.14+
- **Flutter**: 3.27.0+
- **Java**: 17 或 21 (Flutter 构建)
- **操作系统**: Windows 10/11 (64位)

### 运行环境
- **PC 端**: Windows 10/11 (64位)，无需安装运行时
- **Android 端**: Android 5.0+ (API 21+)
- **网络**: PC 和手机需在同一移动热点下

## 7. 关键设计决策

- **单文件架构**: PC 端使用单一 Python 文件，简化部署和打包
- **剪贴板输入**: 使用剪贴板方式实现 Unicode 支持，兼容所有语言
- **双层发现**: UDP 广播 + WebSocket 传输，分离服务发现和数据传输
- **状态同步**: PC 端同步开关状态实时广播到所有 Android 客户端
- **图标预缓存**: PC 端启动时预生成三种状态图标，确保闪烁效果均匀

## 相关文档
- `/llmdoc/architecture/pc-architecture.md` - PC 端详细架构
- `/llmdoc/architecture/android-architecture.md` - Android 端详细架构
- `/llmdoc/architecture/communication-protocol.md` - 通信协议规范
- `/llmdoc/reference/build-deployment.md` - 构建部署指南
