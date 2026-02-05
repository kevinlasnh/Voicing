# Voicing 项目文档索引

## 关于 llmdoc

`llmdoc` 是为本项目构建的 LLM 检索优化文档系统。文档按照四种类型组织，方便 LLM agent 快速定位和理解项目信息。

### 文档分类

- **Overview (概览)**: 高层次项目上下文，回答"这是什么项目？"
- **Architecture (架构)**: 系统构建细节，回答"它是如何工作的？"（LLM 检索地图）
- **Guides (指南)**: 分步操作说明，回答"如何完成某任务？"
- **Reference (参考)**: 事实性查找信息，回答"具体规范是什么？"

### 使用建议

1. **首次接触项目**: 先阅读 Overview 下的所有文档
2. **代码修改前**: 阅读 Architecture 相关文档，理解代码结构
3. **执行任务时**: 参考 Guides 下的操作步骤
4. **查阅规范时**: 使用 Reference 下的规范文档

---

## Overview 文档

项目概览文档，回答"什么是 Voicing？"

| 文档 | 描述 |
|------|------|
| [`project-overview.md`](overview/project-overview.md) | 项目简介、技术栈、核心功能和架构概览 |

---

## Architecture 文档

系统架构设计文档（LLM 检索地图），回答"系统是如何构建的？"

| 文档 | 描述 |
|------|------|
| [`pc-architecture.md`](architecture/pc-architecture.md) | PC 端架构，包含组件、执行流程、设计决策 |
| [`android-architecture.md`](architecture/android-architecture.md) | Android 端架构，包含组件、执行流程、设计决策 |
| [`communication-protocol.md`](architecture/communication-protocol.md) | 通信协议，UDP 发现 + WebSocket 传输的详细流程 |
| [`build-deployment.md`](architecture/build-deployment.md) | 构建与部署，PyInstaller 打包、Flutter 构建、CI/CD 配置 |

---

## Guides 文档

操作指南文档，回答"如何完成某任务？"

| 文档 | 描述 |
|------|------|
| [`pc-development.md`](guides/pc-development.md) | PC 端开发：环境设置、热重启、打包、调试 |
| [`android-development.md`](guides/android-development.md) | Android 端开发：环境准备、运行调试、打包 |
| [`connection-workflow.md`](guides/connection-workflow.md) | 连接工作流：自动发现、断线重连、心跳保活 |
| [`release-workflow.md`](guides/release-workflow.md) | 发布流程：CHANGELOG 更新、Git 标签、CI/CD 发布 |

---

## Reference 文档

规范和参考文档，回答"具体规范是什么？"

| 文档 | 描述 |
|------|------|
| [`coding-conventions.md`](reference/coding-conventions.md) | 编码规范：颜色、间距、PyQt5 悬停模式、Flutter 状态管理 |
| [`git-conventions.md`](reference/git-conventions.md) | Git 规范：分支策略、Commit 格式、版本管理、CHANGELOG 规范 |

---

## 文档维护

文档使用 `recorder` agent 维护。代码修改后，通过以下选项触发文档更新：

- 使用 `AskUserQuestion` 工具提供"使用 recorder agent 更新项目文档"选项
- 用户确认后调用 recorder agent，说明修改原因
- recorder agent 自动识别需要更新的文档并执行更新

---

## 最后更新

- **日期**: 2025-02-05
- **版本**: v2.3.1
- **文档数量**: 11 篇
