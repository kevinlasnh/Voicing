# Git 规范

## 1. 分支策略

- **main 分支**：唯一生产分支，始终保持稳定可发布状态
- **开发流程**：直接在 main 分支开发，小步提交
- **发布流程**：通过 GitHub Actions 自动构建，创建 Git Tag 触发发布

## 2. Commit 规范

### 消息格式

```
<type>: <subject>
```

### 类型前缀

| 前缀 | 用途 | 示例 |
|------|------|------|
| `feat:` | 新功能 | `feat: 实现影随模式第一版` |
| `fix:` | Bug 修复 | `fix: 添加Android网络权限，修复APK无法连接问题` |
| `refactor:` | 重构（不改变功能） | `refactor: 影随模式改为 1:1 完全同步` |
| `chore:` | 构建/配置/依赖 | `chore: 移除动态ICO转换步骤` |
| `docs:` | 文档更新 | `docs: 更新 v2.3.1 发布文档` |
| `debug:` | 调试代码（临时） | `debug: 添加影随模式调试日志` |
| `fix(ci):` | CI/CD 修复 | `fix(ci): 移除 gradle.properties 中的本地代理配置` |

### 规则

- 使用简体中文描述
- 首字母小写
- 不以句号结尾
- 空格分隔前缀和内容

## 3. 版本管理

### 语义化版本

```
MAJOR.MINOR.PATCH
```

- **MAJOR**：不兼容的重大变更（如 v1.x -> v2.0）
- **MINOR**：向下兼容的新功能（如 v2.2 -> v2.3）
- **PATCH**：向下兼容的 Bug 修复（如 v2.3.0 -> v2.3.1）

### Git 标签

- 格式：`v<version>`，如 `v2.3.1`
- 创建时机：发布时通过 GitHub Actions 自动创建
- 标签位置：指向发布 commit

## 4. CHANGELOG 规范

### 更新时机

**以下情况必须立即更新 CHANGELOG.md：**
- 代码有功能改动（新增、修改、删除功能）
- Bug 修复
- UI/样式变更
- 配置文件变更
- 依赖库版本变更

### 格式模板

```markdown
## [VERSION] - YYYY-MM-DD

### [分类]

- **标题** - 描述
  - 详细说明
```

### 分类

- `### 关键修复` 或 `### 修复问题`
- `### 新增功能`
- `### 优化改进`
- `### 技术改进`
- `### 文档更新`
- `### Bug 修复`

## 5. 源码参考

- **CHANGELOG**: `CHANGELOG.md` - 版本发布记录
- **Commit 历史**: 运行 `git log --oneline -20` 查看最近提交
- **CI 配置**: `.github/workflows/release.yml` - 自动发布流程
