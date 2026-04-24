# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### 改进

- 微调 Android 顶部状态文字和“更多功能操作”文字的纵向位置

### 文档

- 同步 README、Android README 和项目开发规范到 v2.9.1 QR-only 连接策略
- 统一文档中的“QR 码”写法，移除字母间错误空格
- 优化精简 `AGENTS.md` / `CLAUDE.md`，保持两份仓库级 agent 规则完全一致
- 停止跟踪本地 agent 规则文件 `AGENTS.md` / `CLAUDE.md`，并加入 `.gitignore`

---

## [2.9.1] - 2026-04-24

### 修复

- **Android: QR-only 连接路径**
  - 手机端启动、恢复前台和手动刷新时不再依赖 UDP 广播发现
  - 已保存设备会直接按 IP 池逐个尝试连接，适配热点、学校/公司局域网等多网络切换场景
  - 无保存设备时保持未连接，引导用户通过“更多功能操作 → 扫码连接”完成首次配对

- **PC: 停止运行时 UDP 广播**
  - 桌面端不再启动 UDP 广播线程
  - 保留物理网卡枚举，用于 QR payload 的主 IP 和候选 IP 列表

- **Android: 键盘和扫码 UI**
  - 修复键盘打开时点击“扫码连接”导致二维码区域先出现在上方、再跟随输入区下移的问题
  - 改用 Android 原生 `WindowInsetsAnimationCompat` 逐帧键盘高度驱动输入区，键盘展开/收起时输入框高度更实时
  - 修复 App 首次点击“更多功能操作”时菜单冷绘制卡顿
  - 微调顶部“已连接/未连接/连接中”和“更多功能操作”文字位置

### 文档

- README 更新为 2.9.1 QR-only 当前行为：首次扫码配对，后续按保存的 IP 池自动重连，不再描述 UDP 优先发现路径

### 测试

- Android:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`
  - `JAVA_HOME=C:\dev\java21\jdk-21.0.2 flutter build apk --debug`
- PC:
  - `python -m py_compile pc/voice_coding.py pc/voicing_protocol.py pc/device_identity.py pc/network_recovery.py`
  - `python -m unittest discover -s pc/tests`

---

## [2.9.0] - 2026-04-24

### 新增

- **QR 扫码连接**
  - PC 托盘菜单新增“显示 QR 码”，二维码包含 `device_id/ip/ips/port/name/os`
  - Android 更多功能菜单新增“扫码连接”，输入区切换为相机预览和四角扫描框
  - 扫码后先做 WebSocket 连通性 probe，成功才保存设备并正式重连

- **单设备持久化**
  - Android 新增 `saved_server` JSON 存储，保存 PC 身份、最近成功地址、候选地址列表、端口、名称、系统和最近连接时间
  - 旧 `manual_server_ip` / `manual_server_port` 自动迁移到 `saved_server`
  - App 启动和手动刷新时优先等待 UDP 广播，失败后回退保存过的 PC 地址候选
  - 同一台 PC 的热点 IP、局域网 IP 可同时保存，网络切换后会逐个候选重连
  - 扫到不同 `device_id` 时会要求确认替换

- **公司网络 / VPN 场景支持**
  - PC 端过滤 VPN 和虚拟网卡，QR 优先展示物理热点/以太网/WiFi 地址，并携带全部可达候选
  - PC WebSocket server 监听全部可广播物理地址，网络变化后自动刷新监听地址
  - Android 端新增 WiFi-bound 原生 WebSocket 通道，通过 `ConnectivityManager` + OkHttp 让普通连接优先走物理 WiFi Network
  - Android Manifest 显式允许局域网明文 `ws://`，匹配当前 PC 端 WebSocket 协议

### 改进

- Android 首屏保持原有状态栏、更多功能操作和输入框；扫码入口只保留在“更多功能操作”中
- “刷新连接”会真实重连，已连接状态下不会被旧 WebSocket 回调闪回“未连接”
- QR 扫码失败提示细分为非 Voicing QR、版本不兼容、二维码损坏
- 相机权限拒绝时显示设置引导，并保留手动 IP fallback
- PC QR 弹窗加入扫码成功绿色对勾反馈，并避免普通自动重连误触发成功态
  - PC QR 弹窗动画改为单顶层窗口绘制，减少 Windows/Qt compositor 下的随机闪屏

### 测试

- Android:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`
  - `flutter build apk --debug`
- PC:
  - `python -m py_compile pc/voice_coding.py pc/voicing_protocol.py pc/device_identity.py pc/network_recovery.py`
  - `python -m unittest discover -s pc/tests`
  - 真机验证：PC 热点、学校局域网、扫码保存、多 IP 候选 fallback 已闭环

---

## [2.7.3] - 2026-04-23

### 修复

- **PC: 托盘菜单视觉边缘精确对齐鼠标**
  - 之前菜单左下角与鼠标点击位置仍有 ~8px 偏移，原因是外层 `QVBoxLayout` 留了 8px 阴影边距
  - 现在按 `layout().contentsMargins()` 动态补偿（X 减 `shadow.left()`，Windows 上 Y 加 `shadow.bottom()`），让视觉菜单边缘而非 widget 外框对齐鼠标
  - macOS / Linux 同步按 `shadow.top()` 补偿向下展开方向

- **PC: 连续右键托盘图标可反复弹出菜单**
  - 修复 `Qt.Popup` 在 Windows 上"吃掉"第二次右键点击导致菜单无法再次弹出的问题
  - 在 `mousePressEvent` 中检测外部右键点击是否落在托盘图标矩形内，是则 `QTimer.singleShot(0)` 立刻在新位置重开菜单
  - 左键点击托盘图标不再触发菜单（仅右键响应）
  - 点击菜单外部区域仍正常关闭菜单（`Qt.Popup` 内建行为保留）

### 文档

- **新增"开发联调工作流"章节到 CLAUDE.md**
  - 记录已注册测试设备（Pixel 5 / Windows）
  - 标准启动序列（PC 热重启 + Flutter run）
  - 双端改动后的迭代规则（热重载 vs 热重启）
  - 触发词规范（"启动开发环境" / "启动联调"）

### 测试

- PC：
  - `python -m py_compile pc/voice_coding.py`
  - Windows 本地手动验证：右键托盘图标，菜单视觉左下角精确贴合鼠标点击位置

---

## [2.7.2] - 2026-04-17

### 修复

- **PC: 托盘右键菜单贴合鼠标位置**
  - Windows：菜单左下角对齐鼠标点击位置（符合 `TrackPopupMenu` 的 `TPM_LEFTALIGN | TPM_BOTTOMALIGN` 标准行为）
  - 修复 Windows 任务栏内点击时菜单被强制推到任务栏上方留出 30-50px 缝隙的问题
  - macOS / Linux 保持菜单左上角对齐图标（向下展开）的标准行为

### 测试

- PC：
  - `python -m unittest discover -s pc/tests`
  - `python -m py_compile pc/voice_coding.py`
  - Windows 本地手动验证：右键托盘图标，菜单左下角贴合鼠标位置

---

## [2.7.1] - 2026-04-17

### 改进

- **PC: UDP 自动发现支持局域网与热点双模**
  - 桌面端现在会枚举可广播的私有 IPv4 接口，并分别向每个子网发送定向 UDP 广播
  - 手机连同一路由器或连电脑热点时，都能收到对应可达 IP 的发现报文
  - 命令探测失败时不再猜测 `/24` 前缀，改为回退到 `<broadcast>`，避免把广播打到错误子网

- **PC: 网络接口过滤更安全**
  - 过滤回环、链路本地、组播、未指定地址，以及不适合做局域网发现的 `/31`、`/32` 地址
  - Windows / Linux / macOS 三平台接口解析都增加了更严格的候选筛选，降低误把 VPN / 虚拟接口当作发现接口的概率

- **GitHub Actions Release 链路加固**
  - workflow 中使用的第三方 Actions 全部改为 full commit SHA pin
  - 默认 token 权限收紧为只读，仅发布 job 保留 `contents: write`
  - `checkout` 关闭持久化凭据，减少构建阶段的 token 暴露面
  - Release 新增 `SHA256SUMS.txt`，下载后可校验产物完整性

### 修复

- **Android Release 不再允许静默退回 debug signing**
  - GitHub Actions 现在会强制检查正式签名 secrets，缺失时直接 fail
  - Android Gradle 在执行 release 任务时，若未配置签名且未显式开启本地调试豁免，会直接阻断构建

### 测试

- Android：
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`
- PC：
  - `python -m unittest discover -s pc/tests`
  - `cd pc && python -m unittest discover -s tests`
  - `python -m py_compile pc/voice_coding.py pc/network_recovery.py pc/platform_utils.py pc/voicing_protocol.py`
  - 新增三平台接口解析与广播地址计算测试

---

## [2.7.0] - 2026-04-16

### 新增

- **macOS 桌面端支持（Apple Silicon / arm64）**
  - PC 端拆出平台抽象层，支持 macOS 的日志目录、托盘菜单、自启和输入热键
  - 发布产物新增 `voicing-macos-arm64.dmg`
  - macOS `.app` bundle 写入 `LSUIElement=true`，以托盘常驻应用形态运行

- **Ubuntu 22.04 GNOME on X11 桌面端支持**
  - PC 端支持 Linux 的日志目录、`.desktop` 自启、托盘交互和 Ctrl+V 输入
  - 发布产物新增 `voicing-linux-x86_64`
  - 程序启动时会显式阻断 Wayland，会话不满足条件时直接提示，避免静默输入失败

- **跨平台桌面端测试覆盖**
  - 新增平台工具、键盘和自启模块测试
  - 桌面端测试命令同时支持仓库根目录和 `pc` 目录执行

### 改进

- **GitHub Actions Release 流程重构**
  - Android / Windows / macOS / Linux 构建先上传 workflow artifacts
  - 最终由单独的 publish job 聚合全部产物并一次性创建 GitHub Release
  - 固定 macOS runner 为 `macos-14`，Linux runner 为 `ubuntu-22.04`

- **Android release 签名链路**
  - 支持通过 GitHub Secrets 生成 `key.properties` 和 release keystore
  - 未配置 secrets 时仍保持 debug signing，兼容本地开发与现有 CI 环境

### 测试

- Android：
  - `flutter test`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
- PC：
  - `python -m unittest discover -s pc/tests`
  - `python -m unittest discover -s tests`
  - `python -m py_compile pc/voice_coding.py pc/platform_utils.py pc/platform_keyboard.py pc/platform_autostart.py pc/platform_instance.py`

---

## [2.6.2] - 2026-04-15

### 修复

- **Android: 息屏唤醒后的前台恢复体验**
  - 亮屏时会重建 UDP 发现监听，并立即进入前台恢复窗口
  - 恢复窗口内使用 500ms 快速重试，不再回退到常规 3/6/12 秒指数退避
  - 如果亮屏前已经连上，恢复期间状态栏保持显示"已连接"，避免闪成"未连接"

- **自动 Enter 与自动发送链路解耦**
  - `TYPE_TEXT` 新增 `send_mode`，区分 `submit`、`shadow`、`commit`
  - Shadow 增量输入不再直接触发 Enter，改为静默窗口后统一 finalize
  - 解决部分输入法一次语音分多段 commit 时，多次 Enter 被某些聊天框解释为换行的问题

- **协议 ACK 改为显式控制清空输入框**
  - `ack` 消息新增 `clear_input`
  - 仅手动 `submit` 会由服务端确认后清空输入框
  - Shadow / commit 不再依赖 ACK 到达时序来清空输入框，降低自动发送链路脆弱性

- **PC: 自动 Enter 注入更稳定**
  - 粘贴后增加 settle delay，再通过 Win32 `SendInput` 发送 Enter
  - 新增 commit 模式，支持只提交 Enter 而不重复输入文本

### 测试

- Android：
  - `flutter test`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
- PC：
  - `python -m unittest discover -s tests`
  - `python -m py_compile voice_coding.py network_recovery.py voicing_protocol.py`

---

## [2.6.1] - 2026-04-14

### 修复

- **Android: 菜单圆角区域水波纹溢出**
  - 问题：点击"自动 Enter"切换状态时，菜单圆角区域闪现白色直角效果
  - 原因：InkWell 水波纹效果未被裁剪到圆角边界内
  - 修复：使用 ClipRRect 裁剪第一个和最后一个菜单项，防止水波纹溢出

---

## [2.6.0] - 2026-04-14

### 新增

- **自动 Enter 功能**
  - Android: 菜单新增"自动 Enter"开关，默认关闭（红色 ✗）
  - 点击切换状态，带淡入淡出 + 颜色渐变动画（红色 ✗ ↔ 绿色 ✓）
  - 状态持久化到本地，App 重启后恢复上次设置
  - PC: 接收到文本后，根据 `auto_enter` 标志自动按 Enter 键
  - 通信协议: `TYPE_TEXT` 消息新增 `auto_enter` 字段

---

## [2.5.1] - 2026-04-14

### 改进

- **Android: 自动发送功能改为默认启用**
  - 移除菜单中的"自动发送"手动开关
  - 语音输入完成后始终自动发送到电脑，无需手动开启
  - 移除 `shared_preferences` 依赖

- **Android: 新增"连接中..."状态显示**
  - 重连过程中 header 显示橙色"连接中..."，替代直接显示"未连接"

- **Android: UI 细节优化**
  - 底部提示更新为"语音自动发送 · 回车手动发送"
  - 硬编码 `Colors.white` 替换为主题 token `AppColors.textPrimary`
  - 提取重复的文字样式为 `AppTextStyles` 常量
  - 菜单项和菜单按钮添加显式涟漪反馈色

### 修复

- **PC: 托盘菜单首次右键卡顿**
  - 问题：启动后首次右键托盘图标时菜单弹出有明显延迟
  - 原因：Qt 延迟渲染机制导致首次 show() 时才编译 stylesheet 和计算布局
  - 修复：启动时预热渲染菜单（屏幕外 show+hide），消除首次打开延迟

---

## [2.5.0] - 2026-04-14

### 改进

- **Android 架构拆分**
  - `main.dart` 仅保留 UI 组合逻辑
  - 新增 `voicing_connection_controller.dart` 承担连接状态机、自动发送和 UDP 恢复逻辑
  - 新增 `app_theme.dart` 抽离设计 token 与主题
  - 新增 `app_logger.dart`，移除生产代码中的 `print`

- **双端协议耦合加固**
  - 新增共享协议契约文件 `protocol/voicing_protocol_contract.json`
  - Android 新增 `voicing_protocol.dart` 统一协议常量与报文解析
  - PC 新增 `voicing_protocol.py` 统一端口、消息类型与报文构造
  - Android / PC 分别新增协议契约测试，避免消息结构再次漂移
  - Android 端显式处理 `sync_disabled`，PC 端补充 `sync_enabled: false`

- **UI 细节优化**
  - 修复 Android 菜单中“自动发送”文字与开关过于贴近的问题，增加稳定间距

### 修复

- **GitHub Actions Release Notes**
  - 修复标签 `vX.Y.Z` 与 `CHANGELOG.md` 中 `[X.Y.Z]` 的提取不一致问题
  - 当 changelog 缺少对应版本条目时，工作流会直接失败而不是生成空说明

- **仓库配置卫生**
  - `android/voice_coding/android/local.properties` 改为本地未跟踪文件，不再进入版本控制
  - 同步修正文档中本地 Java 配置与打包命令描述

### 测试

- Android：
  - `flutter test test/connection_recovery_policy_test.dart test/voicing_protocol_contract_test.dart`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
- PC：
  - `python -m unittest tests.test_network_recovery tests.test_protocol_contract`
  - `python -m py_compile voice_coding.py network_recovery.py voicing_protocol.py`

---

## [2.4.2] - 2026-04-11

### 修复

- **Android 息屏唤醒后的假断连**
  - 前台恢复时不再信任休眠前的旧 WebSocket，而是直接强制重建连接
  - WebSocket 连接新增 8 秒超时，避免状态卡在 `connecting`
  - 新增连接代次隔离，旧 socket 的 `onDone` / `onError` 不再覆盖新连接状态
  - 即使 UDP 广播的 IP 和端口没有变化，只要当前未连接，广播也会触发恢复重连

- **PC 端热点地址漂移**
  - UDP 广播改为每轮重新检测热点 IP，避免电脑网络恢复后继续广播旧地址

### 测试

- **Android 连接恢复策略测试**
  - 新增 `android/voice_coding/test/connection_recovery_policy_test.dart`
  - 覆盖前台恢复、心跳超时、同 IP UDP 恢复、连接冷却窗口

- **PC 广播恢复逻辑测试**
  - 新增 `pc/tests/test_network_recovery.py`
  - 覆盖热点 IP 变化判定和 UDP 广播负载生成

---

## [2.4.1] - 2026-04-08

### 改进

- **Android UI 优化（基于 UI Skill 规范）**
  - 提取 AppSpacing/AppColors 设计常量，消除全文硬编码的 magic numbers
  - 间距对齐 4px 网格系统（13.5→12, 12.5→12）
  - 触摸目标添加 minHeight: 44pt（符合移动端最低标准）
  - GestureDetector 替换为 InkWell，添加 Material 涟漪触摸反馈
  - 下拉菜单从 3 个独立浮动卡片改为单一分组卡片 + Divider 分隔（iOS grouped list 风格）
  - 动画时长统一为 250ms（原 200/250/300ms 混用）
  - 底部提示添加细分隔线
  - 菜单关闭逻辑提取为 _closeMenu() 方法

- **PC 端托盘菜单 UI 优化**
  - 菜单项添加按压视觉反馈（pressed state: white 10% 背景）
  - 添加 Escape 键关闭菜单（Windows 11 Fluent Design 标准行为）
  - 菜单项间距从 2px 调整为 4px（更舒适的视觉间距）

---

## [2.4.0] - 2026-04-08

### 修复

- **Android 待机断连问题**
  - 根因：App 不处理 `paused` 生命周期，无心跳机制，息屏后 WebSocket 静默死亡
  - 新增心跳机制：每 15 秒发送 ping，30 秒无响应判定连接死亡
  - 完善生命周期处理：息屏时停止心跳省电，亮屏时立即验证连接有效性
  - 改进重连策略：指数退避（3s → 6s → 12s → 最大 30s），替代固定 3 秒重试
  - 发送失败时立即触发断连处理

- **PC 端异步阻塞**
  - 问题：`type_text()` 在 async WebSocket handler 中同步调用，阻塞整个事件循环
  - 修复：使用 `asyncio.to_thread()` 将阻塞操作放入线程池

### 改进

- **EXE 图标裁剪为圆形**
  - 将正方形图标裁剪为圆形，与 Android 端统一风格
  - 重新生成多尺寸 ICO 文件（256/128/64/48/32/16px）

- **PC 端代码质量**
  - 5 处裸 `except:` 改为 `except Exception:`，避免吞掉所有异常
  - `AppState` 添加 `threading.Lock` 保护 `connected_clients` 等共享状态
  - UDP 广播轮询从 `time.sleep` 循环改为 `threading.Event.wait`，退出更优雅
  - 删除未使用的 pystray 兼容代码（~120 行），项目已完全使用 PyQt5

- **依赖优化**
  - 移除 `pystray` 依赖（不再使用）
  - `requirements.txt` 版本约束从 `>=` 改为 `~=`，防止跨大版本升级

- **CI/CD**
  - Python 构建版本从 3.14（未稳定）改为 3.12
  - `.gitignore` 添加签名密钥模式（`*.jks`, `*.keystore`, `*.key`, `*.pem`）

---

## [2.3.1] - 2026-02-04

### 🔥 关键修复

- **Android 网络权限修复**
  - 问题：APK 无法连接 PC 端
  - 原因：AndroidManifest.xml 缺少网络权限声明
  - 解决：添加 INTERNET、ACCESS_NETWORK_STATE、ACCESS_WIFI_STATE 权限

- **Windows EXE 图标修复**
  - 问题：EXE 文件图标显示为默认图标，托盘图标显示为纯蓝色
  - 原因：PyInstaller 打包时未包含图标资源
  - 解决：添加 `--icon` 和 `--add-data` 参数

### 🔧 技术改进

- **ICO 文件优化**
  - 创建多尺寸 ICO 文件（256/128/64/48/32/16px）
  - 确保 Windows 各种显示场景下图标清晰

- **CI/CD 更新**
  - GitHub Actions release.yml 添加图标打包步骤
  - 添加 PNG 转 ICO 自动化流程

---

## [2.3.0] - 2026-02-04

### 🎨 品牌更新

- **应用重命名：Voice Coding → Voicing** 🎯
  - 更现代、简洁的品牌名称
  - **Android 端**：
    - `AndroidManifest.xml` 应用标签更新
    - `pubspec.yaml` 包名更新
    - `main.dart` 应用标题更新
  - **PC 端**：
    - 应用名称、互斥锁名称、日志目录全部更新
    - 托盘提示文字更新
    - 错误消息更新

### 🔧 构建修复

- **Flutter 构建 Java 版本问题修复**
  - 问题：系统 JAVA_HOME 指向 Java 25，导致 Gradle 构建失败
  - 错误特征：`Error resolving plugin > 25.0.1`
  - 解决：在 `gradle.properties` 中指定 Java 21 路径
  - 新增规则到 `CLAUDE.md` 防止再次发生

- **Windows EXE 图标修复** 🎯
  - 问题：GitHub Actions 构建的 EXE 缺少图标资源
  - 表现：EXE 文件图标为默认图标，托盘图标显示为纯蓝色
  - 解决：PyInstaller 添加 `--icon` 和 `--add-data` 参数
  - 新增 PNG 转 ICO 步骤

- **Android 网络权限修复** 🔥
  - 问题：AndroidManifest.xml 缺少网络权限声明
  - 表现：APK 无法连接 PC 端
  - 解决：添加 INTERNET、ACCESS_NETWORK_STATE、ACCESS_WIFI_STATE 权限

### 🎯 PC 端托盘图标优化

- **圆形图标**：托盘图标改为圆形外轮廓，与微信等主流应用风格一致
- **图标放大**：256px 高清图标，系统自动缩放
- **悬停提示**：鼠标悬停显示 "Voicing" 提示窗口
- **只响应右键**：左键不再触发菜单，只有右键才显示菜单

### 🐛 Bug 修复

- **闪烁均匀化**：预缓存所有图标状态，解决闪烁时快时慢的问题
- **首次菜单加速**：预加载菜单组件，首次打开不再卡顿
- **闪烁速度**：调整为 200ms 间隔

### 📝 文档更新

- `CLAUDE.md` 新增 Flutter 构建 Java 版本规则
- 记录本机 Java 21 路径：`C:\dev\java21\jdk-21.0.2`
- 记录 Flutter 启动命令
- **README 添加应用图标** - 在标题区域展示 128px 应用图标

---

## [2.2.1] - 2026-02-04

### 🎨 优化改进

- **PC 端托盘图标优化** 🎯
  - 透明背景：去掉深蓝色底色，改为透明背景
  - 放大图标：麦克风占满更多空间，托盘中更清晰
  - 简化状态逻辑：
    - 已连接：正常彩色图标（去掉绿色边框）
    - 等待连接：图标闪烁（透明度变化）
    - 暂停：灰色图标（去掉暂停条）

### 🔧 技术改进

- 重新生成 `pc/assets/icon_1024.png` 为透明背景版本
- 简化 `create_icon_connected()` 函数，直接返回原图
- 简化 `create_icon_paused()` 函数，只做灰度转换

---

## [2.2.0] - 2026-02-04

### 🎨 新增功能

- **自定义应用图标** 🎯
  - 设计了专属 Voice Coding 图标（麦克风+声波元素）
  - 蓝色渐变配色（#4A90E2 → #00D4FF）
  - 深色背景（#1A1A2E）
  - **Android 端**：支持自适应图标（Adaptive Icon）
  - **PC 端**：托盘图标同步更新为新设计
    - 已连接：图标 + 绿色边框
    - 等待连接：正常图标（闪烁动画）
    - 暂停：灰度图标 + 暂停条标记

### 🔧 技术改进

- **Android 端**
  - 添加 `flutter_launcher_icons` 依赖自动生成各尺寸图标
  - 配置 `assets/icons/` 目录存放原始图标资源
  - 生成完整 mipmap 资源集（mdpi ~ xxxhdpi）
  - 配置 `mipmap-anydpi-v26` 自适应图标 XML

- **PC 端**
  - 新增 `load_base_icon()` 函数加载 PNG 图标
  - 重写 `create_icon_*()` 系列函数使用新图标
  - 更新 `ModernTrayIcon` 类使用新图标
  - 更新 `VoiceCoding.spec` 打包配置

### 📁 新增文件

- `android/voice_coding/assets/icons/icon_1024.png` - Android 原始设计稿
- `pc/assets/icon_1024.png` - PC 端图标资源
- `drawable-*/ic_launcher_foreground.png` - 前景图层
- `mipmap-anydpi-v26/ic_launcher.xml` - 自适应图标配置
- `values/colors.xml` - 背景色定义

---

## [2.1.0] - 2026-02-03

### ✨ 新增功能

- **自动发送** 🎯
  - 语音输入实时同步到电脑
  - 智能检测输入法 composing 状态（下划线）
  - 下划线消失时自动发送（输入法完成优化后）
  - 增量发送：只发送新增内容，不影响已有文本
  - 支持连续多段语音输入
  - 开关状态记忆：重启APP后保持上次的开关状态

### 🔧 技术改进

- 使用 `TextEditingController.addListener()` 监听文本状态变化
- 检测 `composing.isValid` 判断输入法是否正在组合文本
- 自动重置 `_lastSentLength` 防止发送失败

---

## [2.0.1] - 2026-02-03

### 🐛 修复问题

- **GitHub Actions 构建修复** - 修复 Android APK 构建失败问题
  - 移除 gradle.properties 中的本地代理配置
  - 修正 Gradle wrapper 配置

---

## [2.0.0] - 2026-02-03

> **重大更新** - 架构简化，专注 PC + Android 双端体验

### ✨ 新增功能

- **UDP 自动发现** 📡
  - 手机 APK 自动发现并连接 PC 服务器
  - PC 端每 2 秒广播服务器信息（IP、端口、设备名）
  - Android 端监听 UDP 广播端口 9530
  - 无需手动配置 IP 地址，支持任意网段
  - 兼容非默认热点 IP（如 192.168.0.1、10.0.0.1 等）

- **撤回功能** 🔄
  - Android 端可恢复最近发送的文本
  - 点击"撤回上次输入"即可恢复

### 🗑️ 移除功能

- Web 端功能（HTTP/HTTPS 服务器和 Web UI）
- PWA 安装支持
- ngrok 隧道功能

### 🔧 变更优化

- **架构简化** - 专注于 PC EXE + Android APK 双端
- **依赖精简** - 移除 cryptography、pyngrok、pyyaml
- **包名更新** - Android 应用 ID: `com.voicecoding.app`
- **构建优化** - GitHub Actions 配置更新

### 📦 下载

- [Android APK](https://github.com/kevinlasnh/Voicing/releases/latest) - 安装到手机
- [Windows EXE](https://github.com/kevinlasnh/Voicing/releases/latest) - 电脑端运行

---

## [1.8.0] - 2026-02-03

### ✨ 新增功能

- **Windows 11 Fluent Design 风格托盘菜单** 🎨
  - 深色半透明背景
  - 圆角设计 + 柔和阴影
  - 滑出动画效果
  - 悬停高亮效果

- **日志系统** 📋
  - 日志文件位置：`%APPDATA%\Voicing\logs\`
  - 托盘菜单"打开日志"快捷入口

### 🐛 修复问题

- PyQt5 菜单悬停高亮效果
- 菜单点击崩溃问题
- 菜单位置对齐问题

---

## [1.6.0] - 2026-02-02

### ✨ 新增功能

- **手动刷新连接** - Android 端新增"刷新连接"按钮
- **PC 热重启脚本** - 开发快速重启

### 🎨 UI 重新设计

- 状态栏连接状态 + 刷新按钮分栏显示
- 输入框配色与状态栏统一
- 移除输入框边框，简洁统一

---

## [1.0.0] - 2026-01-21

### 🎉 首次发布

- **PC 端**：系统托盘应用，接收手机文本并在光标处输入
- **Android 端**：Flutter 原生应用
- **WebSocket** 实时通信
- **开机自启**功能
- **自动断线重连**
- **Anthropic 风格 UI 设计**
