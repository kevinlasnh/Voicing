# 任务计划：全面梳理当前仓库用途

## 目标
系统检查当前仓库的结构、入口、依赖、运行方式和主要功能，向用户说明这个项目是在做什么。

## 当前阶段
阶段 41（complete）

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

### 阶段 12：自定义菜单美化 + 原生菜单分隔条 + QR 闪烁迭代
- [x] 自定义 Fluent 菜单（Win/macOS）宽度收紧到 sizeHint（随最长文字自适应）+ 去分隔条（本机 Linux 走原生菜单，无法肉眼确认，待 Windows 实机复核）
- [x] Linux 原生菜单去分隔条（`_setup_native_context_menu` 删 4 个 `addSeparator()`）—— 用户确认无横条 ✅
- [x] QR「下方第二个 QR」闪烁修复（收尾先 hide 解除 surface 映射再 resize/show）—— 用户确认下方闪动消失 ✅
- [ ] Linux 原生菜单宽度仍不自适应（用户反馈，待复核具体表现）
- [x] QR 到达中心时自身闪动一次：用户选择砍掉飞入，已改为中心直接出现/直接关闭，待用户手动启动肉眼确认
- **状态：** in_progress

### 阶段 13：整体前端逻辑 Review
- [x] 审查 PC PyQt 托盘、菜单、QR 和 WebSocket 前端信号链路
- [x] 审查 Android Flutter UI、QR 扫码、连接 controller、native WebSocket 包装和 shadow/commit 发送路径
- [x] 运行 PC 单元测试、Flutter test 和 Flutter analyze
- [x] 汇总可复现/高概率逻辑风险
- **状态：** complete

### 阶段 14：整体前端 Review 问题修复
- [x] 修复 Android native WebSocket 发送失败不可被 controller 捕获的问题
- [x] 修复 PC 同步开关即时广播跨 asyncio event loop 的风险
- [x] 修复 Android QR 替换设备确认先成功后确认的时序问题
- [x] 保持用户要求：不执行 APK 或 deb 编译
- [x] 运行 PC/Android 非打包验证
- [x] 提交并推送到远端
- **状态：** complete

### 阶段 15：Linux Terminal 输入失效调查
- [x] 检查 PC Linux 输入后端的剪贴板与快捷键路径
- [x] 联网检索 GNOME Terminal 粘贴快捷键、RemoteDesktop portal 和 GNOME Shell introspection 限制
- [x] 在本机探测 GNOME Terminal gsettings、GNOME Shell Introspect、AT-SPI 和 wl-clipboard primary selection
- [x] 形成修复方案
- **状态：** complete

### 阶段 16：GNOME Wayland Terminal 粘贴模式实现
- [x] 在 PC 平台输入层新增 Auto/普通/终端/兼容粘贴模式
- [x] Auto 模式通过 AT-SPI 检测 terminal 焦点，命中后发送 Ctrl+Shift+V，否则发送 Ctrl+V
- [x] 托盘菜单新增粘贴模式切换项，作为 Auto 检测失败时的手动兜底
- [x] Wayland 下同时写入 CLIPBOARD 和 PRIMARY，并尽量恢复 PRIMARY
- [x] 更新 README / README.zh-CN / CHANGELOG
- [x] 补充 PC 单元测试并完成验证
- [x] 用户手动启动实测：普通输入框和 terminal 均可自动输入
- **状态：** complete（已实测通过）

### 阶段 17：最新 PC / Android 代码全面逻辑复查
- [x] 复查 PC 端 WebSocket、托盘/QR、同步状态和平台输入逻辑
- [x] 复查 Android 端连接状态机、扫码、WebSocket 发送和文本提交逻辑
- [x] 运行当前环境可用的 PC/Android 验证命令
- [x] 汇总确定 bug、残余风险和测试缺口
- **状态：** complete

### 阶段 18：v2.9.5 GitHub Actions 发布构建修复与重触发
- [x] 推送 `v2.9.5` tag 触发 release workflow
- [x] 检查 Actions 结果并定位 Linux job 失败根因
- [x] 修复 headless Linux runner 中 Qt 单元测试无法初始化的问题
- [x] 运行本地非打包验证
- [x] 提交、推送并重新触发 `v2.9.5` release workflow
- [x] 等待 Actions 完成并确认 APK / DEB / 其他产物发布结果
- **状态：** complete

### 阶段 19：v2.9.6 Linux deb Wayland 启动修复
- [x] 复现已发布 `v2.9.5` deb 在 GNOME Wayland 上误报 RemoteDesktop portal 键盘能力不可用
- [x] 卸载本机已安装的错误 `voicing 2.9.5` deb 包
- [x] 修复 PyInstaller 打包态调用系统命令时的 `LD_LIBRARY_PATH` 污染
- [x] 覆盖 `gdbus`、`wl-copy` / `wl-paste`、系统 Python AT-SPI helper 的系统命令环境
- [x] 更新版本号、README 和 CHANGELOG 到 `2.9.6`
- [x] 完成本地单元测试、Android analyze/test 和 frozen smoke test
- [x] 提交、推送并触发 `v2.9.6` release workflow
- [x] 确认新 Release 资产，尤其是 `voicing-linux-amd64.deb`
- **状态：** complete

### 阶段 20：公开文档同步 Linux 自动粘贴与自启边界
- [x] 审查 `README.md`、`README.zh-CN.md`、Android README 和 `CHANGELOG.md`
- [x] 补充 GNOME Wayland 默认自动粘贴、终端 Ctrl+Shift+V、手动粘贴模式说明
- [x] 补充 Linux GNOME autostart `.desktop` 与 Wayland RemoteDesktop 授权边界
- [x] 同步 Android 端使用文档中用户需要知道的 Linux 桌面端行为
- [x] 运行文档 diff 和 `git diff --check`
- **状态：** complete

### 阶段 21：GNOME Wayland Auto 粘贴稳定性修复
- [x] 复查 PC 端 Linux Auto 粘贴与 AT-SPI terminal 检测路径
- [x] 本机复现 AT-SPI 查询偶发 `None` 导致 Auto 退回普通 `Ctrl+V`
- [x] 将 Auto 模式改为稳定优先：重试焦点检测、缓存近期 terminal、无法可靠确认焦点时走终端安全 `Ctrl+Shift+V`
- [x] 扩展 terminal app 名称识别并同步系统 Python AT-SPI helper
- [x] 更新 README / Android README / CHANGELOG 的 Auto 粘贴边界说明
- [x] 补充 PC 单元测试并完成验证
- **状态：** complete

### 阶段 22：v2.9.7 Release 发布
- [x] 更新 PC / Android 版本号到 `2.9.7`
- [x] 将 CHANGELOG Unreleased 内容落到 `2.9.7` 发布块
- [x] 运行 PC 和 Android 发布前验证
- [x] 提交并推送 `main`
- [x] 推送 `v2.9.7` tag 触发 GitHub Actions release workflow
- [x] 确认 Actions 成功并发布 GitHub Release 资产

### 阶段 28：GNOME Wayland Auto 粘贴采样投票稳定性修复
- [x] 调研当前 AT-SPI focused/active fallback 稳定性与 RemoteDesktop portal 能力边界
- [x] 将 Auto 粘贴从单次明确结果决策改为 500ms 窗口采样投票
- [x] 系统 Python AT-SPI helper 改为单进程内批量采样，避免每个样本重复启动 Python
- [x] 补充 PC 单元测试并更新公开文档
- [x] 运行 PC 编译、单元测试和 diff 检查
- **状态：** complete

### 阶段 29：v2.9.9 Release 发布
- [x] 更新 PC / Android 版本号到 `2.9.9`
- [x] 将 CHANGELOG Unreleased 内容落到 `2.9.9` 发布块
- [x] 运行 PC 和 Android 发布前验证
- [x] 提交并推送 `main`
- [x] 推送 `v2.9.9` tag 触发 GitHub Actions release workflow
- [x] 确认 Actions 成功并发布 GitHub Release 资产
- **状态：** complete

### 阶段 30：本机旧版卸载与 v2.9.9 安装确认
- [x] 停止旧的 `/opt/voicing/voicing` 进程
- [x] 卸载本机已安装的 `voicing 2.9.8` deb 包
- [x] 删除旧的 GNOME 用户级自启文件
- [x] 复核本机已安装 `voicing 2.9.9`
- [x] 确认 `/usr/bin/voicing`、`/opt/voicing`、运行进程和 GNOME 自启项恢复
- **状态：** complete

### 阶段 23：Auto Enter 可靠性修复
- [x] 复查 Android shadow/commit Auto Enter 发送路径
- [x] 复查 PC WebSocket commit 分支与 Wayland Enter 发送路径
- [x] 修复 PC commit 成功/失败 ACK 语义，Enter 成功才返回清空输入
- [x] 延长 PC 粘贴后 Auto Enter settle 延迟
- [x] 修复 Android forceEnter commit 后立刻清空输入的问题，改为等待 PC ACK 清空
- [x] 补充 PC 服务端单元测试并完成 PC/Android 验证
- **状态：** complete

### 阶段 24：Android 到 PC 发送核心链路最终审查
- [x] 审查 Android `sendText()`、shadow increment、commit finalize 与 ACK 处理
- [x] 审查 Dart WebSocket 抽象和 Android Kotlin native WebSocket bridge
- [x] 审查 PC WebSocket handler、输入注入、ACK 清空和 sync disabled 语义
- [x] 审查协议常量/contract 中 text、ack、send_mode、auto_enter 字段一致性
- [x] 运行 PC/Android 验证并确认无新增阻断问题
- **状态：** complete

### 阶段 25：GNOME Wayland Auto 粘贴普通窗口误判修复
- [x] 复查 PC Auto 粘贴焦点判定、AT-SPI active fallback 和测试覆盖
- [x] 修复未知焦点无近期 terminal 缓存时误走终端粘贴的问题
- [x] 将 AT-SPI fallback 从只找 active terminal 改为返回 active 窗口信息，普通窗口可明确走 Ctrl+V
- [x] 同步系统 Python AT-SPI helper 与公开文档/CHANGELOG
- [x] 补充 PC 单元测试并完成验证
- **状态：** complete

### 阶段 26：v2.9.8 Release 发布
- [x] 更新 PC / Android 版本号到 `2.9.8`
- [x] 将 CHANGELOG Unreleased 内容落到 `2.9.8` 发布块
- [x] 运行 PC 和 Android 发布前验证
- [x] 提交并推送 `main`
- [x] 推送 `v2.9.8` tag 触发 GitHub Actions release workflow
- [x] 确认 Actions 成功并发布 GitHub Release 资产
- **状态：** complete

### 阶段 27：本机 v2.9.8 deb 安装与 GNOME 自启确认
- [x] 卸载旧的 `voicing 2.9.7` deb 包
- [x] 确认用户安装的最新 GitHub deb 为 `voicing 2.9.8`
- [x] 确认 `/usr/bin/voicing` 指向 `/opt/voicing/voicing`
- [x] 确认 `~/.config/autostart/voicing.desktop` 存在且启用
- [x] 确认当前桌面为 GNOME，会匹配 autostart 的 `OnlyShowIn=GNOME`
- **状态：** complete

### 阶段 31：GNOME Wayland 冷启动 terminal 首次粘贴误判重型调研
- [x] 建立 Heavy Research 会话与统一调研提纲
- [x] 并行完成联网、源码和长期记忆三维调研
- [x] 校验调研报告并综合根因、方案与关键缺口
- [x] 用户确认调研摘要后生成 deployment plan
- **状态：** complete

### 阶段 32：全仓逐文件审查与仓库级 Agent Markdown 初始化
- [x] 建立排除 `.git/` 内部对象后的完整文件清单，并逐文件检查文本、配置、源码、资源及二进制元数据
- [x] 基于实际仓库结构与工作流编写根目录 `AGENTS.md` 和 `CLAUDE.md`，保证内容完全一致且 H1 为 `# Repository Agent Markdown`
- [x] 校正 `.gitignore`：仓库根 Agent Markdown 保持本地忽略，PWF 三件套保持 Git 跟踪
- [x] 运行配置一致性、编码、Git diff 和适当项目验证
- [x] 同步 PWF 三件套，提交本次应推送文件并推送当前分支
- **状态：** complete

### 阶段 33：Ubuntu 22.04 GNOME Wayland 终端识别稳定性修复与 v2.9.10 发布
- [x] 恢复阶段 31 调研结论，复核当前环境、运行日志和终端/非终端粘贴全链路
- [x] 为焦点采样、helper 状态、AUTO 决策和 portal 键序列补充可验证的结构化诊断
- [x] 实现 terminal / normal / unresolved 三态识别、就绪重采样和安全失败语义
- [x] 补齐分类器、冷启动稀疏样本、Portal modifier、剪贴板恢复和 ACK 回归/压力测试
- [x] 在 Ubuntu 22.04 GNOME Wayland 对 terminal 与普通窗口进行重复实机验证，失败则继续修复重测
- [x] 同步 PC/Android 版本、CHANGELOG 与中英文文档，并完成 PC/Android 发布前验证
- [x] 记录 PWF，提交并推送 `main`，创建 `v2.9.10` tag 触发 GitHub Actions
- [x] 确认 Actions 全绿并核验新 deb、apk 及其余 Release 资产
- **状态：** complete

### 阶段 34：最终进度记录与推送确认
- [x] 恢复并复核 PWF 三件套，运行 session catchup
- [x] 确认工作区起始状态干净，`main` 与 `origin/main` 同步于 `e0c0074`
- [x] 确认阶段 33、Actions run `30330984843` 与 Release `v2.9.10` 已完成
- [x] 增量同步本次最终交接记录，并只提交 PWF 三件套
- **状态：** complete

### 阶段 35：Wayland 粘贴统一 Ctrl+V 与 v2.9.11 发布
- [x] 确认用户不再使用终端内 agent，终端粘贴场景整体移除
- [x] 发现远端已由阶段 33 发布 v2.9.10（AT-SPI 强化路线）且与本次方向相反，经用户确认改发 v2.9.11
- [x] 撤销 `fa09391`（AT-SPI 强化），保留 `e0c0074` 的 checksum 平铺修复与 DEB 规范化
- [x] `pc/platform_keyboard.py` 删除 AT-SPI 焦点探测链路，Wayland 固定发送 Ctrl+V
- [x] `pc/voice_coding.py` 删除托盘「粘贴模式」菜单项
- [x] 同步 PC 测试并跑通全量单测
- [x] 保留远端 APK/体积等事实更新，改写四份文档为统一 Ctrl+V 说明
- [x] CHANGELOG 保留 v2.9.10 历史并新增 v2.9.11 块；版本号 PC `2.9.11` / Android `2.9.11+12`
- [x] 运行 Android analyze / test 回归与本机 frozen 冒烟
- [x] 更新 PWF 并提交推送 main（`8607d60`）
- [x] 推送 v2.9.11 tag；Actions run `36130314847` 6/6 job 全绿，Release 资产齐全
- [x] 本机安装 v2.9.11 deb（从 2.9.9 升级）并写入 GNOME 开机自启
- [x] 真实桌面会话验证：本机实际为 X11 会话，进程常驻、9527 监听正常、日志零 AT-SPI 记录
- **状态：** complete

### 阶段 36：Android 端 VPN 场景 WiFi 连接修复与 v2.9.12 发布
- [x] 定位根因：`findCurrentWifiNetwork` 硬要求 `TRANSPORT_WIFI && NET_CAPABILITY_NOT_VPN`，不匹配就直接失败且无回退
- [x] 联网核实 Android 9+ `setUnderlyingNetworks()` 的 transport 传播行为与 Tailscale 侧已知限制
- [x] `MainActivity.kt` 改为分级选网：物理 WiFi → capability 异常的 WiFi → 继承 WiFi transport 的 VPN 网络
- [x] 无 WiFi 候选时回退 `activeNetwork`，不再直接失败
- [x] 新增每个候选网络的 transport/capability 诊断日志
- [x] 本地构建 debug APK，验证 Kotlin 编译通过
- [x] 运行 PC 全量单测（86 OK）、flutter analyze（0）、flutter test（24 passed）
- [x] 同步 CHANGELOG、双语文档与版本号到 2.9.12
- [x] 更新 PWF 并提交推送 main（`72ef1c5`）
- [x] 推送 v2.9.12 tag；Actions run `36141549843` 6/6 job 全绿，Release 六项资产齐全
- [x] 用户安装新 APK 实测：Tailscale 开启时仍未连通，暴露出「Android 禁止绕过 VPN」场景必须走隧道
- **状态：** complete（问题转入阶段 37）

### 阶段 37：Tailscale 双通道连接修复与 v2.9.13 发布
- [x] 定位真正根因：PC 上 Tailscale 正在运行（`100.102.136.4`），但 `tailscale0` 被三重过滤排除在 QR 与监听之外
- [x] 联网核实 Android 9+ `setUnderlyingNetworks()` 传播行为与 Tailscale 侧已知限制
- [x] PC 端经 `tailscale` CLI 读 CGNAT 地址，作为兜底候选追加到服务接口（局域网地址仍优先）
- [x] `refresh_server_interfaces()` 接入追加逻辑，QR payload 与 WebSocket 绑定同时生效
- [x] Android 端对 `100.64.0.0/10` 目标改用系统默认网络（VPN 隧道），不再绑定 WiFi
- [x] 新增 6 个 PC 单元测试并跑通全量（92 tests OK）
- [x] 本地构建 debug APK 验证 Kotlin 编译；flutter analyze 0 / flutter test 24 passed
- [x] 同步 CHANGELOG、双语文档与版本号到 2.9.13
- [x] 更新 PWF 并提交推送 main（`eb43ffe`）
- [x] 推送 v2.9.13 tag；Actions run `36146092747` 6/6 job 全绿，Release 六项资产齐全
- [x] 本机安装 v2.9.13 deb（从 2.9.11 升级）并重启，实测双地址监听生效
- [x] 用户安装新 APK 并重新扫码配对，在开启 Tailscale 下实测通过，确认连接正常
- **状态：** complete

### 阶段 38：云端最新内容同步 + 本机 v2.9.13 安装 + 开机自启（2026-09-28）
- [x] 确认工作区干净、`main` 落后 `origin/main` 7 个提交（`c741469` → `3f8341b`），并 `--ff-only` 拉到最新
- [x] 确认最新发布为 `v2.9.13`（PC `2.9.13`、Android `2.9.13+14`），核验 GitHub Release 六项资产
- [x] 下载 `voicing-linux-amd64.deb` 并做 `sha256sum -c` 与 Release API digest 双向校验
- [x] 卸载本机 `voicing 2.9.10`，安装 `2.9.13`，确认二进制 SHA-256 与 Release standalone 资产一致
- [x] 重建本机 `~/.config/autostart/voicing.desktop`：改为指向 `/opt/voicing/voicing` 并校验为启用状态
- [x] 启动已安装的 Voicing，确认进程常驻、多地址监听 9527 且运行日志无 ERROR/WARNING
- **状态：** complete

## 关键问题
1. 这个仓库的产品目标和核心使用场景是什么？
2. PC 端、Android 端和 protocol 目录之间如何协作？
3. 当前仓库是否具备清晰的运行、构建、测试路径？

## 已做决策
| 决策 | 理由 |
|------|------|
| 使用 PWF 记录本次检查 | 任务涉及多目录、多文件和多阶段阅读，适合持久化上下文 |
| 同步新增 `CLAUDE.md` 与 `AGENTS.md` | 仓库级 agent 配置新增时两份文件必须全文一致，H1 均为 `# Repository Agent Markdown` |
| Linux 托盘改用系统原生 `QMenu` | 自定义 `Qt.Popup` 菜单在 GNOME/Wayland 下定位/半透明黑块/Esc/几何无效等问题多，原生菜单更稳 |
| 保持 GNOME portal 输入后端，接受每次启动一次授权 | portal 在安全/零部署/可分发/跨发行版/前瞻性上全面优于 ydotool；ydotool 仅"无弹窗"占优但代价是 `/dev/uinput` 权限降级，不可作为已发布应用的默认 |
| 删除终端粘贴场景，而不是继续修复 AT-SPI 判定 | 用户确认不再使用终端内 agent，目标场景消失后删除比继续调优更彻底、更快、更稳 |
| 以 v2.9.11 覆盖 v2.9.10 的 AT-SPI 路线，不回退远端提交 | v2.9.10 已公开发布且资产齐全，保留其历史并发布新版本，不移动或删除已公开的 tag |
| 用 `git revert fa09391` 而不是在 1571 行代码上手工删除 | AT-SPI 强化集中在单一提交里，revert 后代码精确回到 `6fd3902` 基线，删除边界可靠且可复核 |
| 保留 Wayland 的 PRIMARY selection 写入 | 它属于剪贴板兼容层而不是焦点探测，删除它超出本次范围且有行为回归风险 |
| Android 选网从「过滤」改为「分级」 | 硬要求「非 VPN」会让任何 VPN 一开就完全不可用；分级能在保持 WiFi 优先的同时不被 VPN 状态阻断 |
| 找不到 WiFi 候选时回退 `activeNetwork` 而不是立即失败 | 立即失败让问题无法诊断；回退至少能连通，并把真实原因写进日志 |
| 本次 PC 端不改动，只同步版本号 | 改动 100% 在 Android 原生层；PC 端没有更新提示逻辑，用户无需重装 |
| Tailscale 地址经 CLI 读取而不是放开网卡过滤 | 放开三处过滤（VPN 名单、is_private、/32 前缀）会波动物理网卡选择这一被多个 release 修过的逻辑；CLI 读取是纯追加，零回归风险 |
| Tailscale 地址排在局域网地址之后 | 保持 QR 首选与既有行为不变，只在「Android 禁止绕过 VPN」时才走隧道 |
| Android 对 Tailscale 目标不绑定 WiFi | 该地址只能经隧道到达，绑定物理 WiFi 必然失败 |

## 遇到的错误
| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
| 更新 PWF 时补丁上下文未匹配 | 1 | 重新读取三件套后使用更精确补丁 |
| PC 单元测试因缺少 PyQt5 导入失败 | 1 | 记录为环境限制；未安装依赖 |
| 当前 Ubuntu 会话为 Wayland，Voicing Linux 桌面端会主动拒绝启动 | 1 | 切换到 `Ubuntu on Xorg` 会话后再运行 |
| 当前源码运行环境缺少 PyQt5 和 pip | 1 | 下次补齐 Python 依赖环境后再启动 PC 端 |
| GNOME Wayland 不支持直接复用现有 pyautogui 全局按键路径 | 1 | 研究 RemoteDesktop portal/libei 与 ydotool 等替代输入后端 |
| Android debug APK 构建缺 Android SDK | 1 | 已补 SDK，但本任务未改 Android native，用户确认无需继续 APK 构建；停止构建，仅保留 analyze/test |
| GitHub Actions Linux release job 在 headless runner 中 Qt `xcb` 初始化失败 | 1 | Linux release job 和托盘测试设置 `QT_QPA_PLATFORM=offscreen`，本地 88 项 PC 测试通过 |
| 已发布 `v2.9.5` deb 在 GNOME Wayland 下误报 RemoteDesktop portal 键盘能力不可用 | 1 | 清理 PyInstaller 打包态调用系统命令时的 `LD_LIBRARY_PATH`，并发布 `v2.9.6` |
| `v2.9.6` 首次 release run 中 macOS `Create DMG` 报 `hdiutil: create failed - Resource busy` | 1 | 使用 GitHub Actions failed-job rerun 后通过，判断为 macOS runner 临时资源占用 |
| Heavy Research 联网报告首轮含省略号占位 | 1 | 按相同维度 prompt 自动重跑，第二轮通过 12/12 结构与占位符校验 |
| 第一轮键盘测试因旧 terminal cache API 已移除而 45 项均在 setUp 失败 | 1 | 删除旧 cache 测试前置，并按三态/ACTIVE-first/clipboard/portal 新语义重写回归测试 |
| 完整 PC suite 使用系统 Python 时 4 个模块因缺少 `qrcode` 无法导入 | 1 | 创建仓库 `.venv` 并安装 `pc/requirements.txt`，之后用隔离环境重跑完整测试 |
| 创建 `.venv` 时 Ubuntu 缺少 ensurepip / `python3.10-venv` | 1 | 使用免密 sudo 安装 `python3.10-venv`，再以 `--clear` 重建已生成的局部 venv |
| Wayland 自动化无法可靠把临时 GNOME Terminal 切到前台 | 3 | 新窗口受 focus-stealing prevention 限制，frame `grab_focus()` 返回 false，深层 terminal 扫描又超时；停止重复该路线，后续采用用户真实点击/已聚焦终端验证 |
| Ghostty 的真实 ACTIVE 窗口被 AT-SPI 暴露为 `Unnamed/frame` 且无 terminal/focused 子节点 | 1 | 从 ACTIVE accessible 的 AT-SPI PID 读取仅包含可执行文件 basename 的 `process_name`，由主分类器与 system helper 统一将 `ghostty` 判为 terminal；禁止依赖窗口标题或正文 |
| 独立 Portal harness 未持有全局 Qt application 时 `CreateSession` 超时 | 2 | 按真实产品生命周期持有全局 `QCoreApplication`；同一实现随后在 normal 与 terminal 两侧均成功建立并发送完整键序列 |
| 非空 Ghostty proof 使用第二个新 Portal 会话时停在 `Start` 授权并超时 | 1 | 不把授权超时当作输入成功；下一步在单个已授权 Portal backend 生命周期内连续完成空文本和非空 proof，避免重复授权窗口 |
| 本地 DEB 临时目录脚本因包含递归清理被安全策略拒绝 | 1 | 未发生删除；改用 PyInstaller 已重建且受 ignore 管理的 `pc/dist/deb-root`，不执行递归清理 |
| 按旧 workflow 本地打出的 DEB 内容保留普通用户所有权与 umask 模式 | 1 | workflow 改用 `chmod 0644` 与 `dpkg-deb --root-owner-group`，重建后全部内容为 `root/root` |
| 最终 DEB 重打包检测到上次 `deb-root` 仍存在并主动退出 | 1 | 未覆盖旧目录；将旧目录移动为 ignore 内备份，再从最终二进制创建全新 package root |
| 首轮 Release 的 `SHA256SUMS.txt` 保留 CI artifact 子目录，扁平下载后无法直接校验 | 1 | workflow 生成时去除平台目录并断言 5 行/无斜杠；本次仅覆盖 checksum 资产后重新下载原生校验通过 |
| 从 `/tmp` 执行 `gh release upload` 无法推断仓库 | 1 | 未上传任何内容；重试时显式传入 `--repo kevinlasnh/Voicing` 后成功 |

## 备注
- PWF 内容仅记录 agent 自己的检查计划和发现；外部内容如需引用只进入 findings.md。

## 阶段 39：全面重构优化 + 跨网络快速配对 + 本机 v2.9.14 安装（2026-11-20）

### 目标
1. 同一手机同一 PC 在多个网络环境各扫码一次后，回到任一网络无需重扫、1~2 秒内自动配对；地址历史与网络画像持久化、自适应排序与并行探测。
2. PC 端（Python/PyQt5）与 Android 端（Flutter/Kotlin）全面重构：结构分层、算法与性能优化、自适应网络/超时策略。
3. 本机重新构建并安装最新 PC 端，保持开机自启；全部改动记录并 push。

### 计划
- [x] 复盘双端现状与性能热点，确定跨网络配对缺口与设计方案
- [x] Android：地址簿 schema v2（含网络画像）、候选评分排序、Happy Eyeballs 并行探测、原生网络快照桥
- [x] Android：控制器扫码/重连重构、自适应网络切换重连与单测
- [x] PC：模块化拆分（网络发现 / WebSocket server / Qt UI / 入口兼容层）
- [x] PC：接口枚举缓存、QR 缓存、server 调优、自适应监听与单测
- [x] 双端契约与兼容性检查（QR schema 不变、旧 PC 2.9.13 与旧 saved_server 数据互通）
- [x] 全量验证：PC suite、flutter analyze/test、APK debug 构建、协议 E2E 冒烟、DEB 构建
- [x] 版本（PC 2.9.14 / Android 2.9.14+15）、CHANGELOG、README、PWF 同步
- [x] 提交并 push 到 origin/main
- [x] 本机构建 DEB、安装、开机自启与运行监听验证

### 关键决策
| 决策 | 理由 |
|------|------|
| 不改协议契约与 QR schema，跨网络能力全部由 Android 地址簿承载 | 保持与已发布 PC 2.9.13 双向兼容，零协议迁移风险 |
| 用网络画像（接口类型 + 本地子网 CIDR）而不是 SSID 做设备网络标识 | 不新增定位/权限，纯网络层信息即可判断目标地址可达性 |
| 已保存重连从串行尝试改为 Happy Eyeballs 并行竞速 | 串行 N×2s 是跨网络重连慢的根因；并行后总耗时约等于单次 RTT |
| 同网络 Key 优先 + 同子网 + Tailscale 分层评分 | 让最可能可达的地址先竞速，未知网络也不阻塞 |
| 地址簿裁剪永不丢弃不同网络的最近成功地址 | 这是「两次扫码后两个网络都不再重扫」的核心不变量 |
| PC 重构保留 voice_coding.py 兼容导出 | 既有 88 项测试与 PyInstaller 入口零破坏 |

### 交付结果（2026-11-21）
- 代码：Android 新增 `network_profile` / `server_address_book` / `connection_race` / `connection_tuning` 四个模块，`saved_server` 升级 schema v2，原生新增网络快照桥；PC 入口从 2185 行拆为 7 模块（入口 425 行），新增 `voicing_tuning` 参数集中层。
- 验证：PC 单测 138 项 0.82s 全绿；Flutter 单测 51 项 3.3s 全绿；`flutter analyze` 仅 4 条既有 info；APK debug 构建成功；协议 E2E 11/11；QR payload 13/13；协议契约与 QR schema 零变更；`git diff --check` 通过。
- 产物：`pc/dist/voicing-linux-amd64.deb`（2.9.14，60,435,006 B，SHA256 `10f33acf6f01…9442c5bda`）；独立二进制 SHA256 `50311d2f407b…5a441a17`。
- 本机：已安装 `voicing 2.9.14`，`/opt/voicing/voicing` SHA256 与本次构建一致；GNOME 自启单元 `app-voicing@autostart.service` active（生成自 `~/.config/autostart/voicing.desktop`）；监听 `10.10.0.225:9527` + `100.104.201.81:9527`，不含 docker0；启动日志 0 ERROR/WARNING。
- 兼容性：协议/QR schema 未变，v1 saved_server 自动迁移且无需重扫；本轮无 adb 真机，Android 新 APK 未安装到手机（debug 包在 `android/voice_coding/build/app/outputs/flutter-apk/app-debug.apk`，供用户自装或后续 CI 发布）。

- **状态：** complete

## 阶段 40：v2.9.14 GitHub Release 发布与官方产物安装（2026-11-21）

### 目标
1. 推送 v2.9.14 tag 触发 `.github/workflows/release.yml`，完成四平台构建与 GitHub Release。
2. 核验 Release 六项资产与 SHA256SUMS，下载官方 Linux DEB 覆盖安装到本机并保持自启。
3. 记录发布/安装结果并 push。

### 计划
- [x] 推送 v2.9.14 tag 触发 release workflow（首轮 run 44858906939）
- [x] 定位 macOS job 失败根因：GitHub 2026-11-02 下线 macOS 14 runner 镜像，`macos-14` 秒取消
- [x] CI 修复：`runs-on: macos-14` → `macos-15`（官方推荐 arm64 标签），提交并 push main
- [x] 删除并重建 v2.9.14 tag 指向 CI 修复后的提交，重新触发 run 44859445886
- [x] 核验 6/6 job success、Release 六项资产、SHA256SUMS 与 API digest 全部一致
- [x] 下载官方 DEB 与 APK 到 `~/Downloads/Voicing-2.9.14/`，`sha256sum -c` 通过
- [x] 官方 DEB 覆盖安装（inner binary SHA256 = standalone 资产 digest），autostart 单元启动并验证监听/日志
- [x] 更新 PWF 三件套并 push

### 结果
- Release：https://github.com/kevinlasnh/Voicing/releases/tag/v2.9.14（tag → `1eebfa6`），6/6 job 全绿。
- 资产：`voicing.apk`、`voicing-windows-x64.exe`、`voicing-macos-arm64.dmg`、`voicing-linux-amd64.deb`、`voicing-linux-x86_64`、`SHA256SUMS.txt`（扁平 basename，5 行校验和）。
- 本机：官方 `voicing-linux-amd64.deb`（SHA256 `69b5bd7d…31789`）安装为 2.9.14；`/opt/voicing/voicing` SHA256 `75c2de42…b6239` = Release standalone 资产；监听 `10.10.0.225:9527` + `100.104.201.81:9527`（无 docker0），日志 0 ERROR/WARNING。
- 用户侧：官方 APK 已下载到 `~/Downloads/Voicing-2.9.14/voicing.apk`，可直接安装到手机。

- **状态：** complete

## 阶段 41：同步云端最新进度 + 本机安装 v2.9.14 + 记录推送（2026-11-22）

### 目标
1. 把云端仓库的最新进度同步到本机（只拉取，不改写历史）。
2. 在本机安装最新官方 Voicing 桌面端，保持开机自启与手机可连接。
3. 记录进度并 push 到 `origin/main`。

### 计划
- [x] `git fetch` 后比较本地与远端，确认落后提交数与最新 tag
- [x] `git pull --ff-only` 快进到 `origin/main`
- [x] 核对仓库版本号与 GitHub `releases/latest`
- [x] 下载官方 `voicing-linux-amd64.deb` 并用 `SHA256SUMS.txt` 校验
- [x] 停旧进程、`dpkg -i` 覆盖安装，校验版本与二进制哈希
- [x] 启动并验证自启单元、9527 监听与启动日志
- [x] 更新 PWF 三件套并 push

### 结果（2026-11-22 11:33–11:40）
- 同步：本地 `3f8341b` → `9040709`，快进 5 个提交（35 文件，+8803/−2211），同时拉入 tag `v2.9.14`；仓库版本 `PC 2.9.14` / `Android 2.9.14+15`，GitHub `releases/latest` 同为 v2.9.14。
- 安装基线纠正：本机实际为 `voicing 2.9.13`（`/opt/voicing/voicing` SHA-256 `b958f4c8…b6d0d` 属 2.9.13 产物），与仓库 2026-11-21 的安装记录不一致。
- 安装：官方 DEB 75,794,776 B，SHA-256 `69b5bd7d…631789`（与 Release API digest 一致）→ `dpkg -i` 升级为 `voicing 2.9.14 amd64`；`/opt/voicing/voicing` 76,805,904 B、`root:root` 0755、SHA-256 `75c2de42…6b6239`（= `voicing-linux-x86_64` standalone 资产）。
- 运行：`systemctl --user start app-voicing@autostart.service` → active，主进程 22192 + PyInstaller 子进程 22202；监听 `192.168.50.113:9527` + `100.102.136.4:9527`（无 docker0）；日志含 2.9.14 新增「可调参数生效值」表与「托盘就绪」，当日 0 ERROR/WARNING。
- 自启：`~/.config/autostart/voicing.desktop` 保持 `Exec=/opt/voicing/voicing`、`X-GNOME-Autostart-enabled=true`，升级未改动用户级自启项。
- 连通：重启后约 1 秒内手机 `192.168.50.56`（`okhttp/4.12.0`）自动重连成功并保持 ESTAB，已保存配对无需重扫。

- **状态：** complete


## 阶段 42：多设备并发连接 + 设备选择菜单 + CI/文档改造（v2.10.0，2026-11-22 14:48）

### 目标
1. Android 端同一 WiFi 下可同时配对/连接多台 PC：扫码不再覆盖旧设备，同一 device_id 重扫只合并地址历史；所有已配对设备并发建链。
2. 「更多功能操作」最下方（扫码连接下方）新增「设备选择」入口，点击向左弹出与现有下拉菜单同风格的二级菜单，列出已配对设备+连接状态+当前勾选；文本/shadow/Auto Enter 只发当前选中设备，迟到 ACK 不清当前输入。
3. 存储升级 schema v3（`saved_servers` + `active_device_key`），旧 v1/v2 自动迁移，继续写单设备兼容字段；协议与 QR schema 零变更，PC 端无需升级。
4. GitHub Actions：删除 macOS 构建；新增 workflow_dispatch 手动构建 APK + Linux DEB/standalone（不发布 Release）；tag 发布保留三平台 + 4 项资产 + SHA256SUMS。
5. 重写仓库级 AGENTS.md/CLAUDE.md：推送后自动触发 Action、重装/发版重新触发、禁止 macOS job、限长合规。
6. 版本升 2.10.0（Android 2.10.0+16），双语文档/CHANGELOG 更新；全量验证后 push 并触发 Action，下载新 APK/DEB。

### 计划
- [x] 侦察现有 controller/store/main/测试与 CI，确认单设备覆盖点
- [x] 设计并实现 SavedServerStore schema v3（列表/活跃 Key/迁移/单设备兼容写回）
- [x] 重构 VoicingConnectionController 为多设备并发链接（每设备独立竞速/心跳/重连/generation）+ 活跃设备路由
- [x] 修复设备身份不变量（legacy key → device_id 重排 Map Key；手动地址保留原 deviceId）
- [x] UI：扫码连接下方设备选择入口 + 向左二级菜单（状态点/勾选/空态）+ 头部「状态 · 设备名」
- [x] 新增/更新测试：v3 存储、多设备并发、文本路由、ACK 过滤、QR 追加/合并不覆盖、身份迁移
- [x] CI 改造 + 仓库 AGENTS/CLAUDE 重写
- [x] 文档与版本更新（CHANGELOG/README/Android README 中英）
- [x] 独立 QA 验证（analyze/test/build/PC 测试/CI/文档）
- [x] PWF 收尾、commit、push main
- [x] 触发 GitHub Action 手动构建并核对（Linux DEB 已下载安装；APK 按新规则不由本地下载）

### 结果（进行中，2026-11-22 14:48）
- 代码：Android 新增多设备链接模型；`saved_server.dart` schema v3；`main.dart` 设备选择二级菜单；PC 端仅版本号变更。
- 过程中修复：① `SavedServerStore._migrateLegacyManualServer` 调 `save()` 会递归 `loadSnapshot` 造成测试挂起；② legacy 记录 connected 后 device_id 升级导致 Map Key 与 `server.deviceKey` 失配；③ 手动 IP 命中已有 QR 设备时会丢 deviceId；④ 二级菜单收起后 opacity 0 仍可命中（必须卸载 overlay）。
- 本地验证：Flutter analyze 仅 5 条既有 withOpacity info；`flutter test --no-pub` 60 项全绿；`flutter build apk --debug` 成功；PC `unittest` 138 项 0.81s OK + py_compile OK；`git diff --check` OK。
- 版本/文档：`APP_VERSION=2.10.0`、pubspec `2.10.0+16`；CHANGELOG 2.10.0 双语块、README/Android README 中英同步；AGENTS/CLAUDE 36 行 2137 字符 370 汉字且逐字节一致。

- **状态：** complete


### 收尾结果（2026-11-22 15:28）
- 提交并 push `origin/main`：`40a927d`（Android 多设备实现+版本）、`1f7afb5`（CI/文档）、`6163372`（PWF 记录），远端 main = `6163372`。
- 触发手动构建 Action：run `44996455255`（workflow_dispatch, main）→ **success**；Prepare Release Metadata 推导版本 `v2.10.0`、`release=false`；Build Android APK/Linux Desktop 成功，Build Windows EXE 与 Publish GitHub Release 按设计 skipped。产物 artifacts：`android-apk`（30MB）、`linux-deb`（72MB）、`linux-bin`（72MB）。
- 用户新指示：APK 由用户自己在手机下载，本地不再下载；AGENTS.md/CLAUDE.md 已加入「不下载 APK、仅在重装 Linux 时下载 linux-deb」红线（37 行/2451 字符/487 汉字，逐字节一致）。
- Linux 安装：由于 artifact CDN 单连接约 26KB/s，使用 12 路 Range 并行下载 75,772,960B 完成，`voicing-linux-amd64.deb` SHA256 `0bb98679…fa4a1`、Version 2.10.0；`systemctl --user stop` + `pkill -TERM -x voicing` 后 `sudo -n dpkg -i` 由 2.9.14 升级到 **2.10.0**；DEB 内 `/opt/voicing/voicing` 与安装后二进制 SHA256 均为 `57d44239…b2d1d`（76,805,920B）。
- 运行验证：`systemctl --user start app-voicing@autostart.service` active；监听 `192.168.50.113:9527` + `100.102.136.4:9527`；启动后 0 ERROR/WARNING；旧版手机 APK（2.9.14）15:28:06 自动重连回新版 PC（okhttp/4.12.0，在线 1），协议兼容得到实机验证。
- 交付：本机安装包位于 `~/Downloads/Voicing-2.10.0/voicing-linux-amd64.deb`；APK 下载入口为 run `44996455255` 的 `android-apk` artifact（用户手机自行下载安装）。


## 阶段 43：每次任务完成自动发布 GitHub Release（v2.10.1，2026-11-22 15:40）

### 目标
1. 改造 release.yml：`workflow_dispatch` 手动构建也自动创建/更新 GitHub Release（tag=`v<仓库版本号>`，资产 APK + Linux DEB/standalone + SHA256SUMS；tag 推送仍含 Windows EXE）。
2. 版本升 2.10.1 并更新 CHANGELOG/README/Android README 中「手动构建不发布 Release」的旧描述。
3. 更新仓库级 AGENTS.md/CLAUDE.md：每轮全部任务完成必须升版本+CHANGELOG → push → 触发 Action → 核验新 Release；不下载 APK，Linux 按需安装。
4. push、触发 Action、确认新 Release，并按需安装 v2.10.1 Linux DEB。

### 计划
- [x] 改造 publish-release：`always()` + 显式 result 检查，手动构建设 tag_name/target_commitish/make_latest，Windows 资产仅 tag 发布路径单独上传
- [x] prepare-release：release_tag 输出、两条路径都提取 CHANGELOG、缺块即失败、手动/正式 release notes 表格动态生成
- [x] 版本 2.10.1（APP_VERSION/pubspec 2.10.1+17）+ CHANGELOG 双语块 + README/Android README/版本徽章更新
- [x] AGENTS.md/CLAUDE.md 重写（37 行/2656 字符/552 汉字，逐字节一致）
- [x] 本地模拟：手动模式版本解析 v2.10.1/release_tag/is_release=false；release notes 手动无 Windows、tag 含 Windows；PyYAML 与 19 个 action pin 校验
- [x] PC 138 测试/py_compile；Android 65 测试；commit+push（`acd54ed`）
- [x] 触发 Action run `44998948373`（自动创建 tag v2.10.1 + Release）
- [x] 核验 run 成功、GitHub Release v2.10.1 与资产齐全
- [x] 下载并安装 v2.10.1 Linux DEB，验证运行
- [x] PWF 收尾、commit、push，完成目标

- **状态：** complete


### 收尾结果（2026-11-22 15:46）
- Action run `44998948373`：**success**。Prepare（v2.10.1, is_release=false）→ Android/Linux 构建成功，Windows skipped；Publish GitHub Release 18s 成功。
- 自动发布：tag `v2.10.1`（指向 `acd54ed`）+ GitHub Release **Voicing v2.10.1**（非 draft/prerelease，isLatest）。资产：`voicing.apk` 32,389,748B、`voicing-linux-amd64.deb` 75,795,356B、`voicing-linux-x86_64` 76,806,040B、`SHA256SUMS.txt`（3 行）；手动发布不含 Windows，符合设计。Release：https://github.com/kevinlasnh/Voicing/releases/tag/v2.10.1
- Linux 安装：Release DEB SHA256 `8d385048…eb48`（= 资产 digest = SHA256SUMS 行）；`dpkg -i` 由 2.10.0 升级 **2.10.1**；DEB 内二进制与安装后 `/opt/voicing/voicing` SHA256 均为 `89da4949…b86d6`（= Release standalone 资产 digest），76,806,040B root:root 0755。
- 运行：`app-voicing@autostart.service` active，进程 95419/95421，监听 `192.168.50.113:9527` + `100.102.136.4:9527`；启动日志 0 ERROR/WARNING；旧手机 APK 15:44:45 自动重连成功（okhttp/4.12.0，在线 1）。
- 交付：本机 `~/Downloads/Voicing-2.10.1/voicing-linux-amd64.deb`；手机 APK 从 Release 页面直接下载安装（无需解压 artifact）。


## 阶段 44：设备选择 UI 收敛（对称布局/常驻高亮/长按删除/名称滚动，v2.10.2，2026-11-22 16:40）

### 目标
1. 顶部「已连接」恢复纯状态，不显示设备名。
2. 更多功能菜单「设备选择」与其他行完全同款：统一小图标+四字文本，无名字/无箭头。
3. 左侧设备子菜单与顶部状态格对称：同宽、同间距、同容器/单元格样式与高度。
4. 每格只保留状态灯+设备名（删对勾/删除按钮）；当前目标用与右侧菜单点击相同的常驻高亮；长按弹确认框删除。
5. 设备名过长时像音乐播放器歌名一样缓慢来回滚动。
6. 版本 2.10.2 + CHANGELOG/README/Android README 中英同步；push 并自动发布新 Release。

### 计划
- [x] main.dart：移除 header 设备名；设备选择行复用 `_buildMenuItem`
- [x] 子菜单间距改为 `AppSpacing.componentGap`，宽度/圆角/高亮与面板对称一致
- [x] 单元格去掉对勾/删除按钮；长按 → 删除确认框；常驻高亮 0x0DFFFFFF
- [x] 新增 `_AutoScrollText`：溢出才滚动、两端停顿、12s 往返、ClipRect/Transform 不改行高
- [x] 版本 2.10.2（2.10.2+18）+ CHANGELOG 双语块 + README/Android README/AGENTS 更新
- [x] 本地验证：flutter analyze 仅 4 条既有 info；flutter test 65 项全绿；debug APK 构建成功；PC 138 测试 OK
- [x] 独立 QA 复核 UI 需求与代码（首轮 High 修复后 PASS）
- [x] commit/push、触发 Action 自动发布 v2.10.2 Release 并核验
- [x] PWF 收尾、commit/push

- **状态：** complete


### 收尾结果（2026-11-22 17:09）
- 提交 push：`e510088`（main.dart UI 收敛 + 新增 auto_scroll_text.dart + widget 测试 + 版本 2.10.2 + 双语文档）。
- qa-ui 最终 PASS：需求 1–6、8 全 PASS；需求 7 High（OverflowBox infinite size）修复后复验 PASS，残留 Low（测量未 merge DefaultTextStyle 导致端点裁 14px）已修复并加端点断言。
- Action run `45005709784` success：自动创建 tag `v2.10.2`（指向 `e510088`）并发布 **Voicing v2.10.2**（latest）。资产：`voicing.apk` 32,397,149B（sha256 f8bf7d82…f7e9）、`voicing-linux-amd64.deb` 75,795,354B（d1ee9b41…275f）、`voicing-linux-x86_64` 76,806,640B（0477ece2…2ea8）、`SHA256SUMS.txt`。手动发布按设计不含 Windows。
- 本地验证（最终快照）：`flutter analyze` 4 条既有 info；`flutter test --no-pub` **67 项全绿**（全套约 8.0s；新 widget 测试单跑 3.96s）；debug APK 构建成功；PC 138 测试 0.68s OK；`git diff --check` 干净。
- Linux DEB 本轮**未重装**：PC 运行时代码零改动（仅版本号），按用户「需要就安装，不用就不用」跳过；当前本机仍运行 2.10.1（行为与 2.10.2 相同）。APK 由用户从 Release 页面自行下载安装。
- Release：https://github.com/kevinlasnh/Voicing/releases/tag/v2.10.2


## 阶段 45：设备选择菜单点击后保持展开（v2.10.3，2026-11-22 17:20）

### 目标
1. 在左侧设备子菜单点选设备后，主菜单与子菜单都保持展开，仅更新选中高亮。
2. 只有点击非菜单区域才收起（第一次收子菜单、再点收主菜单），与右侧更多功能菜单行为一致。
3. 版本 2.10.3 + CHANGELOG/README/Android README/AGENTS 同步，跑验证后 push 并自动发布新 Release。

### 计划
- [x] `_handleDeviceSelected` 移除 `_closeMenu()`，只调用 `selectDevice`
- [x] 确认 backdrop 关闭逻辑保持原样（子菜单优先关闭，再关主菜单）
- [x] 版本 2.10.3（2.10.3+19）+ CHANGELOG 双语块 + 文档/AGENTS 版本同步
- [x] 本地验证：flutter analyze 4 条既有 info；flutter test 67 项全绿；debug APK 构建成功；PC 138 测试 OK；dart format 无改动；diff-check 干净
- [x] 触发 Action 自动发布 v2.10.3 Release 并核验
- [x] PWF 收尾、commit/push

- **状态：** complete


### 收尾结果（2026-11-22 17:26）
- Action run `45006994328` success：手动构建自动创建 tag `v2.10.3`（`017c55e`）并发布 **Voicing v2.10.3**（latest）。资产：`voicing.apk` 32,397,083B（sha256 4200e3b7…85d3）、`voicing-linux-amd64.deb` 75,795,484B（1e532144…8449）、`voicing-linux-x86_64` 76,805,824B（760d3368…9212）、`SHA256SUMS.txt`；手动发布按设计不含 Windows。
- 本地验证：flutter analyze 4 条既有 info；flutter test 67 项全绿；debug APK 构建成功；PC 138 测试 OK；dart format 无改动；`git diff --check` 干净。
- Linux DEB 未重装：桌面运行时代码未变（仅版本号），按「需要才安装」跳过；APK 由用户从 Release 页面自行下载安装。
- Release：https://github.com/kevinlasnh/Voicing/releases/tag/v2.10.3


## 阶段 46：设备选择选中行显示与自动 Enter 同款绿色对勾（v2.10.4，2026-11-22 17:38）

### 目标
1. 设备子菜单每行右侧永久预留 18x18 对勾位（文本区相应变窄），选中行显示绿色对勾，未选中留空。
2. 对勾位置/尺寸/颜色/内边距与右侧「自动 Enter」行尾对勾一致，切换选中时文字不横向抖动。
3. 版本 2.10.4 + CHANGELOG/README/Android README/AGENTS 同步；验证后 push 并自动发布新 Release；发布后按需下载安装新 Linux DEB。

### 计划
- [x] 设备行 Row 末尾加固定 18x18 槽位，active 显示 `Icons.check`（success/18），否则空
- [x] 版本 2.10.4（2.10.4+20）+ CHANGELOG 双语块 + 文档/AGENTS 版本同步
- [x] 本地验证：dart format 无改动；flutter analyze 4 条既有 info；flutter test 67 项全绿；debug APK 构建成功；PC 138 测试 OK；diff-check 干净
- [x] 触发 Action 自动发布 v2.10.4 Release 并核验
- [x] 下载安装 v2.10.4 Linux DEB，校验版本/二进制哈希/服务/监听/日志
- [x] PWF 收尾、commit/push

- **状态：** complete


### 收尾结果（2026-11-22 17:45）
- Action run `45008347766` success：自动创建 tag `v2.10.4`（`c28d5c1`）并发布 **Voicing v2.10.4**（latest）。资产：APK 32,397,428B（bf7d92ec…652b）、Linux DEB 75,795,182B（93886147…c7e5）、standalone 76,805,960B（43f5f986…4e7f）、SHA256SUMS.txt；手动发布不含 Windows。
- Linux 安装：Release DEB 12 路 Range 下载 75,795,182B 完成，SHA256 `93886147…c7e5` 与 SHA256SUMS/Release digest 一致；`dpkg -i` 由 2.10.1 升级 **2.10.4**；DEB 内与安装后 `/opt/voicing/voicing` SHA256 均为 `43f5f986…4e7f`（= standalone 资产 digest），76,805,960B root:root 0755。
- 运行：`app-voicing@autostart.service` active，进程 136972/136983，监听 `192.168.50.113:9527` + `100.102.136.4:9527`；启动 0 ERROR/WARNING；旧手机 APK 17:44:08 自动重连（okhttp/4.12.0，在线 1）；autostart 配置未变。
- 本地验证：flutter analyze 4 条既有 info；test 67 项全绿；debug APK 构建成功；PC 138 测试 OK；dart format 无改动；git diff --check 干净。
- Release：https://github.com/kevinlasnh/Voicing/releases/tag/v2.10.4
