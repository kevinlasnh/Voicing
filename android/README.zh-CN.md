# Voicing Android App

[English](README.md) | [简体中文](README.zh-CN.md)

Android 端应用，通过手机语音输入将文字实时发送到电脑。

## 功能

- 语音输入完成后自动发送到电脑（始终启用）
- 按回车手动发送
- "自动 Enter"开关：语音分段输入静默后统一按一次回车（默认关闭，状态持久化）
- "撤回上次输入"恢复刚才的文本
- "刷新连接"手动重连
- 更多功能操作里的"扫码连接"支持扫描 PC 端二维码配对；每扫一台新 PC 都会追加到已配对列表，不覆盖之前的设备，同一 `device_id` 重扫只合并地址历史
- 多台已配对 PC 同时保持连接：每台设备都有独立的 WebSocket、心跳、重连退避与 Happy Eyeballs 候选竞速，同一 WiFi 下可以同时在线多台电脑
- "设备选择"是「更多功能操作」的最后一项（在"扫码连接"下方）。点击后向左侧弹出二级菜单，风格与现有下拉菜单一致，列出全部已配对设备及其实时状态（已连接 / 连接中 / 未连接，同步关闭显示为警告色）和当前目标的勾选标记；每行行尾的删除按钮可在确认后解绑该设备
- 文本、shadow 增量与 Auto Enter 只发往当前选中的设备；其它设备的迟到 ACK 不会清空输入框
- 顶部状态栏显示「状态 · 当前设备名」（例如「已连接 · 我的电脑」）
- 已配对设备按 schema v3 持久化（`saved_servers` 列表加 `active_device_key`）；旧 v1/v2 单设备 `saved_server` 数据首次启动自动迁移、无需重新扫码，同时继续写一份单设备 `saved_server`（等于活跃设备）供降级兼容
- 每条设备记录会记住该 PC 的 `device_id`、最近成功 IP、多个候选 IP，以及每个地址在哪个手机网络成功过（schema v2 地址簿）
- 启动、恢复前台和手动刷新时，按当前网络给每台已配对 PC 的候选地址排序并对最优候选**并行竞速**重连；回到曾配对过的网络约 1~2 秒自动连回，无需重扫
- 同一 PC 重新扫码时会合并新旧候选 IP 与网络历史，不会因为在新局域网扫码而丢掉旧局域网地址
- PC 端会在运行中刷新 QR 码和 WebSocket 监听地址，切换局域网后无需重启桌面端再扫码
- PC 端监听启动后，QR payload 会优先使用实际绑定成功的 IP
- Android 原生 WebSocket 对局域网目标按优先级选 WiFi 网络，对 Tailscale CGNAT 段目标走系统默认网络（VPN 隧道），因此开着 VPN 也不再阻断连接
- Android 原生 IME 高度监听让输入框实时跟随键盘展开/收起
- 息屏/亮屏后快速重连，并优先保持"已连接"状态显示
- 连接状态实时显示（已连接/连接中.../未连接）
- 深色主题 UI（Material Design 3）
- 通信协议（端口 9527、消息类型）与 QR payload 均未变更，新版 APK 与现有 PC 端直接互通，PC 端无需更新
- 协议契约测试覆盖

## 安装

从 [GitHub Releases](https://github.com/kevinlasnh/Voicing/releases/latest) 下载 `voicing.apk`，安装到手机。
建议同时下载 `SHA256SUMS.txt`，先校验摘要再安装。

或自行编译：

```bash
cd android/voice_coding
flutter pub get
flutter build apk --release
```

## 使用

1. 电脑运行桌面端程序，开启热点或连接同一局域网
2. 电脑端托盘菜单点击"显示 QR 码"
3. 手机连接同一网络，打开 Voicing
4. 首次使用或换电脑后，点击手机端"更多功能操作"里的"扫码连接"，扫描 PC 端二维码保存这台电脑（每次扫码都会把这台 PC 追加到已配对列表，不覆盖之前的设备，刚扫码的 PC 会成为当前发送目标）
5. 状态栏以「已连接 · 当前设备名」显示当前发送目标；后续启动会按当前网络给保存的地址排序，并并行尝试最优候选。若电脑和手机一起切换到新局域网，等待 PC 端刷新 QR 码后重新扫码一次即可把新网络并入地址簿，之后在该网络无需重扫；再切回旧局域网时会继续使用旧网络的成功地址。v2.9.4 起，QR payload 不再优先发布桌面端绑定失败的地址
6. 要把文字发给另一台已配对电脑：打开「更多功能操作 → 设备选择」（菜单最后一项、在"扫码连接"下方），在向左展开的二级菜单里点选目标设备。文本、shadow 增量与 Auto Enter 只发往选中的设备
7. 切换到语音输入法，说话，文字自动出现在电脑光标处
8. Linux/GNOME Wayland 桌面端统一发送普通 Ctrl+V，不再区分终端和普通窗口；终端程序默认不把 Ctrl+V 当粘贴，请在普通输入场景使用。如果 GNOME 在登录或 Voicing 启动后弹出 RemoteDesktop 键盘授权，请先允许再发送文字
9. 点击"更多功能操作"可开启"自动 Enter"（适合聊天场景，语音分段输入只会补一次 Enter）

## 构建说明

- GitHub Actions 发布环境使用 Java 17，可正常产出 `voicing.apk`
- tag 发布构建 Android / Windows / Linux 三个平台并作为 GitHub Release 资产发布；`workflow_dispatch` 手动构建现在也会自动发布新的 GitHub Release（tag 为 `v<仓库版本号>`，资产含 APK、Linux DEB/standalone 与 `SHA256SUMS.txt`，不含 Windows EXE），同时仍在本次 run 页面保留 workflow artifact
- 本地如果默认 Java 指向 25，`flutter build apk --release` 会失败；请在 `android/local.properties` 中通过 `org.gradle.java.home` 指向兼容的 JDK 17/21
- 改动 `MainActivity.kt`、Manifest 或 Gradle 配置后必须完整重新安装 APK；Flutter hot restart 不会更新原生层
- 改动键盘高度、WiFi-bound WebSocket 等原生桥接逻辑后，必须用完整 APK 重新安装验证
- 正式 release 现在必须配置 `key.properties`；若只做本地调试验证，可显式传入 `-Pvoicing.allowDebugReleaseSigning=true` 作为临时豁免，默认不再静默退回 debug signing
- Android Gradle 仓库顺序为官方 `google()` / `mavenCentral()` 优先，阿里云镜像仅作 fallback，避免镜像临时 502 阻断 GitHub Actions release 构建

## 技术栈

- Flutter 3.27.0 (CI)
- Dart SDK: `^3.5.4`
- web_socket_channel: `^2.4.5`
- shared_preferences: `^2.3.3`
- mobile_scanner: `^5.2.3`
- OkHttp: `4.12.0`（Android 原生 WiFi-bound WebSocket）
- Material Design 3
