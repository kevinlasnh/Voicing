# Findings — Phase 2：豆包输入法桌面化可行性调研

调研日期：2026-04-22
分支：`feature/desktop-native-asr-research`
用户约束（强制）：**只用豆包输入法本身的语音能力，不走火山引擎云 API**

---

## 23. 用户原方案的技术现实判定

**原方案**：电脑安装豆包输入法 APK → 反编译 → 抽离语音模块 → 集成进 Voicing 桌面端

**结论**：**不可行**。三个硬性阻断：

1. **架构不兼容**：豆包输入法 APK 内的语音 native library（.so）是 ARM 架构（armeabi-v7a / arm64-v8a），无法在 Windows x86_64 原生运行。需要 Android 模拟器或重编译，工作量等同于从零开发。
2. **"离线"模型并非真正离线**：豆包输入法的 ~150MB 内置模型是降级 fallback，准确率明显低于云端版本。日常使用的高准确率识别仍走字节服务器，APK 本质是协议客户端。
3. **法律风险**：直接抽离 ByteDance 编译产物再分发属于明确版权侵权，无法开源。

---

## 24. 关键发现：已有现成的逆向客户端 ⭐

**项目**：`starccy/doubaoime-asr`（GitHub）
- URL：https://github.com/starccy/doubaoime-asr
- 别人已经做完了协议逆向工作，提供 Python 客户端

技术细节（已 WebFetch 核实）：
- **不需要本地装 APK**：纯网络调用字节服务器
- **不走火山引擎付费 API**：调用的是豆包输入法 Android 客户端自己用的内部接口
- **协议**：自定义 protobuf（项目内有 `wave_protocol.md` + `gen_proto.sh`）
- **鉴权流程**：
  - 首次运行自动向服务器注册虚拟 device
  - 服务器返回 token
  - token 缓存到本地凭证文件
  - 后续请求带 `device_id` + `token`
- **音频依赖**：Opus（Windows 可通过 PyOgg / opuslib 装）
- **三种调用模式**：
  - `transcribe`（一句话）
  - `transcribe_stream`（流式，返回中间结果）
  - `transcribe_realtime`（实时异步）
- **Windows 原生**：纯 Python，无需 Android 模拟器

项目健康度（必须重点关注）：
- Stars：298 / Forks：112
- **commits 仅 4 次，维护活跃度低**
- **无 LICENSE 文件**
- 作者声明："服务端协议可能随时变更导致功能失效"

---

## 25. 路径 A 的现实风险

复用 `doubaoime-asr` 实现 Voicing 桌面化的风险矩阵：

| 风险 | 触发条件 | 后果 | 缓解 |
|---|---|---|---|
| 协议变更 | 字节 server 端升级 protobuf schema | Voicing 桌面端整体瘫痪 | 监控上游仓库 + 准备 fallback |
| 鉴权加固 | 字节加 device fingerprint / app signature 校验 | 虚拟 device 注册失败 | 无法绕过，只能切 fallback |
| 速率限制 / 封禁 | 单 device_id 请求量过大 | 高频用户被封 | 本地多 device_id 池 + 限速 |
| 法律风险 | 字节发律师函 | 项目下架 | 项目仅个人学习用，不商业化分发 |
| 上游项目废弃 | starccy/doubaoime-asr 不再维护 | 协议失配后无人修复 | fork 维护 / 自己重新逆向 |
| 无 LICENSE | 不能合法 vendoring 或 fork | 法律灰色地带 | 联系作者获取授权 / 仅作运行时依赖 |

---

## 26. Fallback 方案：本地 Whisper

如果豆包路径失效，可降级到本地 Whisper：
- **whisper.cpp**：纯 C++，Windows 原生支持，离线运行
- 中文识别 `large-v3` 模型准确率已接近商业水平
- 缺点：模型 ~3GB，首次加载延迟，CPU 实时性勉强（需 GPU 流畅）
- 优点：100% 合法、零成本、零外部依赖

**建议作为 v2 的 fallback engine 内建**，让用户在豆包失效时一键切换。

---

## 27. Voicing 桌面化最终架构建议

```
┌──────────────────────────────────────────┐
│ Voicing Desktop (Windows / macOS / Linux) │
│                                            │
│  全局热键监听（pynput / keyboard）         │
│        ↓                                   │
│  按下热键 → 录音（PyAudio / sounddevice）│
│        ↓                                   │
│  ASR Engine（可切换）                      │
│   ├── Doubao IME（doubaoime-asr）⭐ 默认  │
│   └── Whisper.cpp（本地 fallback）        │
│        ↓                                   │
│  文本注入（pyperclip + 模拟 Ctrl+V）       │
│   ↑ 复用 Voicing v2.7.x 现有链路          │
│        ↓                                   │
│  自动 Enter（已有逻辑）                    │
└──────────────────────────────────────────┘
```

复用现有 PC 端组件：
- `pc/voice_coding.py` 的剪贴板注入 + 自动 Enter
- `pc/platform_keyboard.py` 的跨平台输入
- 系统托盘 UI

新增组件：
- `pc/asr_engine/` 抽象接口
- `pc/asr_engine/doubao_ime.py` 调 doubaoime-asr
- `pc/asr_engine/whisper_local.py` 调 whisper.cpp
- `pc/hotkey_listener.py` 全局热键
- `pc/audio_capture.py` 录音

可彻底删除的 v1 组件：
- WebSocket server
- UDP 发现
- Android 端整体（独立桌面端不再需要手机）

注：Android 端是否保留？建议**双形态共存**——Voicing 桌面版独立运行 + 原 Voicing Mobile 仍作为「无桌面 ASR 时的 fallback」。但用户的明确目标是抛弃手机端，可让用户决策。

---

## 28. 调研引用源

- doubaoime-asr 项目：https://github.com/starccy/doubaoime-asr
- 火山引擎 ASR 产品页：https://www.volcengine.com/product/asr （仅供对比，不采用）
- 豆包输入法体验评测：https://www.80aj.com/2025/12/19/doubaoshurufayuyinshibietiyanlixianjingzhundipeishebeiye/
- whisper.cpp 介绍：https://cn.x-cmd.com/pkg/whispercpp/
- PushToTalk 参考实现：https://github.com/ruanyf/weekly/issues/8545

---

## 29. doubaoime-asr 配置项调研结论（决定 PoC 砍配置）

调研日期：2026-04-22

WebFetch 核实 `starccy/doubaoime-asr` 的 `ASRConfig` 与 `wave_protocol.md`：

**实际可配的字段**：
- `credential_path`（凭证缓存路径）
- `device_id`（虚拟设备 ID，自动注册）
- `token`（鉴权 token，自动获取）
- `sample_rate`（采样率，默认 16000）
- `channels`（声道，默认 1）
- `enable_punctuation`（标点总开关，默认 true）

**用户期望但 doubaoime-asr 不支持的**（豆包输入法 App 内的本地后处理功能）：
- 标点四档模式（智能 / 替换为空格 / 句末不加 / 保留所有）
- 数字英文前后空格
- 口水词去除（正常 / 激进）
- 离线语音切换（云端逆向接口本质就是云端，无离线）

**判定**：豆包 App 这些选项是客户端本地后处理，字节服务器不暴露这些参数。要在 Voicing Desktop 实现需自研后处理层。

**PoC 决策**：方案 B —— 只暴露 `enable_punctuation` 总开关到托盘菜单；其他四项后处理留到正式版再考虑。

---

## 30. 双热键模式架构

用户需求：同时支持两种触发方式
- **按住模式（hold）**：按下 KeyDown 开始录音 → KeyUp 结束并发送
- **点击模式（toggle）**：单击 Click 开始 → 再单击 Click 结束并发送

技术实现要点：
- `keyboard` 库支持 `on_press` / `on_release` 事件，可分别监听
- toggle 模式实现：维护 bool 状态，每次 KeyDown 翻转
- 两个热键共享同一个 `keyboard.hook()` 回调，避免双钩子互相干扰
- toggle 模式**不加超时**（用户决策），完全依赖用户主动点停
- 弹窗录入热键时必须 unhook 主热键，避免录入时误触

跨平台差异：
- Windows / Linux X11：`keyboard` 库直接工作
- macOS：`keyboard` 不支持，需 `pynput` fallback
- Linux Wayland：两个库都受限，建议 PoC 直接阻断（提示用户切 X11）

---

## 31. 暂停（PAUSED）状态实现

用户决策菜单名「启用 Voicing」，关闭时：
- 卸载所有热键钩子（`keyboard.unhook_all()` 或 `pynput.GlobalHotKeys.stop()`）
- 图标切灰色常亮
- tooltip 改「Voicing · 已暂停」
- 任何热键操作不响应

打开时反向操作：重新注册热键钩子 + 图标恢复蓝色 + 状态进入 IDLE。

注意：暂停状态下「设置热键」弹窗仍可正常使用（弹窗自带 hook，与主热键独立）。

---

## 32. 视觉状态机最终定稿

| 状态 | 视觉 | 周期 |
|---|---|---|
| PAUSED | 灰色常亮 | — |
| IDLE | 蓝色常亮 | — |
| RECORDING | 蓝色闪烁 | 500ms |
| TRANSCRIBING | 蓝色呼吸灯 | 800ms 渐亮渐暗 |
| INJECTING | 蓝色呼吸灯（同上） | 800ms |
| ERROR | 红色闪烁 → 3s 后自动回 IDLE | 500ms |

设计原则：
- 所有正常态都是蓝色（保持品牌一致性）
- 灰色专属 PAUSED
- 红色专属 ERROR
- 闪烁=正在收音；呼吸灯=正在处理

---

## 33. doubaoime-asr 对接的确实是豆包输入法 APK 同款后端（2026-04-22 确认）

通过阅读 `device.py` / `config.py` / `asr.py` / `wave_protocol.md` 源码交叉验证：

**5 条独立证据**：
1. `device.py` 的 `DeviceRegisterHeaderField` 含完整 Android 设备指纹字段：`device_brand` / `device_model` / `os_version` / `os_api` / `cpu_abi` / `resolution` / `dpi` / `rom` / `rom_version` / `build_serial` / `serial_number`——这是伪装 Android 设备而非调用开放 API
2. `APP_CONFIG` 含 `aid` / `channel` / `app_name` / `version_code` / `version_name`，取值从豆包输入法 APK 提取
3. 服务端域名：`keyhub.zijieapi.com`（字节密钥交换）+ `speech.bytedance.com`（语音服务），都是字节内部服务，非火山引擎公开 API
4. 协议完全复刻 APK：Wave 加密（ECDH+AES）、protobuf 序列化、`StartTask`/`StartSession`/`TaskRequest`/`FinishSession` 方法、Opus 音频编码、`x-ss-stub = MD5(body)` 字节标准签名
5. 作者自述："通过对安卓豆包输入法客户端通信协议分析并参考客户端代码实现"

**结论**：
- 识别效果 = 豆包手机端云端识别（不是降级版、不是离线 150MB 本地模型）
- 同一个服务器、同一个模型、同��个接口
- 无需付费（模拟的就是 APK 免费用户）
- 未知风险：字节可能对单 device_id 有隐性限流，无公开文档

---

## 34. 软件工程审查：5 个严重 + 7 个中等漏洞（已全部修复到 task_plan.md）

2026-04-22 对 task_plan.md 做完整软件工程审视，发现 20 处漏洞，关键 5 个已修复：

### ⚠️ 严重漏洞（已修）

**#1 注入失败无处理分支**
- 原问题：`INJECTING → IDLE` 假设永远成功，忽略焦点切走/剪贴板锁/按键被拦截
- 修复：新增 `INJECTING → ERROR`（剪贴板异常 / 模拟按键被拦截）

**#2 剪贴板还原可能覆盖用户新复制内容**
- 原问题：盲目 100ms 后还原，用户可能在期间主动复制了新东西
- 修复：还原前比对 hash，若已变则不还原；考虑 Windows SendInput 作 Phase 3 优化

**#3 Worker 线程取消语义未定义**
- 原问题：60s 超时、PAUSED 强制中止时，录音/ASR worker 怎么停？
- 修复：
  - Audio worker：`threading.Event` + callback 主动 break
  - ASR worker：`asyncio.Task.cancel()` + httpx/websocket close()
  - Inject worker：不可中断（100-300ms 内完成），try/except 兜底

**#4 单实例保护方案未选型**
- 原问题：写了「单实例保护 ✅」但没说怎么做
- 修复：
  - Windows：`CreateMutexW("Global\\VoicingDesktop")`
  - macOS/Linux：`fcntl.flock()` on PID 文件
  - 启动时验证 PID 是否真在跑（幽灵锁清理）

**#5 credentials.json 并发写入保护**
- 原问题：连续两次 401 并发触发 register_device，可能损坏 JSON
- 修复：`asyncio.Lock` 串行化 register + 原子写（写 .tmp → os.replace）

### ⚡ 中等漏洞（已修）

**#6 Toggle 模式用 KeyDown 还是 KeyUp 未明确** → 统一用 KeyUp 边沿触发
**#7 热键"包含关系"定义模糊** → 明确为子集关系：A ⊆ B → 拒绝
**#8 ERROR 状态 3s 自动恢复会吞掉连续错误** → 每次新 ERROR 重置定时器
**#9 静音检测的提示方式未定** → 托盘 INFO 1s（不用系统通知）
**#10 配置热重载语义边界未定** → 明确「下次调用生效，已在飞的不变」
**#11 自动 Enter 跨平台键名** → 直接复用 `keyboard.press_and_release('enter')`
**#12 录入弹窗边界未覆盖** → 前置条件 `state == IDLE`，否则菜单项灰化

### 💡 建议项（已加入 Step 11-14）

- Step 11：ASR engine 抽象契约（为 Whisper fallback 留口子）
- Step 12：启动自检流程（doubaoime-asr import / 麦克风 / 网络 / credentials）
- Step 13：软关闭协议（SIGINT / SIGTERM / Windows close 统一走 app.shutdown()）
- Step 14：PoC → 正式版过渡（Phase 3 占位）

---

## 35. 双热键用户录入流程最终设计（2026-04-22）

用户追问："怎么让用户录入那两个热键"，专门新增 0.9 节完整定义用户流程：

- 两个热键的语义差异（hold=短句快说，toggle=长段口述）
- 两个独立菜单入口
- 弹窗标题/副文案/规则提示的文案差异
- 实时 ✓/✗ 校验反馈
- 「恢复默认」按钮
- 弹窗打开时完全卸载主热键 hook（避免误触）
- 弹窗关闭时重注册两个热键（不是只注册被改的）
- 子集关系冲突校验（hold ⊆ toggle 或 toggle ⊆ hold → 拒绝）
- 跨平台键名映射表
