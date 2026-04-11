# Voicing 项目会话日志

> 记录每次开发会话的进度和结果

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
