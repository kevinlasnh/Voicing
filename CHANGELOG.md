# Changelog / 更新日志

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.8.0] - 2026-02-03

### Added / 新增
- ✅ **PC 端悬停高亮效果已修复** - 使用 `paintEvent` + `WA_TransparentForMouseEvents` 实现
- 🎨 **Windows 11 Fluent Design 风格菜单** - 完整实现现代化 UI
  - 深色半透明背景 `rgba(32, 32, 32, 245)`
  - 8px 圆角容器，4px 圆角菜单项
  - 柔和阴影效果（24px 模糊半径）
  - 从下往上滑出动画 + 淡入效果
  - Segoe UI 字体（Windows 11 默认字体）
  - 统一白色图标和文字
- 📋 **日志系统** - 完整实现日志功能
  - 日志文件位置：`%APPDATA%\VoiceCoding\logs\voice_coding_YYYYMMDD.log`
  - 点击"打开日志"用记事本打开当天日志

### Changed / 变更
- 🚪 退出按钮图标从 ⏻ 改为 🚪
- 🗑️ 移除"显示 IP 地址"菜单选项
- 🗑️ 移除 `is_danger` 红色危险样式

### Fixed / 修复
- ✅ **悬停高亮效果** - PyQt5 自定义 QWidget 的 `:hover` 伪状态不工作
  - 解决方案：使用 `paintEvent` 手动绘制背景
  - 子控件添加 `setAttribute(Qt.WA_TransparentForMouseEvents)` 让鼠标事件穿透
- ✅ **菜单点击崩溃** - `toggle_sync` 调用 `update_tray_icon_pyqt(None)` 导致 NoneType 错误
  - 解决方案：改用 `state.tray_icon` 获取正确的托盘图标实例
- ✅ **菜单位置** - 菜单左下角现在正确对齐鼠标点击位置
- ✅ **状态标签背景** - 添加 `background: transparent` 修复高亮被截断问题

### Technical / 技术
- `MenuItemWidget` 类使用 `enterEvent`/`leaveEvent` 追踪悬停状态
- `paintEvent` 绘制 4px 圆角矩形背景
- 所有子 QLabel 设置 `WA_TransparentForMouseEvents` 让鼠标事件穿透
- 使用 Python `logging` 模块记录日志到文件

---

## [1.7.0] - 2026-02-03 (Deprecated - 已废弃)

### Added / 新增
- 🎨 **PC 端 Windows 11 风格托盘菜单** - 使用 PyQt5 实现现代化 UI
  - 圆角浮窗菜单设计
  - 流畅的悬停效果
  - 实时状态指示（● ON / ○ OFF）
  - 阴影效果提升层次感
- 📋 **打开日志功能** - 便捷查看应用日志
- 🔄 **箭头旋转动画** - Android 端菜单箭头随状态旋转

### Changed / 变更
- 🎨 **Android 端菜单优化**
  - "刷新连接" → "更多功能操作"下拉菜单
  - 使用 `→` 箭头图标，展开时旋转为 `↓`
  - 滑入 + 淡入动画效果
- 📐 **UI 间距微调** - Header 与输入框间距调整为 13.5px

### Technical / 技术
- 新增 PyQt5 依赖用于现代化托盘菜单

---

## [1.7.0] - 2026-02-03

### Added / 新增
- 🔄 **撤回功能** - Android 端新增"更多"菜单，支持撤回上次输入的文本
  - 点击菜单中的"撤回上次输入"，可将文本恢复到手机输入框
  - PC 端自动保存最近发送的文本
  - 解决光标位置错误导致文本丢失的问题
- 📋 **弹出菜单** - Android 端刷新按钮改为"更多"菜单
  - 刷新连接：手动重连
  - 撤回上次输入：恢复最近发送的文本

### Changed / 变更
- 🎨 **UI 间距微调** - Header 与输入框间距从 16px 调整为 14px

---

## [1.6.0] - 2026-02-02

### Added / 新增
- 📱 **手动刷新连接** - Android 端新增"刷新连接"按钮，点击可手动重连
- 🔧 **PC 热重启脚本** - 开发时可快速重启 PC 端应用

### Changed / 变更
- 🎨 **UI 重新设计**
  - 状态栏分为左右两栏：连接状态 + 刷新按钮
  - 输入框配色与状态栏统一（背景色 #3D3B37）
  - 移除输入框边框，简洁统一
- 🗑️ **移除焦点检测** - 移除不稳定的输入焦点检测功能
- 🗑️ **移除 Toast 提示** - 简化交互，移除所有弹窗提示
- 📋 **托盘菜单简化**
  - 仅保留：显示IP、同步开关、开机启动、退出
  - 使用动态文本显示开关状态（✓/无勾选）
  - 移除 HTTPS 和 ngrok 选项

### Removed / 移除
- 移除 `uiautomation` 依赖
- 移除 `psutil` 依赖
- 移除焦点监控线程

---

## [1.5.0] - 2026-02-02

### Added / 新增
- ✨ **PC 端输入焦点检测** - 自动检测当前窗口是否有输入焦点
- 📱 **Android 端焦点指示器** - Header 显示 🟢 可输入 / 🔴 无输入状态
- 🔄 **WiFi 重连恢复** - 应用回到前台时自动尝试重连

### Changed / 变更
- 🎨 **UI 简化** - 合并 Header 和状态栏为一个框
- ❌ **移除发送提示** - 发送成功后不再显示 Toast 提示
- 📐 **间距统一** - 所有边缘间距统一为 16px

### Fixed / 修复
- 🐛 **无输入焦点保护** - PC 端无输入焦点时阻止发送并清空文本
- 🐛 **输入框焦点边框** - 移除输入框聚焦时的橙色边框

---

## [1.4.0] - 2026-02-02

### Changed / 变更
- ✨ **UI 简化** - 移除"发送到电脑"和"清空"按钮
- ⌨️ **交互优化** - 使用回车键发送文本，底部显示提示

---

## [1.3.3] - 2026-02-02

### Fixed / 修复
- 🐛 **WebSocket 连接** - 修复 `Uri.parse()` 调用，移除不必要的 `requestFocus()`

### Changed / 变更
- 📄 **CLAUDE.md** - 完善开发规范文档，明确 CHANGELOG 更新流程

---

## [1.3.2] - 2026-02-02

### Changed / 变更
- ↩️ **UI 回退** - 回退到原始橙色主题设计
- 📦 安装 ui-ux-pro-max Skill 作为设计参考

---

## [1.3.1] - 2026-02-02

### Added / 新增
- 📄 **CLAUDE.md** - 开发规范文档

### Changed / 变更
- ✨ **输入框优化** - 文字靠上对齐，5行最小高度
- 🧹 **仓库清理** - 移除 IDE 文件和生成产物
- ⚙️ **Gradle 配置** - 升级到 8.11.1，配置代理支持

### Fixed / 修复
- 🐛 修复 Dart 编译错误（Uri.parse 和 FocusNode）
- 🐛 配置 Java 21 解决 Gradle 兼容性问题

---

## [1.3.0] - 2026-02-02

### Added / 新增
- 📱 **Android 原生应用** - Flutter 开发
  - WebSocket 实时通信
  - 自动重连机制
  - 连接状态显示
  - Anthropic 风格深色主题 UI
- 🤖 **GitHub Actions 自动构建**
  - 每次提交自动构建 APK
  - 自动发布到 GitHub Releases
  - 无需本地安装 Android SDK

### Changed / 变更
- 📦 新增 `android/` 目录存放 Flutter 项目
- 📁 APK 构建产物存放于 `android/apk/` 目录

### Technical / 技术
- Flutter 3.24.5 + Dart 3.5.4
- Material Design 3 深色主题
- WebSocket 通信协议

---

## [1.2.0] - 2026-02-02

### Added / 新增
- 🌐 **ngrok 隧道支持** - 解决移动端 PWA 安装问题
  - 使用 ngrok 提供的 HTTPS 隧道和有效 SSL 证书
  - 托盘菜单新增 ngrok 开关选项
  - 自动复制 ngrok URL 到剪贴板
  - 显示更清晰的连接状态信息
- 📦 新增 pyngrok 和 pyyaml 依赖

### Fixed / 修复
- 🐛 修复证书生成中 `ipaddress.IPv4Address()` 使用问题
- 🐛 修复 HTTPS 服务器启动时的证书加载问题

### Changed / 变更
- 🔄 菜单项重新排序：ngrok 选项置顶以便快速访问
- 📝 "Enable HTTPS" 改名为 "Enable HTTPS (local)" 以区分本地和 ngrok HTTPS

### Technical / 技术
- ngrok 隧道使用 `bind_tls=True` 强制 HTTPS 连接
- 支持动态 URL 获取和显示

---

## [1.1.0] - 2026-02-02

### Added / 新增
- 🔒 HTTPS 服务器支持（自签名证书），启用 PWA 安装功能
- 📲 PWA (Progressive Web App) 完整支持
  - Service Worker 注册和缓存
  - beforeinstallprompt 事件处理
  - 应用安装监听
- 🔐 托盘菜单新增 HTTPS 开关选项
- 📜 自动生成自签名 SSL 证书（支持常见局域网 IP）

### Changed / 变更
- ✨ manifest.json 新增 `id` 字段，提升浏览器识别能力
- 🌐 显示 IP 时优先显示 HTTPS 地址（如已启用）
- 📦 新增 cryptography 依赖用于证书生成

### Fixed / 修复
- 🐛 修复 Service Worker 未注册导致 PWA 无法安装的问题
- 🐛 修复移动端浏览器因缺少 HTTPS 而拒绝安装 PWA 的问题

### Technical / 技术
- 证书支持多种常见内网 IP（192.168.137.1, 192.168.0.1, 192.168.1.1, 10.0.0.1）
- 证书有效期 10 年，自动生成并复用
- 支持 OpenSSL 和 cryptography 两种证书生成方式

---

## [1.0.0] - 2026-01-21

### Added / 新增
- 🎉 初始版本发布
- 📱 Web 客户端：手机浏览器直接访问，无需安装 App
- 💻 PC 端系统托盘应用
- 🔗 WebSocket 实时通信
- 📝 文本整包传输到电脑光标处
- ⚡ 开机自启功能
- 🔄 自动断线重连
- 🎨 Anthropic 风格 UI 设计
- 📊 连接状态实时显示
- 🖥️ 设备名称显示

### Features / 功能
- 单实例运行保护
- 托盘菜单：IP 显示、同步开关、开机自启
- 固定高度 Panel，适配手机浏览器
- 深色主题界面

### Technical / 技术
- Python 后端 + 原生 JavaScript 前端
- PyInstaller 单文件打包
- HTTP + WebSocket 双协议服务

---

## [Unreleased] - 开发中

### Planned / 计划中
- [ ] 多语言支持
- [ ] 自定义快捷键
- [ ] 历史记录功能
- [ ] 剪贴板同步
- [ ] macOS 支持
