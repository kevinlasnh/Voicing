<div align="center">

<img src="android/voice_coding/assets/icons/icon_1024.png" width="120" alt="Voicing" style="border-radius: 50%;">

# Voicing

**手机语音输入，直接打到电脑上**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/kevinlasnh/Voicing)](https://github.com/kevinlasnh/Voicing/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android-blueviolet)](#)
[![Version](https://img.shields.io/badge/version-2.7.0-green)](#)

和 AI 对话时打字太慢？Voicing 让你用嘴代替手

</div>

---

> **说明**：macOS 和 Linux 桌面端目前仍处于内测阶段，正在持续测试中，稳定性暂时无法保证。

## 它能做什么

Voicing 把手机的语音输入法变成电脑的"嘴"——你在手机上说话，文字直接出现在电脑光标处

- **零配置连接** — 手机连电脑热点，打开 App，自动连接
- **语音自动发送** — 说完话文字自动打过去，不需要手动操作
- **自动 Enter** — 可选开关，文本稳定落定后统一按一次回车
- **手动发送也行** — 按回车手动发送，适合需要编辑的场景
- **撤回支持** — 发错了？一键撤回上次输入
- **断线自动恢复** — 手机息屏再亮屏，优先保持已连接显示并快速恢复
- **跨平台** — 支持 Windows / macOS / Linux 桌面端，Android 手机端
- **体积小巧** — APK 21MB，桌面端 50MB 左右，无运行时依赖

## 快速开始

### 1. 下载

从 [Releases](https://github.com/kevinlasnh/Voicing/releases/latest) 下载对应平台文件：

| 平台 | 文件 | 要求 |
|------|------|------|
| Windows | `voicing-windows-x64.exe` | Win 10/11 (64-bit) |
| macOS | `voicing-macos-arm64.dmg` | Apple Silicon (M1+) |
| Linux | `voicing-linux-x86_64` | Ubuntu 22.04+ GNOME X11 |
| Android | `voicing.apk` | Android 5.0+ |

### 2. 连接

```
电脑运行桌面端程序 → 开启热点 / 互联网共享 / 同一局域网 → 手机连接网络 → 打开 voicing App
```

- **Windows**：运行 `voicing-windows-x64.exe`，开启"移动热点"
- **macOS**：打开 `voicing-macos-arm64.dmg`，拖入 Applications（首次打开需右键→打开），开启"互联网共享"或连接同一局域网
- **Linux**：`chmod +x voicing-linux-x86_64` 后运行，开启 Wi-Fi 热点或连接同一局域网

状态栏显示"已连接"就说明连上了

### 3. 使用

1. 电脑上把光标点到要输入的位置
2. 手机上切换到语音输入法，开始说话
3. 文字自动出现在电脑上

> **推荐搭配**：[豆包输入法](https://shurufa.doubao.com/) + [大疆 Mic Mini](https://www.dji.com/cn/mic-mini) + [DJI Mic 系列手机接收器](https://store.dji.com/cn/product/dji-mic-series-mobile-receiver?vid=200571) —— 语音识别准确，领夹麦克风直连手机，体验最佳

## 功能一览

### 手机端

- 语音输入完成后自动发送到电脑
- 按回车手动发送
- "自动 Enter"开关：语音分段输入时只在静默后统一按一次回车（默认关闭）
- "撤回上次输入"恢复刚才的文本
- "刷新连接"手动重连

### 电脑端

托盘图标菜单（Windows 右键 / macOS+Linux 左键）：

| 菜单项 | 功能 |
|--------|------|
| 同步输入 | 开关是否接收手机文字 |
| 开机自启 | 注册表方式，开机自动启动 |
| 打开日志 | 用记事本打开当天日志 |
| 退出应用 | 关闭程序 |

托盘图标状态：
- 闪烁 = 等待手机连接
- 常亮 = 已连接
- 灰色 = 同步已关闭

## 工作原理

1. 桌面端通过 UDP 广播（端口 9530）宣告自己的存在
2. 手机监听广播，发现桌面端后通过 WebSocket（端口 9527）建立连接
3. 手机上的文字（语音输入或手动输入）实时发送到桌面端
4. 桌面端通过剪贴板粘贴文本（Windows Ctrl+V / macOS Cmd+V / Linux Ctrl+V），并在需要时补发一次 Enter

## 开发

### 环境准备

```bash
git clone https://github.com/kevinlasnh/Voicing.git
cd Voicing

# 桌面端（Windows / macOS / Linux）
cd pc
pip install -r requirements.txt
python voice_coding.py --dev

# Android 端
cd android/voice_coding
flutter pub get
flutter run
```

### 项目结构

```
Voicing/
├── pc/                          # 桌面端 (Python + PyQt5)
│   ├── voice_coding.py          # 主程序
│   ├── platform_utils.py        # 平台检测与通用工具
│   ├── platform_keyboard.py     # 键盘模拟抽象
│   ├── platform_autostart.py    # 开机自启抽象
│   ├── platform_instance.py     # 单实例检测抽象
│   ├── voicing_protocol.py      # 协议常量
│   ├── network_recovery.py      # UDP 广播恢复逻辑
│   └── requirements.txt         # Python 依赖
├── android/voice_coding/        # Android 端 (Flutter)
│   ├── lib/
│   │   ├── main.dart            # UI 层
│   │   ├── voicing_connection_controller.dart  # 连接状态机
│   │   ├── voicing_protocol.dart               # 协议常量
│   │   ├── app_theme.dart       # 主题与设计 token
│   │   └── app_logger.dart      # 日志封装
│   └── pubspec.yaml             # Flutter 依赖
├── protocol/                    # 双端共享协议契约
│   └── voicing_protocol_contract.json
├── .github/workflows/
│   └── release.yml              # 自动构建发布
├── CHANGELOG.md
├── CONTRIBUTING.md
└── LICENSE
```

### 打包发布

正式发布通过 GitHub Actions 自动构建（四平台：Android / Windows / macOS / Linux）：

```bash
git tag v2.7.0
git push origin v2.7.0
```

本地调试用：

```bash
# Windows
cd pc && pyinstaller --onefile --windowed --name=Voicing \
  --icon=assets/icon.ico --add-data "assets;assets" voice_coding.py

# macOS（生成 .app bundle）
cd pc && pyinstaller --windowed --name=Voicing \
  --icon=assets/icon.icns --add-data "assets:assets" voice_coding.py

# Linux
cd pc && pyinstaller --onefile --name=Voicing \
  --add-data "assets:assets" voice_coding.py

# Android
cd android/voice_coding && flutter build apk --release
```

注意：本地 Android release 构建需要兼容的 JDK 17/21。当前 GitHub Actions 发布环境固定使用 Java 17。

## 常见问题

**手机无法连接电脑？**
1. 确认电脑和手机在同一个 WiFi 热点或局域网下
2. 检查电脑防火墙是否放行 UDP 9530 端口
3. 手机息屏恢复后会立即进入快速重连，通常无需手动刷新
4. 仍然不行就点手机端"刷新连接"

**本地 Flutter 打 APK 失败，提示 Java / Gradle 不兼容？**
本机如果默认使用 Java 25，`flutter build apk --release` 会失败。请安装 JDK 17/21，并在 `android/voice_coding/android/local.properties` 中设置 `org.gradle.java.home=...`；正式 release 走 GitHub Actions 的 Java 17 环境。

**文字打到了错误位置？**
发送前确保电脑光标在正确的输入框里

**日志在哪？**
右键（macOS/Linux 为左键）托盘图标 → "打开日志"
- Windows: `%APPDATA%\Voicing\logs\`
- macOS: `~/Library/Logs/Voicing/`
- Linux: `~/.local/share/Voicing/logs/`

## 贡献

欢迎提交 Issue 和 Pull Request，请看 [CONTRIBUTING.md](CONTRIBUTING.md)

## 许可证

[MIT License](LICENSE)
