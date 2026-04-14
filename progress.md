# Voicing 项目会话日志

> 记录每次开发会话的进度和结果

---

## 2026-04-14 会话（下午）

### 会话目标
移除自动发送开关、UI 优化、PC 菜单首次右键修复、CI 修复、README 全面优化

### 执行步骤

#### Step 1: 移除自动发送开关，硬编码为始终启用 ✅
- Controller 删除 SharedPreferences 依赖、setShadowModeEnabled()、偏好存取方法
- `_shadowModeEnabled` 硬编码为 `true`（`final`）
- UI 删除菜单中的自动发送开关项和 `_buildSwitchMenuItem()` 方法
- pubspec.yaml 移除 `shared_preferences: ^2.5.3`，净减 15 个传递依赖

#### Step 2: Android UI 优化 ✅
- 新增"连接中..."状态显示（橙色圆点 + 文字）
- 底部提示改为"语音自动发送 · 回车手动发送"
- 硬编码 `Colors.white` 替换为 `AppColors.textPrimary` 主题 token
- 新增 `AppTextStyles` 常量（label/body/hint），消除重复文字样式
- 菜单项和菜单按钮添加显式涟漪反馈色（splashColor/highlightColor）

#### Step 3: PC 端托盘菜单首次右键卡顿修复 ✅
- 问题：Qt 延迟渲染，首次 show() 才编译 stylesheet/计算布局
- 修复：`ModernTrayIcon.__init__()` 中添加菜单预热渲染（屏幕外 show + 50ms 后 hide）

#### Step 4: CI 修复（阿里云 maven 镜像 502）✅
- 移除 `build.gradle` 中的阿里云镜像配置
- 移除 `settings.gradle` 中 `pluginManagement.repositories` 的阿里云配置
- CI 现在直接使用 Google/Maven Central 官方源

#### Step 5: README 全面优化 ✅
- 安装 `crafting-effective-readmes` 和 `readme-blueprint-generator` 全局 skill
- 按 OSS 最佳实践全面重写 README
- 新增 ASCII 架构图、功能表格、FAQ 按频率排列

### 验证结果
- Android: `flutter analyze` 0 issues, `flutter test` 9/9 通过
- PC: `py_compile` 通过, `unittest` 7/7 通过
- GitHub Actions: v2.5.1 构建成功（APK 20MB + EXE 49MB）

### 当前状态
- 代码：v2.5.1 已发布
- Git：main 与 origin/main 同步
- Release: https://github.com/kevinlasnh/Voicing/releases/tag/v2.5.1

---

## 2026-04-14 会话（上午）

### 会话目标
全面检查仓库当前内容是否仍然最新，核对 Android APK 与 Windows EXE 源码是否保持稳定耦合，并基于实际代码与测试结果给出优化建议

### 执行步骤

#### Step 1: 恢复上下文并建立审计范围 ⏳
- 读取 `task_plan.md`、`findings.md`、`progress.md`
- 确认仓库由 `android/voice_coding`（Flutter Android）与 `pc`（Python/PyQt5 Windows）构成
- 确认存在少量未提交本地变更：`.claude/settings.local.json`、`android/.../local.properties`、`pc/VoiceCoding.spec`
- 已登记新的 Phase 6 审计任务，准备继续做版本、协议、测试与优化检查

#### Step 2: 版本基线与协议结构排查 ⏳
- 确认本地 `main` 与 `origin/main` 同步，远端最新标签仍为 `v2.4.2`
- 确认双端通过 UDP `9530` + WebSocket `9527` + JSON 消息类型耦合，没有共享协议层
- 核对消息类型发现：PC 端定义 `sync_disabled`，Android 端未显式处理该分支
- 核对文档与依赖声明发现：`android/README.md` 的 Dart 版本描述与 `pubspec.yaml` 不完全一致，`pubspec.lock` 中 `flutter_launcher_icons` 已解析到 `0.14.4`

#### Step 3: 直接修复低风险问题并复验 ✅
- **协议修复**：PC `sync_disabled` 增加 `sync_enabled: false`；Android 显式处理 `sync_disabled`
- **CI 修复**：`.github/workflows/release.yml` 的 changelog 提取改为 `vX.Y.Z` → `CHANGELOG` 中 `X.Y.Z`，并在缺失条目时 fail fast
- **仓库治理**：将 `android/voice_coding/android/local.properties` 加入 `.gitignore`，并从 Git 跟踪中移除（保留本地文件）
- **文档修复**：同步修正 README / Android README / llmdoc 中的错误命令、旧路径、版本说明与本机配置描述
- **验证结果**：
  - Android: `flutter test test/connection_recovery_policy_test.dart` → 4/4 通过
  - Android: `flutter analyze --no-fatal-infos --no-fatal-warnings` → 仍为 16 条 info，无 error / warning
  - PC: `python -m unittest tests.test_network_recovery` → 3/3 通过
  - PC: `python -m py_compile voice_coding.py network_recovery.py` → 通过

#### Step 4: 完成 v2.5.0 优化并通过发布前回归 ✅
- 新增共享协议契约文件 `protocol/voicing_protocol_contract.json`
- 新增 PC `voicing_protocol.py` 与 `tests/test_protocol_contract.py`
- Android 新增 `app_theme.dart`、`app_logger.dart`、`voicing_protocol.dart`、`voicing_connection_controller.dart`
- Android `main.dart` 拆分为 UI 组合层，移除生产代码中的 `print`
- 修复 Android 菜单中“自动发送”开关与文字间距过近的问题
- 升级并对齐依赖约束：
  - Android: `web_socket_channel ^2.4.5`、`shared_preferences ^2.5.3`、`flutter_launcher_icons ^0.14.4`
  - PC: `Pillow ~=12.2.0`、`pyinstaller ~=6.19.0`、`pyperclip ~=1.11.0`、`PyQt5 ~=5.15.11`
- 最终回归结果：
  - Android: `flutter pub get` → 通过
  - Android: `flutter test` → 9/9 通过
  - Android: `flutter analyze --no-fatal-infos --no-fatal-warnings` → 0 issue
  - PC: `python -m pip install -r requirements.txt` → 通过，环境已对齐约束
  - PC: `python -m unittest discover -s tests` → 7/7 通过
  - PC: `python -m py_compile voice_coding.py network_recovery.py voicing_protocol.py` → 通过

---

## 2026-04-11 会话

### 会话目标
修复 Android 息屏唤醒后的假断连，补充推送前测试，更新全部相关文档并准备走 GitHub Actions 发布

### 执行步骤

#### Step 1: 复盘根因并修复连接状态机 ✅
- 确认问题主要在 Android 端，而不是文本封包本身
- **Android**：`resumed` 后强制重建连接，不再信任休眠前旧 socket
- **Android**：WebSocket 增加 8 秒连接超时
- **Android**：加入 connection generation，忽略 stale socket 的 `onDone` / `onError`
- **Android**：同 IP UDP 广播在未连接时也能触发恢复重连
- **PC**：UDP 广播每轮重新检测热点 IP，避免广播旧地址

#### Step 2: 补充测试脚本 ✅
- 新增 `android/voice_coding/lib/connection_recovery_policy.dart`
- 新增 `android/voice_coding/test/connection_recovery_policy_test.dart`
- 新增 `pc/network_recovery.py`
- 新增 `pc/tests/test_network_recovery.py`

#### Step 3: 推送前验证 ✅
- Android: `flutter test test/connection_recovery_policy_test.dart` → **4/4 通过**
- Android: `flutter analyze --no-fatal-infos --no-fatal-warnings` → **无 error，仅剩 info**
- PC: `python -m unittest tests.test_network_recovery` → **3/3 通过**
- PC: `python -m py_compile voice_coding.py network_recovery.py` → **通过**

#### Step 4: 文档与版本更新 ✅
- 版本号更新：Android `2.4.2+1`，PC `APP_VERSION = 2.4.2`
- 更新 `CHANGELOG.md` 增加 `2.4.2`
- 更新 `README.md`、`android/README.md`、`DEV_STATUS.md`
- 更新 `llmdoc` 中连接、架构、开发和发布文档

### 当前状态

- 代码修复完成
- 推送前测试完成
- 文档已同步
- Git 提交：`577c573 fix: 修复息屏唤醒后的连接恢复并补充测试`
- 标签：`v2.4.2`
- GitHub Actions：`Create Release` run `24280956312` 全部成功
- Release: https://github.com/kevinlasnh/Voicing/releases/tag/v2.4.2

---

## 2026-04-08 会话

### 会话目标
全栈优化 + UI 优化，修复致命断连 bug，项目推至稳定状态

### 执行步骤

#### Step 1: 全面代码审查 ✅
- 并行派出 3 个子代理审查 PC 端、Android 端、CI/配置
- 发现 15 个优化点（3 Critical / 4 High / 5 Medium / 3 Low）
- 定位断连 bug 根因：无心跳、无 paused 生命周期处理、无连接验证

#### Step 2: v2.4.0 全栈优化 ✅
- **Android 断连修复**：心跳（15s ping / 30s 超时）+ 生命周期 + 指数退避重连
- **PC 异步阻塞修复**：type_text → asyncio.to_thread()
- **代码清理**：5 处裸 except、AppState 加锁、UDP 改 Event、删除 pystray 冗余代码（~120行）
- **CI 修复**：Python 3.14→3.12、依赖锁定 ~=、.gitignore 补充
- **EXE 图标**：裁剪为圆形，重新生成多尺寸 ICO
- Commit: `8800992`，Tag: `v2.4.0`，CI 构建成功

#### Step 3: v2.4.1 UI 优化 ✅
- 读取 3 个 UI Skill（ui-ux-pro-max、flutter-building-layouts、ui-mobile）提取规范
- **Flutter**：AppSpacing/AppColors 常量、4px 网格、44pt 触摸目标、InkWell 涟漪、菜单分组卡片、动画统一 250ms
- **PC**：菜单按压反馈、Escape 键关闭、项间距 2→4px
- flutter analyze: 0 error, 16 info（全为 avoid_print / prefer_const）
- Commit: `dd6874a`，Tag: `v2.4.1`，CI 构建中

### 结果

**两个版本已发布**：
- v2.4.0: https://github.com/kevinlasnh/Voicing/releases/tag/v2.4.0
- v2.4.1: https://github.com/kevinlasnh/Voicing/releases/tag/v2.4.1

**代码统计**：
- v2.4.0: 8 files, +154 -201 (net -47 行)
- v2.4.1: 3 files, +227 -163 (net +64 行)

### 项目状态
**稳定** — 用户确认软件运行正常，无待完成任务

---

## 2026-02-05 会话 (下午)

### 会话目标
README 图标圆形显示优化

### 执行步骤

#### Step 1: 分析需求 ✅
- 用户查看 README 中的图标显示
- 确认图标目前是正方形显示
- 需求：将图标裁剪为圆形

#### Step 2: 修改 README ✅
- 文件：`README.md` 第 5 行
- 修改：添加 `style="border-radius: 50%;"` 到 img 标签
- 效果：图标在 GitHub 上显示为圆形

### 结果

**修改内容**：
```html
<!-- 修改前 -->
<img src="android/voice_coding/assets/icons/icon_1024.png" width="180" alt="Voicing App Icon">

<!-- 修改后 -->
<img src="android/voice_coding/assets/icons/icon_1024.png" width="180" alt="Voicing App Icon" style="border-radius: 50%;">
```

### Git 状态
```
M README.md
```

### 下一步
等待提交并推送到 GitHub

---

## 2026-02-05 会话 (上午)

### 会话目标
初始化 llmdoc 文档系统

### 执行步骤

#### Step 0: 获取项目结构 ✅
- 读取 `README.md` - 项目概述
- 读取 `CLAUDE.md` - 开发规范
- 读取 `DEV_STATUS.md` - 当前开发状态
- 读取 `pubspec.yaml` - Android 依赖
- 读取 `requirements.txt` - PC 依赖

#### Step 1: 运行 Scout Agents ✅
并行执行 5 个 scout agents：
- `scout-pc-architecture.md` - PC 端架构调查
- `scout-android-architecture.md` - Android 端架构调查
- `scout-communication-protocol.md` - 通信协议调查
- `scout-build-deployment.md` - 构建部署调查
- `scout-ui-design.md` - UI 设计规范调查

#### Step 2: 分析核心概念 ✅
识别出以下核心概念（用户全部选中）：
- 通信协议
- PC 端架构
- Android 端架构
- 构建部署

#### Step 3: 生成基础文档 ✅
- `llmdoc/overview/project-overview.md` - 项目概览
- `llmdoc/reference/coding-conventions.md` - 编码规范
- `llmdoc/reference/git-conventions.md` - Git 规范

#### Step 4: 生成核心概念文档 ✅

**通信协议**：
- `llmdoc/architecture/communication-protocol.md`
- `llmdoc/guides/connection-workflow.md`

**PC 端架构**：
- `llmdoc/architecture/pc-architecture.md`
- `llmdoc/guides/pc-development.md`

**Android 端架构**：
- `llmdoc/architecture/android-architecture.md`
- `llmdoc/guides/android-development.md`

**构建部署**：
- `llmdoc/architecture/build-deployment.md`
- `llmdoc/guides/release-workflow.md`

#### Step 5: 清理临时文件 ✅
- 删除 `llmdoc/agent/scout-*.md`
- 删除 `llmdoc/agent/` 目录

#### Step 6: 生成最终索引 ✅
- `llmdoc/index.md` - 文档系统索引入口

### 结果

**生成文档统计**：
- Overview: 1 篇
- Architecture: 4 篇
- Guides: 4 篇
- Reference: 2 篇
- **总计：11 篇文档**

### Git 状态
```
M .claude/settings.local.json
?? llmdoc/
```

### 下一步
等待用户新功能或 bug 修复需求

---

## 2026-02-04 会话

### 完成内容
- v2.3.1 发布
- Android 网络权限修复
- Windows EXE 图标修复
- ICO 多尺寸文件生成

---

## 历史版本

| 版本 | 日期 | 主要内容 |
|------|------|----------|
| v2.4.1 | 2026-04-08 | UI 优化（设计常量、触摸反馈、菜单分组） |
| v2.4.2 | 2026-04-11 | 修复休眠唤醒后的假断连，补充连接恢复测试 |
| v2.4.0 | 2026-04-08 | 全栈优化（断连修复、异步阻塞、代码清理） |
| v2.3.1 | 2026-02-04 | 网络权限 + EXE 图标修复 |
| v2.3.0 | 2026-02-04 | 重命名 Voicing + 托盘优化 |
| v2.2.0 | 2026-02-04 | 自定义应用图标 |
| v2.1.0 | 2026-02-03 | 自动发送功能 |
| v2.0.0 | 2026-02-03 | UDP 自动发现 + 架构简化 |
