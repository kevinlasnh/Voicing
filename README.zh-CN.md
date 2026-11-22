<div align="center">

<img src="android/voice_coding/assets/icons/icon_1024.png" width="120" alt="Voicing" style="border-radius: 50%;">

# Voicing

**把手机语音输入法的输出结果塞进电脑 Agent 的嘴里**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/kevinlasnh/Voicing)](https://github.com/kevinlasnh/Voicing/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android-blueviolet)](#)
[![Version](https://img.shields.io/badge/version-2.10.3-green)](#)

[English](README.md) | **简体中文**

和 AI 对话时打字太慢？Voicing 让你用嘴代替手

</div>

---

> **说明**：macOS 和 Linux 桌面端目前仍处于内测阶段，正在持续测试中，稳定性暂时无法保证。官方 CI/Release 只产出 Windows、Linux 与 Android，macOS 应用需从源码自行构建（见「打包发布」）。

## 它能做什么

Voicing 把手机的语音输入法变成电脑的"嘴"——你在手机上说话，文字直接出现在电脑光标处

- **扫码配对连接** — 首次扫描 PC 端二维码即可保存设备；之后每扫一台新 PC 都会追加到已配对列表，不会覆盖之前的设备
- **多台 PC 同时在线** — 同一 WiFi 下可以配对多台电脑并同时保持连接：每台设备都有独立的 WebSocket、心跳、重连退避与候选竞速
- **设备选择** — 在「更多功能操作 → 设备选择」切换发送目标；向左弹出的二级菜单与顶部状态格同宽、同间距、同风格，列出全部已配对设备与状态灯，当前目标保持与点击菜单行相同的常驻高亮（点选后菜单不收起，只有点击菜单外区域才关闭），名称过长时像音乐播放器歌名一样缓慢滚动；长按设备行并确认即可解绑
- **跨网络秒级重连** — 每个保存的地址都会记录它在哪个手机网络成功过（schema v2 地址簿），按当前网络自适应排序并**并行竞速**拨号；同一台电脑在家/公司等多个网络各扫码一次后，回到任一网络约 1~2 秒自动连回，无需重扫
- **无广播依赖** — 手机端启动后直接尝试已保存设备的 IP 池，不再依赖 UDP 广播发现
- **PC 端运行时刷新网络地址** — 电脑切换到新局域网后，QR 码和 WebSocket 监听会自动刷新，无需重启桌面端
- **QR 只发布实际监听 IP** — WebSocket 监听启动后，二维码只优先展示桌面端实际绑定成功的地址
- **物理网卡优先 + Tailscale 兜底** — 双端优先走真实 WiFi/LAN；PC 端另外把 Tailscale 地址写进 QR 作为兜底，手机侧对该地址走 VPN 隧道，因此即使 Android 禁止 socket 绕过 VPN 也仍然连得上
- **语音自动发送** — 说完话文字自动打过去，不需要手动操作
- **自动 Enter** — 可选开关，开启后说完话文字就被自动提交给 Agent 执行，无需手动在键盘上按回车键
- **手动发送也行** — 按回车手动发送，适合需要编辑的场景
- **撤回支持** — 发错了？一键撤回上次输入
- **断线自动恢复** — 手机息屏再亮屏，优先保持已连接显示并快速恢复
- **Linux 粘贴稳定** — GNOME Wayland 下统一发送普通 Ctrl+V，不再探测终端焦点，粘贴结果不受辅助功能总线状态影响
- **跨平台** — 桌面端代码支持 Windows / macOS / Linux，手机端为 Android；官方产物覆盖 Windows、Linux 与 Android，macOS 需从源码构建
- **体积小巧** — APK 约 32MB、桌面端约 50–60MB；Linux DEB 会自动安装声明的桌面集成依赖

## 快速开始

### 1. 下载

从 [Releases](https://github.com/kevinlasnh/Voicing/releases/latest) 下载对应平台文件：

| 平台 | 文件 | 要求 |
|------|------|------|
| Windows | `voicing-windows-x64.exe` | Win 10/11 (64-bit) |
| Linux | `voicing-linux-amd64.deb` 或 `voicing-linux-x86_64` | Ubuntu 22.04+ GNOME X11，或具备 RemoteDesktop portal 的 GNOME Wayland |
| Android | `voicing.apk` | Android 5.0+ |

Release 里同时提供 `SHA256SUMS.txt`，下载后可先校验 SHA-256 摘要再安装或运行。tag 发布固定产出上面 4 个构建产物（APK、Windows EXE、Linux DEB 与 Linux 独立二进制）加 `SHA256SUMS.txt`。

> **macOS**：官方不再产出 DMG（macOS CI job 已删除）。桌面端代码仍然保留——按「打包发布」里的命令从源码构建 `.app` 后本地运行。

### 2. 连接

```
电脑运行桌面端程序 → 开启热点 / 互联网共享 / 同一局域网 → 电脑端显示 QR 码 → 手机扫码连接
```

- **Windows**：运行 `voicing-windows-x64.exe`，开启"移动热点"
- **macOS**：按「打包发布」从源码构建 `.app`，再开启"互联网共享"或连接同一局域网
- **Linux**：安装 `voicing-linux-amd64.deb`，或对独立二进制执行 `chmod +x voicing-linux-x86_64` 后运行；开启 Wi-Fi 热点或连接同一局域网。GNOME Wayland 在 Voicing 启动或首次粘贴文字时可能会要求授权 RemoteDesktop 键盘会话

状态栏显示「已连接」就说明连上了；当前接收文字的电脑是「更多功能操作 → 设备选择」里保持高亮的那一行。

扫码成功后手机会记住这台电脑及其候选 IP 池，并记录每个地址在哪个网络成功过。每扫一台新 PC 都会追加到已配对列表而不是覆盖之前的设备，全部已配对电脑会并行尝试连接，因此可以多台同时在线；用「更多功能操作 → 设备选择」决定文字发往哪一台。同一台电脑在两个不同网络（例如家里 WiFi 和公司 WiFi、或手机热点）各扫码配对一次后，回到其中任一网络都会在约 1~2 秒内自动连回，不需要重新扫码：候选地址按当前网络自适应排序（本网络成功过 > 同网段 > Tailscale 兜底），并以并行竞速方式同时尝试，而不是串行等待。电脑端切换到新局域网后会自动刷新 QR 码和 WebSocket 监听地址；手机在新局域网重新扫码同一台 PC 时，会把新 IP 合并进候选池，不丢旧网络地址。从 2.9.14 升级会保留全部原有候选池，并把单台已保存设备自动迁移进多设备列表（存储 schema v3），无需重新扫码。

### 3. 使用

1. 电脑上把光标点到要输入的位置
2. 手机上切换到语音输入法，开始说话
3. 文字自动出现在电脑上

Linux/GNOME Wayland 下桌面端统一发送普通 Ctrl+V，不再区分终端和普通窗口，也不需要任何终端侧配置。注意终端程序默认不把 Ctrl+V 当粘贴（GNOME Terminal / Ghostty 等的粘贴快捷键是 Ctrl+Shift+V），所以桌面端现在面向的是浏览器、编辑器、聊天窗口等普通输入场景；终端内的粘贴请用终端自己的快捷键。

> **推荐搭配**：[豆包输入法](https://shurufa.doubao.com/) + [大疆 Mic Mini](https://www.dji.com/cn/mic-mini) + [DJI Mic 系列手机接收器](https://store.dji.com/cn/product/dji-mic-series-mobile-receiver?vid=200571) —— 语音识别准确，领夹麦克风直连手机，体验最佳

## 功能一览

### 手机端

- 语音输入完成后自动发送到电脑
- 按回车手动发送
- "自动 Enter"开关：语音分段输入时只在静默后统一按一次回车（默认关闭）
- "撤回上次输入"恢复刚才的文本
- "刷新连接"手动重连
- "扫码连接"（更多功能操作）把扫描到的 PC 追加到已配对列表；同一台 PC 重扫只合并地址历史
- "设备选择"（更多功能操作里"扫码连接"下方）向左展开二级菜单，列出全部已配对设备与状态灯；当前目标保持与点击菜单行相同的常驻高亮，名称过长时会缓慢来回滚动。文本、shadow 增量与 Auto Enter 只发往选中设备。长按设备行并确认即可解绑该设备

### 电脑端

托盘图标菜单（Windows 右键 / macOS 左键 / Linux 左键或右键）：

| 菜单项 | 功能 |
|--------|------|
| 显示 QR 码 | 展示当前电脑的 Voicing 配对二维码 |
| 同步输入 | 开关是否接收手机文字 |
| 开机自启 | 通过系统机制登录后自动启动：Windows Run 注册表、macOS LaunchAgent、Linux GNOME autostart `.desktop` |
| 打开日志 | 用记事本打开当天日志 |
| 退出应用 | 关闭程序 |

托盘图标状态：
- 闪烁 = 等待手机连接
- 常亮 = 已连接
- 灰色 = 同步已关闭

## 工作原理

1. 桌面端展示包含 `device_id/ip/ips/port/name/os` 的配对二维码，运行中会刷新当前物理 IPv4 地址池，并优先使用 WebSocket 实际绑定成功的 IP
2. 手机扫描二维码后做 WebSocket（端口 9527）连通性 probe，成功后把这台 PC 追加到已配对设备列表（同一 `device_id` 重扫会合并记录，不产生重复项）
3. 手机端为每台已配对 PC 持久化多个候选 IP，热点和不同局域网地址都会保留，并记录每个地址在哪个网络成功过；已配对设备与当前发送目标按 schema v3 存储（`saved_servers` 列表加 `active_device_key`），旧单设备数据自动迁移，同时继续写一份单设备记录供降级兼容；同一 `device_id` 重新扫码会同时合并候选池与网络历史，不覆盖旧地址
4. 全部已配对 PC 并发建链：每台都有独立心跳、重连退避和候选竞速，因此同一 WiFi 下可以有多台电脑同时在线
5. 后续启动或手动刷新时，手机按当前网络给候选地址打分排序，并对最优的几个候选并行竞速（120ms 错峰、首个握手成功即胜出），不再依赖 UDP 广播发现
6. PC 端 WebSocket server 会在地址池变化后重新绑定当前局域网 IP，避免继续监听旧网络地址
7. QR payload 避免发布绑定失败的地址；macOS 网卡命名按保守策略处理，不再假设 `en0` 一定是 WiFi
8. PC 端把局域网地址排在首位，并把 Tailscale 地址（经 `tailscale` CLI 读取）作为兜底候选一起写入 QR 且一并监听；Android 端对局域网目标按优先级绑定 WiFi Network（物理 WiFi → capability 受 VPN 影响的 WiFi → 继承 WiFi transport 的 VPN 网络），对 Tailscale CGNAT 段目标则走系统默认网络即 VPN 隧道
9. 手机上的文字（语音输入或手动输入）实时发送到桌面端；配对多台 PC 时只发给「更多功能操作 → 设备选择」选中的那一台（shadow 增量与 Auto Enter 同样跟随该目标），其它设备的迟到 ACK 不会清空输入框
10. 桌面端通过剪贴板粘贴文本，并在需要时补发一次 Enter；Linux X11 走常规 Ctrl+V 路径，GNOME Wayland 走 RemoteDesktop portal 键盘授权
11. GNOME Wayland 统一发送普通 Ctrl+V：不再做终端焦点探测，也不再提供粘贴模式切换，粘贴行为完全确定

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
│   ├── voice_coding.py          # 入口、装配与兼容导出层
│   ├── network_interfaces.py    # 网卡发现/过滤、地址快照缓存
│   ├── voicing_server.py        # WebSocket server、连接注册表、同步广播
│   ├── tray_ui.py               # 托盘图标与菜单（Linux 原生 QMenu）
│   ├── qr_dialog.py             # QR 弹窗与扫码成功遮罩
│   ├── voicing_tuning.py        # 全部可调参数与 VOICING_* 覆盖
│   ├── voicing_state.py         # 跨线程共享状态与 Qt 信号桥
│   ├── device_identity.py       # PC device_id / name / os 持久化
│   ├── platform_utils.py        # 平台检测与通用工具
│   ├── platform_keyboard.py     # 键盘模拟抽象
│   ├── platform_autostart.py    # 开机自启抽象
│   ├── platform_instance.py     # 单实例检测抽象
│   ├── voicing_protocol.py      # 协议常量
│   ├── network_recovery.py      # 网络恢复策略辅助
│   └── requirements.txt         # Python 依赖
├── android/voice_coding/        # Android 端 (Flutter)
│   ├── lib/
│   │   ├── main.dart            # UI 层（含「更多功能操作」与设备选择二级菜单）
│   │   ├── voicing_connection_controller.dart  # 连接状态机
│   │   ├── voicing_protocol.dart               # 协议常量
│   │   ├── saved_server.dart    # 已配对 PC 持久化（schema v3 设备列表、v2 地址簿）
│   │   ├── server_address_book.dart # 跨网络地址历史与评分排序
│   │   ├── network_profile.dart # 手机网络画像（接口/子网）
│   │   ├── connection_race.dart # Happy Eyeballs 并行竞速拨号
│   │   ├── connection_tuning.dart # 连接层可调参数
│   │   ├── voicing_websocket.dart # Android WiFi-bound WebSocket / Dart fallback
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

正式发布通过 GitHub Actions 自动构建，只构建三个平台（Android / Windows / Linux）；macOS job 已删除，官方 Release 不再产出 macOS DMG。tag 发布固定产出 4 个构建产物（`voicing.apk`、`voicing-windows-x64.exe`、`voicing-linux-amd64.deb`、`voicing-linux-x86_64`）加 `SHA256SUMS.txt`：

```bash
git tag v2.10.3
git push origin v2.10.3
```

手动构建使用 `workflow_dispatch` 触发（GitHub Actions 页面 Run workflow，或命令行）：

```bash
gh workflow run release.yml --ref main
```

手动构建会自动发布一个新的 GitHub Release：从仓库版本文件（`pubspec.yaml` / `APP_VERSION`，不会使用分支名）推导版本号，在本次构建的 commit 上创建 tag `vX.Y.Z`，并把 APK、Linux DEB、Linux standalone 二进制与 `SHA256SUMS.txt` 上传到该 Release。workflow artifact（`android-apk`、`linux-deb`、`linux-bin`）仍保留在本次 run 页面。手动发布不构建 Windows EXE；tag 推送发布保留 Windows 资产。

本地调试用：

```bash
# Windows
cd pc && pyinstaller --onefile --windowed --name=Voicing \
  --icon=assets/icon.ico --add-data "assets;assets" voice_coding.py

# macOS（生成 .app bundle，仅限源码自行构建，官方 CI/Release 不再产出）
cd pc && pyinstaller --windowed --name=Voicing \
  --icon=assets/icon.icns --add-data "assets:assets" voice_coding.py

# Linux
cd pc && pyinstaller --onefile --name=Voicing \
  --add-data "assets:assets" voice_coding.py

# Android
cd android/voice_coding && flutter build apk --release
```

注意：本地 Android release 构建需要兼容的 JDK 17/21，并配置正式签名；当前 GitHub Actions 发布环境固定使用 Java 17，正式 Release 也会强制校验签名 secrets。Android Gradle 仓库解析优先使用官方 `google()` / `mavenCentral()`，阿里云镜像仅作为 fallback。

## 常见问题

**手机无法连接电脑？**
1. 确认电脑和手机在同一个 WiFi 热点或局域网下
2. 检查电脑防火墙是否放行 TCP 9527
3. 首次使用或换电脑后，用电脑端"显示 QR 码"和手机端"扫码连接"配对一次（每次扫码都会把 PC 追加到已配对列表，不覆盖之前的设备）
4. 手机息屏恢复后会立即进入快速重连，通常无需手动刷新
5. 刚切换到新局域网后，PC 端会自动刷新 QR 码和监听地址；仍然不行就点手机端"刷新连接"，或重新扫描 PC 端二维码把新 IP 合并进候选池
6. 如果电脑端是 macOS，请确认已更新并重启到 v2.9.4 或更新版本，这些版本不再因为 `en0/en1` 网卡命名误判而优先发布错误地址

**同一 WiFi 下有多台电脑，怎么选择把文字发给哪一台？**
每台电脑扫码配对一次即可：每次扫码都会追加到已配对列表，之前的设备不会被替换，刚扫码的这台 PC 会自动成为当前发送目标，全部已配对电脑各自保持连接。打开「更多功能操作 → 设备选择」（菜单最后一项、在"扫码连接"下方），向左展开的二级菜单会列出所有已配对设备与实时状态，当前目标保持高亮（与点击右侧菜单行同一种效果），名称过长时缓慢来回滚动。选中后文本、shadow 增量与 Auto Enter 只发往该设备；顶部状态栏只显示连接状态。

**本地 Flutter 打 APK 失败，提示 Java / Gradle 不兼容？**
本机如果默认使用 Java 25，`flutter build apk --release` 会失败。请安装 JDK 17/21，并在 `android/voice_coding/android/local.properties` 中设置 `org.gradle.java.home=...`；正式 release 走 GitHub Actions 的 Java 17 环境。

**文字打到了错误位置？**
发送前确保电脑光标在正确的输入框里

**Linux 下终端里粘不上？**
这是预期行为。Voicing 现在统一发送普通 Ctrl+V，而终端默认不把 Ctrl+V 当粘贴。终端内的粘贴请使用终端自身快捷键（例如 GNOME Terminal / Ghostty 的 Ctrl+Shift+V）。

**Linux 开机自启正常吗？**
Ubuntu GNOME 下正常。Voicing 会写入 `~/.config/autostart/voicing.desktop`，由 GNOME 在登录后启动。GNOME Wayland 下程序可以自启，但 RemoteDesktop 键盘授权仍由 GNOME 控制；登录或启动后如果弹出授权提示，需要手动允许。

**日志在哪？**
打开托盘图标菜单 → "打开日志"
- Windows: `%APPDATA%\Voicing\logs\`
- macOS: `~/Library/Logs/Voicing/`
- Linux: `~/.local/share/Voicing/logs/`

## 贡献

欢迎提交 Issue 和 Pull Request，请看 [CONTRIBUTING.md](CONTRIBUTING.md)

## 许可证

[MIT License](LICENSE)
