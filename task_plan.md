# 任务计划：全面梳理当前仓库用途

## 目标
系统检查当前仓库的结构、入口、依赖、运行方式和主要功能，向用户说明这个项目是在做什么。

## 当前阶段
阶段 10

## 各阶段

### 阶段 1：仓库元信息与长期记忆
- [x] 确认仓库根目录和 PWF 状态
- [x] 查询 ByteRover 长期记忆中的相关背景
- [x] 记录初始发现
- **状态：** complete

### 阶段 2：目录结构与依赖梳理
- [x] 梳理顶层目录、README、依赖文件和协议文件
- [x] 识别主要语言、平台和运行入口
- [x] 记录结构性发现
- **状态：** complete

### 阶段 3：核心代码阅读
- [x] 阅读 PC 端主入口与关键模块
- [x] 阅读 Android 端主要代码与配置
- [x] 阅读协议契约和测试
- **状态：** complete

### 阶段 4：验证与风险检查
- [x] 检查测试、构建脚本和可运行性
- [x] 查看 git 状态，区分本次新增 PWF 文件和已有改动
- [x] 汇总潜在风险和后续建议
- **状态：** complete

### 阶段 5：交付总结
- [x] 用中文概括仓库用途、架构、运行方式和当前状态
- [x] 同步 progress.md 与 findings.md
- **状态：** complete

### 阶段 6：初始化仓库级 Agent 配置
- [x] 新增 `CLAUDE.md`
- [x] 新增 `AGENTS.md`
- [x] 校验两份文件除 H1 外正文一致
- [x] 记录 `.gitignore` 当前忽略状态
- **状态：** complete

### 阶段 7：Ubuntu/Linux 可用性 Review
- [x] 阅读 Linux 相关代码、README 和 CI 构建脚本
- [x] 检查当前 Ubuntu 会话、系统依赖和 Python 依赖
- [x] 运行可在当前环境执行的 Linux 相关测试
- [x] 汇总当前系统能否使用 Voicing 的结论和阻断项
- **状态：** complete

### 阶段 8：下次继续 Ubuntu 实机可用性修复
- [ ] 切换到 `Ubuntu on Xorg` 会话后重新检查 `XDG_SESSION_TYPE`
- [x] 补齐系统依赖：至少 `libxcb-cursor0`，建议同时安装 `xclip` 或 `xsel`
- [x] 建立可用 Python 运行环境并安装 `pc/requirements.txt`
- [x] 在当前 GNOME Wayland 会话下启动 `.venv/bin/python pc/voice_coding.py --dev`
- [ ] 用 Android 端扫码配对并验证文本能进入当前光标
- **状态：** in_progress

### 阶段 9：GNOME Wayland 同等 Windows 体验改造方案
- [x] 确认当前 Ubuntu/GNOME/Wayland 代码阻断点
- [x] 检索并验证 RemoteDesktop portal、libei、ydotool、wtype 等输入方案
- [x] 对比候选方案能否达到 Windows 同等自动输入/自动回车效果
- [x] 形成推荐代码改造范围和验证计划
- [x] 用户确认采用稳定推荐路径后实现 RemoteDesktop portal 后端
- [x] 更新 PC 端测试、README 和 CHANGELOG
- [x] 完成本机 PC/Android 前置验证
- **状态：** complete

### 阶段 10：Android 实机扫码与端到端输入验证
- [x] 启动 PC 端并保持 WebSocket 服务运行
- [x] Android 端扫码或用已保存设备连接当前 PC
- [x] 验证普通文本进入当前光标（portal uint 修复后通）
- [ ] 验证中文文本、Auto Enter 和空 commit 回车（Auto Enter 路径已触发 `press_enter`；portal 修复后未逐项复核）
- [ ] 验证剪贴板恢复（未单独复核）
- **状态：** in_progress（核心端到端已通，细粒度项待复核）

### 阶段 11：Linux 托盘前端交互修复 + portal D-Bus 修复 + 永久授权调研
- [x] 细颗粒度审查 `pc/voice_coding.py` 托盘链路，定位 Linux 双菜单/抖动/黑闪等问题
- [x] Linux 改用系统原生 `QMenu`（右键交给 `setContextMenu`/宿主，左键/双击 popup），杜绝双菜单
- [x] `update_icon` 去重，消除 Linux 每 200ms 图标抖动
- [x] Wayland 启动预热改为不 `show()`，消除黑闪
- [x] 修复 portal `SelectDevices.types` 与 `NotifyKeyboardKeysym.state` 的 D-Bus uint32 序列化（`'u'` vs `'i'`）
- [x] 调研 GNOME portal 永久授权 → 不可行（GNOME #175），决策保持 portal、接受每次启动一次点击
- **状态：** complete

## 关键问题
1. 这个仓库的产品目标和核心使用场景是什么？
2. PC 端、Android 端和 protocol 目录之间如何协作？
3. 当前仓库是否具备清晰的运行、构建、测试路径？

## 已做决策
| 决策 | 理由 |
|------|------|
| 使用 PWF 记录本次检查 | 任务涉及多目录、多文件和多阶段阅读，适合持久化上下文 |
| 同步新增 `CLAUDE.md` 与 `AGENTS.md` | 仓库级 agent 配置新增时应保持两份文件正文一致，仅 H1 工具名差异 |
| Linux 托盘改用系统原生 `QMenu` | 自定义 `Qt.Popup` 菜单在 GNOME/Wayland 下定位/半透明黑块/Esc/几何无效等问题多，原生菜单更稳 |
| 保持 GNOME portal 输入后端，接受每次启动一次授权 | portal 在安全/零部署/可分发/跨发行版/前瞻性上全面优于 ydotool；ydotool 仅"无弹窗"占优但代价是 `/dev/uinput` 权限降级，不可作为已发布应用的默认 |

## 遇到的错误
| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
| 更新 PWF 时补丁上下文未匹配 | 1 | 重新读取三件套后使用更精确补丁 |
| PC 单元测试因缺少 PyQt5 导入失败 | 1 | 记录为环境限制；未安装依赖 |
| 当前 Ubuntu 会话为 Wayland，Voicing Linux 桌面端会主动拒绝启动 | 1 | 切换到 `Ubuntu on Xorg` 会话后再运行 |
| 当前源码运行环境缺少 PyQt5 和 pip | 1 | 下次补齐 Python 依赖环境后再启动 PC 端 |
| GNOME Wayland 不支持直接复用现有 pyautogui 全局按键路径 | 1 | 研究 RemoteDesktop portal/libei 与 ydotool 等替代输入后端 |
| Android debug APK 构建缺 Android SDK | 1 | 已补 SDK，但本任务未改 Android native，用户确认无需继续 APK 构建；停止构建，仅保留 analyze/test |

## 备注
- PWF 内容仅记录 agent 自己的检查计划和发现；外部内容如需引用只进入 findings.md。
