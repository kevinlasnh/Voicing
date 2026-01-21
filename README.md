# Voice Coding / 语音编程

A lightweight Bluetooth/WiFi text bridge between your phone and PC. Type on your phone, text appears at your PC's cursor.

轻量级手机-电脑文本桥接工具。在手机上输入（语音输入），文本自动出现在电脑光标处。

---

## ✨ Features / 功能特性

| Feature / 功能 | Description / 描述 |
|---|---|
| 📱 **Phone Input / 手机输入** | Type or voice-input on your phone. 在手机上打字或语音输入。 |
| 💻 **PC Output / 电脑输出** | Text appears instantly at cursor position. 文本瞬间出现在光标处。 |
| 🔗 **Direct Connection / 直连** | No cloud, no server, just peer-to-peer. 无云端，无服务器，端对端直连。 |
| 📦 **Packet Transfer / 整包传输** | Text sent as complete packet, order guaranteed. 文本整包发送，顺序保证。 |
| 🖥️ **System Tray / 系统托盘** | Silent background service with tray icon. 静默后台运行，托盘图标。 |

---

## 📦 Download / 下载

| Platform / 平台 | Download / 下载 |
|---|---|
| Windows PC | [VoiceCoding.exe](./dist/VoiceCoding.exe) |
| Android | [VoiceCoding.apk](./dist/VoiceCoding.apk) |

---

## 🚀 Quick Start / 快速开始

### Step 1: PC Setup / 电脑端设置

1. Run `VoiceCoding.exe` on your Windows PC.  
   在 Windows 电脑上运行 `VoiceCoding.exe`。

2. A green icon appears in the system tray (bottom-right).  
   系统托盘（右下角）出现绿色图标。

3. Note the IP address shown (e.g., `192.168.1.100:9527`).  
   记下显示的 IP 地址（如 `192.168.1.100:9527`）。

### Step 2: Phone Setup / 手机端设置

1. Install `VoiceCoding.apk` on your Android phone.  
   在安卓手机上安装 `VoiceCoding.apk`。

2. Open the app, enter the PC's IP address.  
   打开应用，输入电脑的 IP 地址。

3. Tap "Connect" to establish connection.  
   点击"连接"建立连接。

### Step 3: Start Typing / 开始输入

1. Type or use voice input on your phone.  
   在手机上打字或使用语音输入。

2. Tap "Send" - text appears at your PC's cursor!  
   点击"发送" - 文本出现在电脑光标处！

---

## 🖱️ Tray Menu / 托盘菜单

Right-click the tray icon for options:  
右键点击托盘图标查看选项：

| Option / 选项 | Description / 描述 |
|---|---|
| 🚀 **Start with Windows / 开机启动** | Auto-start when Windows boots. 开机自动启动。 |
| ⏯️ **Enable Sync / 启用同步** | Toggle text sync on/off. 切换同步开关。 |
| 📋 **Show IP / 显示IP** | Show connection IP address. 显示连接IP地址。 |
| ❌ **Quit / 退出** | Exit the application. 退出程序。 |

---

## 🛠️ Tech Stack / 技术栈

### PC (Windows)
- Python 3.10+
- `pystray` - System tray integration
- `websockets` - Real-time communication
- `pyautogui` - Keyboard simulation

### Android
- Kivy / KivyMD - Cross-platform UI
- WebSocket client

---

## 📁 Project Structure / 项目结构

```
Voice-Coding/
├── README.md
├── .gitignore
├── pc/                      # Windows PC application
│   ├── voice_coding.py      # Main application
│   ├── requirements.txt     # Python dependencies
│   └── VoiceCoding.spec     # PyInstaller config
├── android/                 # Android application
│   ├── main.py              # Kivy main app
│   ├── buildozer.spec       # Android build config
│   └── voicecoding.kv       # Kivy UI layout
└── dist/                    # Built executables
    ├── VoiceCoding.exe
    └── VoiceCoding.apk
```

---

## 🔧 Build from Source / 从源码构建

### PC Application
```bash
cd pc
pip install -r requirements.txt
pyinstaller VoiceCoding.spec
```

### Android Application
```bash
cd android
pip install buildozer
buildozer android debug  # Requires Linux/WSL
```

---

## 📄 License / 许可证

MIT License
