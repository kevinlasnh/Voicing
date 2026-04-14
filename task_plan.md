# Voicing 项目任务计划

> 项目：Voicing - 手机语音输入到电脑工具
> 最后更新：2026-04-11

---

## 项目目标

**核心功能**：让用户用手机语音输入，文字实时出现在电脑光标处

**当前版本**：v2.5.1

---

## 当前状态

### 已完成功能 ✅

| 功能模块 | 状态 | 说明 |
|---------|------|------|
| WebSocket 实时通信 | ✅ | PC 端 9527 端口 |
| UDP 自动发现 | ✅ | 端口 9530，每 2 秒广播 |
| Android 文字输入 | ✅ | 支持语音输入法 |
| 自动发送功能 | ✅ | 始终启用，语音输入自动发送 |
| 撤回功能 | ✅ | 恢复上次发送的文本 |
| PC 端自动输入 | ✅ | 剪贴板 + Ctrl+V 方案 |
| Windows 11 托盘菜单 | ✅ | Fluent Design 风格 |
| 日志系统 | ✅ | %APPDATA%\Voicing\logs\ |
| 开机自启 | ✅ | Windows 注册表 |
| 心跳断线重连 | ✅ | 15s ping / 30s 超时 / 指数退避 |
| Android 生命周期处理 | ✅ | paused 停心跳，resumed 验证连接 |
| 异步非阻塞输入 | ✅ | asyncio.to_thread() |
| Android 前台强制重连 | ✅ | resumed 后直接重建 WebSocket |
| Android 连接超时保护 | ✅ | 8 秒 connect timeout |
| Android 旧连接回调隔离 | ✅ | generation 防 stale socket |
| 同 IP UDP 恢复重连 | ✅ | 未连接时广播也可触发恢复 |
| PC 热点 IP 动态广播 | ✅ | 每轮 UDP 广播前重新检测热点 IP |
| Android 恢复策略测试 | ✅ | `connection_recovery_policy_test.dart` |
| PC 广播恢复测试 | ✅ | `pc/tests/test_network_recovery.py` |
| UI 设计 token 系统 | ✅ | AppSpacing + AppColors |
| 触摸反馈 | ✅ | InkWell 涟漪 + PC 端 pressed state |
| 菜单分组卡片 | ✅ | iOS grouped list 风格 |
| 键盘支持 | ✅ | Escape 关闭 PC 菜单 |

### 待完成任务 🚧

**新增审计任务（2026-04-14）**
- 全面核对仓库内容与文档是否仍反映当前代码状态
- 检查 Android APK 与 Windows EXE 源码是否保持协议/状态机一致
- 验证当前仓库在本机环境下的可测试性、可构建性与稳定性
- 输出优化建议与优先级

### 最近完成

| 日期 | 任务 | 版本 |
|------|------|------|
| 2026-04-14 | 自动发送硬编码启用、Android UI 优化、PC 菜单首次右键修复 | v2.5.1 |
| 2026-04-14 | 协议契约测试、Android 架构拆分、CI/文档修复、自动发送开关间距优化 | v2.5.0 |
| 2026-04-11 | 修复休眠唤醒后的假断连，补充 Android / PC 连接恢复测试 | v2.4.2 |
| 2026-04-08 | UI 优化（设计常量、触摸反馈、菜单分组、键盘支持） | v2.4.1 |
| 2026-04-08 | 全栈优化（断连修复、异步阻塞、代码清理、图标圆形） | v2.4.0 |
| 2026-02-05 | README 图标圆形显示 | - |
| 2026-02-04 | Android 网络权限 + EXE 图标修复 | v2.3.1 |
| 2026-02-04 | 品牌重命名 + 托盘优化 | v2.3.0 |

---

## 计划阶段

### Phase 1: llmdoc 文档系统初始化 ✅（已移除）
- [x] 运行 scout agents 探索代码库
- [x] 生成 11 篇文档
- [x] v2.5.1 后移除 llmdoc 系统，保留 README 作为唯一文档入口

### Phase 2: v2.4.0 全栈优化 ✅
- [x] Android 断连 Bug 修复（心跳 + 生命周期 + 指数退避）
- [x] PC 端异步阻塞修复（asyncio.to_thread）
- [x] 代码质量（裸 except、状态锁、UDP Event、删除 pystray 冗余代码）
- [x] CI/配置修复（Python 3.12、依赖锁定、.gitignore）
- [x] EXE 图标裁剪为圆形

### Phase 3: v2.4.1 UI 优化 ✅
- [x] Flutter: AppSpacing/AppColors 设计常量
- [x] Flutter: 间距对齐 4px 网格
- [x] Flutter: 触摸目标 44pt + InkWell 涟漪
- [x] Flutter: 菜单改分组卡片 + Divider
- [x] Flutter: 动画统一 250ms
- [x] PC: 菜单按压反馈 + Escape 键 + 间距优化

### Phase 4: v2.4.2 连接恢复修复 ✅
- [x] Android: resumed 后强制重建 WebSocket
- [x] Android: WebSocket connect timeout
- [x] Android: stale socket generation 隔离
- [x] Android: 同 IP UDP 广播恢复重连
- [x] PC: 每轮 UDP 广播刷新热点 IP
- [x] 新增 Android / PC 连接恢复测试脚本
- [x] 更新 README / DEV_STATUS / llmdoc / CHANGELOG

### Phase 5: GitHub Actions 发布 ✅
- [x] 提交 `v2.4.2` 修复与文档更新
- [x] 推送 `main`
- [x] 推送 `v2.4.2` 标签
- [x] 等待 GitHub Actions 自动构建并创建 Release

### Phase 6: 2026-04-14 全仓审计与 v2.5.0 优化 ✅
- [x] 校验仓库结构、文档、版本号与依赖基线
- [x] 审查 Android / PC 双端通信协议、状态机与功能耦合
- [x] 协议契约测试、Android 架构拆分与 UI 细节修复
- [x] 运行静态检查、单测与源码级修复验证
- [x] 输出稳定性结论、问题清单与优化建议

---

## 错误记录

| 错误 | 尝试 | 解决方案 |
|------|------|----------|
| Android 待机断连 | 1 | 添加心跳 + 生命周期处理 + 指数退避 |
| Android 息屏恢复后仍显示未连接 | 1 | resumed 强制重连 + connect timeout + UDP 同 IP 恢复 |
| PC async 阻塞 | 1 | type_text 改用 asyncio.to_thread |
| CI Python 3.14 不稳定 | 1 | 降级到 3.12 |
| 本机 Java 25 导致 Flutter release 构建失败 | 1 | 本地不再做 release 构建，改由 GitHub Actions 构建 |

---

## 重要决策

| 决策 | 原因 | 日期 |
|------|------|------|
| 使用剪贴板方式实现输入 | 支持 Unicode 兼容性 | v1.0 |
| 移除 Web 端功能 | 专注 PC + Android 双端体验 | v2.0 |
| UDP 广播自动发现 | 无需手动配置 IP | v2.0 |
| 自定义应用图标 | 品牌识别度 | v2.2 |
| 应用重命名 Voice Coding → Voicing | 更现代简洁的品牌名 | v2.3 |
| 移除 pystray 依赖 | 项目已完全使用 PyQt5 | v2.4.0 |
| 自动发送始终启用 | 降低使用门槛，语音输入体验一致 | v2.5.1 |
| 移除 llmdoc 文档系统 | README 已足够，llmdoc 维护成本高于收益 | v2.5.1 |
| 引入共享协议契约 + 双端契约测试 | 降低 Android / PC 消息结构漂移风险 | v2.5.0 |
| Android 连接状态机从 UI 中拆出 | 降低 `main.dart` 复杂度并便于维护 | v2.5.0 |

---

## 下一步

**项目已稳定，v2.5.1 已完成**

主要文档入口：`README.md`
