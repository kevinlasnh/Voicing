# Task Plan: Voicing

## Sedimentation Checkpoint
Last sedimented: 2026-04-20 17:37
Sedimented items: 18 （详见 .brv/context-tree/，待审批已全部 approve）
项目日记见 progress.md

## Current Phase
Phase 2：Voicing Desktop 部署计划（功能闭环已锁定，待 Codex 审查）

---

### Phase 1: 跨平台 Release 资产真实设备验收
- **Status:** pending（搁置，等 Phase 2 验证后再回来）

---

### Phase 2: Voicing Desktop（豆包输入法逆向接口路径）

- **Status:** in_progress — 功能闭环已锁定，前后端分工已定
- **分支**：`feature/desktop-native-asr-research`
- **核心目标**：Voicing 在电脑端独立运行，全程不需要手机
- **用户硬约束**（不可谈判）：
  1. 只用豆包输入法本身（`starccy/doubaoime-asr`），不走火山引擎云 API
  2. 原 Voicing 架构（`android/` + `pc/`）零改动，PoC 全部隔离在 `poc/desktop_asr/`
  3. 桌面端只有右键托盘，不开主窗口（设置热键弹临时小窗口，用完即关）
  4. 热键支持用户在 GUI 内自定义录入

#### 前后端分工（2026-04-22 更新）

| 职责 | 负责人 | 范围 |
|---|---|---|
| **全部代码实现** | **Codex** | 前端（托盘 UI / 设置小窗口 / 视觉状态机 / 热键录入）+ 后端（ASR / 录音 / 注入 / 状态机 / config / 日志 / 单实例 / credentials / worker）|
| **前端微调** | **Claude Code** | Codex 实现完成后，对前端 UI 做视觉/交互微调以符合用户要求 |
| **接口契约** | 见下方 | 前端通过 Qt signal 调后端；后端通过 Qt signal 通知前端状态变化 |

Codex 执行范围：**Step 1-14 全部**。Claude Code 在 Codex 完成后做前端微调。

---

#### 前后端接口契约（Qt signal/slot）

##### 前端 → 后端（前端发出，后端监听）

| Signal 名 | 参数 | 触发时机 | 后端响应 |
|---|---|---|---|
| `sig_enable_changed` | `bool enabled` | 用户切换「启用 Voicing」 | True → 注册热键进 IDLE；False → 卸载热键进 PAUSED |
| `sig_config_changed` | `str key, object value` | 用户切换自动 Enter / 标点 / 开机自启 / 隐私声明确认 | 更新内存 config + 原子写 config.json |
| `sig_hotkey_register_request` | `str target, list[str] keys` | 设置小窗口请求试注册 | target="hold"/"toggle"，后端尝试 OS 注册，结果通过 `sig_hotkey_register_result` 回传 |
| `sig_hotkey_dialog_opened` | 无 | 设置小窗口打开 | 后端卸载所有主热键 hook（避免录入时误触） |
| `sig_hotkey_dialog_closed` | 无 | 设置小窗口关闭 | 后端重新注册两个主热键（确保状态一致） |
| `sig_quit_requested` | 无 | 用户点「退出」 | 后端执行 `app.shutdown()` 软关闭协议 |

##### 后端 → 前端（后端发出，前端监听）

| Signal 名 | 参数 | 触发时机 | 前端响应 |
|---|---|---|---|
| `sig_state_changed` | `str new_state, str detail` | 状态机每次转换 | 前端切换图标 6 态 + 更新 tooltip（detail 用于 ERROR 时显示原因） |
| `sig_hotkey_register_result` | `str target, bool success, str error` | 热键注册完成 | 设置小窗口显示 ✓（success=True）或 ✗ + error 文案 |
| `sig_health_check_result` | `dict results` | 启动自检完成 | results 格式：`{"doubaoime": bool, "microphone": bool, "network": bool, "credentials": bool}`；任一 False → 托盘 ERROR + tooltip |
| `sig_asr_error` | `str error_type, str message` | ASR 失败 | error_type: "network"/"token"/"protocol"；前端在 ERROR tooltip 显示 message |
| `sig_recording_info` | `str info_type, str message` | 静音/误触/超时 | info_type: "silence"/"debounce"/"timeout"；前端短暂 INFO 提示 1s |

##### 共享数据结构（`voicing_desktop/shared.py`）

```python
from enum import Enum
from dataclasses import dataclass, field
from typing import Optional

class VoicingState(str, Enum):
    PAUSED = "paused"
    IDLE = "idle"
    RECORDING_HOLD = "recording_hold"
    RECORDING_TOGGLE = "recording_toggle"
    TRANSCRIBING = "transcribing"
    INJECTING = "injecting"
    ERROR = "error"

@dataclass
class ASRResult:
    text: str
    duration_ms: int
    engine: str  # "doubao_ime" / "whisper_local"
    raw_response: Optional[dict] = None

@dataclass
class VoicingConfig:
    version: int = 1
    privacy_accepted: bool = False
    enabled: bool = True
    hotkey_hold: list[str] = field(default_factory=lambda: ["ctrl", "alt", "v"])
    hotkey_toggle: list[str] = field(default_factory=lambda: ["ctrl", "alt", "b"])
    auto_enter: bool = False
    enable_punctuation: bool = True
    autostart: bool = False
    asr_engine: str = "doubao_ime"
    asr_credential_path: str = "doubao-credentials.json"
    asr_sample_rate: int = 16000
    audio_min_duration_ms: int = 200
    audio_max_duration_seconds: int = 60
    audio_vad_rms_threshold: float = 0.005
```

##### 调用方向规则（Codex 实现时必须遵守）

| 规则 | 说明 |
|---|---|
| 前端**禁止**直接调后端函数 | 必须通过 signal，保证线程安全 |
| 后端**禁止**直接改 UI | 必须通过 signal 回主线程 |
| config 写入**只有后端做** | 前端发 `sig_config_changed`，后端负责落盘 |
| 状态机**只有后端改** | 前端只读 `sig_state_changed` |
| 热键注册/卸载**只有后端做** | 前端发请求，后端执行并回传结果 |
| 共享结构在 `shared.py` | 前后端 import 同一份，避免定义漂移 |

---

#### Step 0：功能闭环清单（✅ 已锁定 2026-04-22）

##### 0.1 核心链路
| 功能 | 说明 | 决策 |
|---|---|---|
| 双热键触发 | 热键 A：按住说话松开发送；热键 B：点击开始/再点击停止发送 | ✅ |
| 录音 | sounddevice 16kHz mono PCM | ✅ |
| 豆包 ASR 识别 | `starccy/doubaoime-asr` 逆向接口 | ✅ |
| 剪贴板注入到光标 | `pyperclip` + `Ctrl+V`（macOS `Cmd+V`） | ✅ |
| 自动 Enter（开关） | 识别后自动回车，默认关，托盘菜单可切换 | ✅ |
| 注入后剪贴板还原 | 注入前保存 → 注入后 100ms 还原 | ✅ |
| 标点开关 | doubaoime-asr `enable_punctuation` 总开关，托盘菜单可切换 | ✅ |

##### 0.2 托盘 UI（唯一 GUI 入口）
```
┌──────────────────────────────────────────┐  ← rgba(32,32,32,245) + 8px 圆角
│  🎤 按住 Ctrl+Alt+V · 点击 Ctrl+Alt+B    │  ← 灰色状态行，不可点击
├──────────────────────────────────────────┤
│  ✓ 启用 Voicing                          │  ← 开关（关=热键全失效+图标灰）
│    设置热键...                            │  ← 打开设置小窗口（两个热键并列）
│  ✓ 自动 Enter                            │  ← 开关
│  ✓ 标点                                  │  ← 开关
│    开机自启                               │  ← 开关（关=无 ✓）
├──────────────────────────────────────────┤
│    打开日志                               │
│    打开配置目录                           │
│    关于 Voicing                           │
├──────────────────────────────────────────┤
│    退出                                   │
└──────────────────────────────────────────┘
```
- 完全复用 v2.7.2 的 `ModernMenuWidget` 设计 token（见下方前端规范）
- 菜单入口从 2 个合并为 1 个「设置热键...」（小窗口内并列两个热键）
- PoC 期独立实现，不复制 `pc/` 代码

##### 0.3 视觉状态机
| 状态 | 图标视觉 | tooltip |
|---|---|---|
| PAUSED | 灰色常亮 | Voicing · 已暂停 |
| IDLE | 蓝色常亮 | Voicing · 按住 Ctrl+Alt+V 或点击 Ctrl+Alt+B 说话 |
| RECORDING | 蓝色闪烁（500ms 周期） | Voicing · 正在录音... |
| TRANSCRIBING | 蓝色呼吸灯（渐亮渐暗 800ms 周期） | Voicing · 正在识别... |
| INJECTING | 蓝色呼吸灯（同上，与 TRANSCRIBING 视觉一致） | Voicing · 正在输入... |
| ERROR | 红色闪烁（500ms 周期，持续 3s 后回 IDLE） | Voicing · 错误：{原因} |

##### 0.4 热键录入交互
- 弹窗实时捕获 KeyDown/KeyUp 组合键 → ✅
- 合法性校验（拒绝单字母/系统占用键） → ✅
- 两个热键不能相同、不能有包含关系 → ✅
- 保存后即时生效（卸旧注新，失败回滚） → ✅
- Esc 取消不保存 → ✅
- 弹窗期间禁用主热键监听 → ✅

##### 0.5 边界与鲁棒性
| 场景 | 处理 | 决策 |
|---|---|---|
| 按住模式短按 <200ms | 视为误触丢弃 | ✅ |
| 按住模式长按 >60s | 自动停止并丢弃 | ✅ |
| toggle 模式无超时 | 用户自己点停止 | ✅ |
| 静音（RMS 太低） | 不调 ASR，托盘提示 | ✅ |
| 嵌套触发（录音中再按热键） | 忽略 | ✅ |
| 网络超时 8s | ERROR 状态，托盘提示 | ✅ |
| token 失效 401/403 | 清 credentials，下次自动重注册 | ✅ |
| 豆包协议变更 | ERROR + 托盘红闪 | ✅ |
| 热键被系统占用 | 注册失败 → 回退默认 + 警告 | ✅ |

##### 0.6 明确驳回的功能
| 功能 | 驳回理由 |
|---|---|
| 退出前二次确认 | 用户不需要 |
| 麦克风占用/拔掉检测 | 用户用 DJI Mic Type-C，自己管理 |
| Esc 长按紧急中止 | 与按住模式冲突 |
| 撤回上次输入 | 桌面端不存在输入框跑空问题 |
| 最近识别历史 | 电脑端本来都是文本框 |
| 识别前预览 toast | 打断心流 |
| 音量条预览 | 收益低 |
| 系统通知 toast | 托盘闪烁已够 |
| 多方言选择 | 大部分用户不需要 |
| 检查更新 | PoC 阶段不做 |
| 四档标点模式 / 数字英文空格 / 口水词去除 / 离线语音 | doubaoime-asr 不支持，需自研后处理层，PoC 不做 |
| 麦克风选择 | 用户不需要 |
| Desktop 主窗口 | 只做托盘 |
| 二级菜单 | 识别配置只剩标点总开关，不需要二级菜单 |

##### 0.7 系统集成
| 功能 | 决策 |
|---|---|
| 跨平台托盘（Windows / macOS / Linux X11） | ✅ |
| 开机自启（复用 `pc/platform_autostart.py` 逻辑） | ✅ |
| 配置持久化 `%APPDATA%/Voicing/desktop/config.json` | ✅ |
| 日志按日 rotate 保留 7 天 | ✅ |
| 单实例保护 | ✅ |
| 进程名 `Voicing Desktop` | ✅ |
| 首启隐私声明弹窗 | ✅ |
| 关于页（版本号 + 第三方声明） | ✅ |

##### 0.8 Android 端
- ✅ 完全不修改 `android/` 目录
- 双形态共存：Voicing Desktop 独立 + Voicing Mobile 原样保留
- 去留留到 PoC 通过后决策

##### 0.9 双热键录入用户流程（✅ 已锁定）

详见 Step 5。核心决策：
- 方案 A：弹临时设置小窗口（业界标准，Discord / ShareX / Snipaste 同款）
- 托盘菜单 1 个聚合入口「设置热键...」，小窗口内两个热键并列
- 录入即时生效（不等关窗），失败即时回滚
- 窗口打开时卸载主热键 hook，关闭时重注册
- 默认值：hold = `Ctrl+Alt+V`，toggle = `Ctrl+Alt+B`

---

#### Step 1：环境前提核实（pending）

**目标**：把假设变成已核实

| 子步骤 | 动作 | 验收 |
|---|---|---|
| 1.1 | clone `starccy/doubaoime-asr`，阅读 `pyproject.toml` / `wave_protocol.md` / `examples/` / `gen_proto.sh`，结论写 `findings.md` #29 | 依赖清单 + protobuf 握手细节已记录 |
| 1.2 | Windows 11 跑通 doubaoime-asr example：注册 device → 拿 token → 识别一段 wav | 一行命令能出识别结果 |
| 1.3 | 核实 Opus 在 Windows 的安装方式（pyogg wheel 自带 / 需手装 opus.dll） | 安装路径已固化 |
| 1.4 | 版权边界：doubaoime-asr 无 LICENSE → 禁止 vendor，只作 pip 依赖；README 声明第三方非官方 | 法律边界已记录 |

---

#### Step 2：目录结构与依赖契约（pending）

**目标**：建立完整骨架

```
poc/desktop_asr/
├── README.md
├── pyproject.toml
├── voicing_desktop/
│   ├── __init__.py
│   ├── __main__.py              # python -m voicing_desktop
│   ├── app.py                   # QApplication + 生命周期 + 单实例锁
│   ├── config.py                # config.json 读写 + schema 校验
│   ├── logging_setup.py         # 日志 rotation
│   ├── hotkey/
│   │   ├── __init__.py
│   │   ├── listener.py          # 双热键监听（hold + toggle）
│   │   ├── recorder.py          # 热键录入弹窗捕获
│   │   └── normalize.py         # 跨平台键名归一化
│   ├── audio/
│   │   ├── __init__.py
│   │   └── capture.py           # sounddevice 16kHz mono
│   ├── asr/
│   │   ├── __init__.py
│   │   ├── engine.py            # ASR 抽象接口
│   │   └── doubao_ime.py        # 调 doubaoime-asr
│   ├── injection/
│   │   ├── __init__.py
│   │   └── injector.py          # 剪贴板注入 + 还原 + 可选 Enter
│   ├── tray/
│   │   ├── __init__.py
│   │   ├── icon.py              # 托盘图标 6 态视觉
│   │   ├── menu.py              # 右键菜单
│   │   ├── hotkey_dialog.py     # 热键录入弹窗
│   │   └── privacy_dialog.py    # 首启隐私声明
│   └── state.py                 # 全局状态机
├── tests/
│   ├── test_config.py
│   ├── test_normalize.py
│   ├── test_state.py
│   └── test_injector_smoke.py
└── docs/
    ├── architecture.md
    └── known-issues.md
```

Python 依赖（`pyproject.toml`）：
- `doubaoime-asr` @ `git+https://github.com/starccy/doubaoime-asr.git@<pin-sha>`
- `PyQt5` ~= 5.15.11
- `sounddevice` ~= 0.5.0
- `numpy`（与 doubaoime-asr 对齐）
- `keyboard` ~= 0.13.5（Windows/Linux）
- `pynput` ~= 1.7.7（macOS fallback）
- `pyperclip` ~= 1.11.0
- `opuslib` 或 `pyogg`（Step 1.3 决定）
- dev: `pytest` / `pytest-asyncio` / `pytest-qt`

**验收**：clean venv `pip install -e .` 通过

---

#### Step 3：状态机与数据流（pending）

**目标**：双热键 + 暂停 + 错误完整覆盖的状态机

完整状态机（11 状态，含所有错误分支）：

```
PAUSED        ── 启用 Voicing 打开 ──→  IDLE
IDLE          ── 启用 Voicing 关闭 ──→  PAUSED

# 触发录音
IDLE          ── hold 热键 KeyDown ──→  RECORDING_HOLD
IDLE          ── toggle 热键 KeyUp ──→  RECORDING_TOGGLE  # 注意：toggle 用 KeyUp 边沿触发，避免与 hold 视觉一致

# 结束录音
RECORDING_HOLD    ── hold 热键 KeyUp ──→    TRANSCRIBING
RECORDING_TOGGLE  ── toggle 热键 KeyUp ──→  TRANSCRIBING

# 录音异常分支
RECORDING_HOLD    ── 录音 > 60s ──→         IDLE（丢弃 + 托盘 INFO 提示）
RECORDING_TOGGLE  ── 用户无超时 ──→         依赖用户主动再按 toggle 热键
RECORDING_HOLD    ── KeyUp < 200ms ──→      IDLE（误触丢弃，静默）
ANY_RECORDING     ── 静音（RMS<阈值）──→    IDLE（托盘 INFO 提示 1s）
ANY_RECORDING     ── 启用 Voicing 关闭 ──→  PAUSED（强制丢弃当前录音）
ANY_RECORDING     ── 麦克风异常 ──→         ERROR（sounddevice callback 抛异常）

# ASR 阶段
TRANSCRIBING  ── ASR 成功 ──→               INJECTING
TRANSCRIBING  ── 网络超时 8s ──→            ERROR
TRANSCRIBING  ── token 失效 401/403 ──→     RE_REGISTER（见下）
TRANSCRIBING  ── 协议解析失败 ──→           ERROR
TRANSCRIBING  ── 启用 Voicing 关闭 ──→      PAUSED（cancel 正在进行的 HTTP 请求）

# 自动重注册（新增）
RE_REGISTER   ── 注册成功 ──→               TRANSCRIBING（重试一次）
RE_REGISTER   ── 注册失败 ──→               ERROR

# 注入阶段（补全错误分支）
INJECTING     ── 注入成功 ──→               IDLE
INJECTING     ── 剪贴板异常 ──→             ERROR（pyperclip 抛异常）
INJECTING     ── 模拟按键被拦截 ──→         ERROR

# 错误恢复
ERROR         ── 3s 定时器 ──→              IDLE（新 ERROR 重置定时器，不累加）

# 通用忽略
PAUSED        ── 任何热键 ──→               忽略
ANY_RECORDING ── 嵌套触发 ──→               忽略
```

线程模型（明确取消语义）：
- **Qt 主线程**：状态机切换 + UI 更新（唯一状态写入者）
- **Audio worker**（sounddevice InputStream 的 callback 线程）：
  - 取消机制：`threading.Event`，callback 每次检查 event.is_set() 主动 break
  - stream.stop() + stream.close() 必须在释放前完成
- **ASR worker**（单独线程跑 asyncio event loop）：
  - 取消机制：`asyncio.Task.cancel()` + 底层 httpx/websocket client 的 close()
  - 必须在 `await` 点响应 CancelledError
- **Inject worker**：
  - 不可中断（仅 100-300ms 完成），但必须 try/except 兜底
- 所有跨线程通信通过 Qt signal/slot 回主线程，禁止 worker 直接改状态

单实例保护：
- Windows：`CreateMutexW("Global\\VoicingDesktop")`
- macOS / Linux：`fcntl.flock()` on `%APPDATA%/Voicing/desktop/voicing.pid`
- 启动时检查：若发现已有进程 → 读 PID → 用 OS API 验证进程是否真的在跑（避免崩溃遗留的幽灵 PID）→ 未运行则清理后续启；已运行则退出
- 退出时必须清理锁

credentials.json 并发保护：
- 全局 `asyncio.Lock()` 保护 register_device()（串行化）
- 写 credentials.json 用原子写：写 `.tmp` → `os.replace()` → 成功后清 `.tmp`
- 连续两次 401 并发触发 RE_REGISTER 时，第二次必须 await 第一次结果

ASR 调用边界：
- 网络超时 8s → ERROR
- token 失效 401/403 → 进入 RE_REGISTER 状态，清 credentials.json，自动重注册并重试一次
- 协议解析失败 → ERROR + 日志记录完整响应体便于后期定位
- 连续 3 次 RE_REGISTER 失败 → 进入长期 ERROR 状态，等待用户手动点「重置豆包凭证」

文本注入边界（修复剪贴板竞态）：
- 注入前保存原剪贴板内容 + 计算 sha256 hash（`clipboard_guard.py`）
- 注入后等 `Ctrl+V` 触发的目标应用处理完（默认 150ms，可配置）
- 还原前再次读剪贴板，计算 hash：
  - 若仍是刚注入的识别文本 → 还原为原内容
  - 若已变（用户主动复制了新东西）→ 不还原，日志记录
- Windows 可选优化：用 `SendInput` 直接发 unicode 字符（绕过剪贴板，无还原问题），作为 Phase 3 优化
- 跨平台粘贴：Windows/Linux `Ctrl+V`；macOS `Cmd+V`
- Enter 按键：直接调用 `keyboard.press_and_release('enter')`，不走剪贴板

配置热重载边界：
- 「自动 Enter / 标点 / 开机自启」切换 → 立即改内存对象 + 原子写 config.json
- **语义约定**：变更只影响下次触发的 ASR 调用，正在飞的请求不受影响
- `enable_punctuation` 变更：下次 `asr.transcribe()` 调用用新值
- `auto_enter` 变更：下次 INJECTING 阶段用新值

**验收**：`tests/test_state.py` 覆盖以上全部 26 条转换 + 单实例崩溃恢复测试 + 剪贴板 hash 竞态测试

---

#### Step 4：托盘 UI 实现（pending）— Claude Code 前端

**设计 token（从 v2.7.2 `ModernMenuWidget` 提取，必须完全复用）**：

| Token | 值 | 用途 |
|---|---|---|
| `bg_container` | `rgba(32, 32, 32, 245)` | 菜单/窗口背景 |
| `border_subtle` | `rgba(255, 255, 255, 0.08)` | 边框 + 分隔线 |
| `hover_bg` | `rgba(255, 255, 255, 15)` | 悬停 |
| `press_bg` | `rgba(255, 255, 255, 25)` | 按压 |
| `accent` | `#60CDFF` | 开关 ✓ / 活跃状态 |
| `text_primary` | `#ECECEC` | 主文字 |
| `text_secondary` | `#6B6B6B` | 状态行 / 说明文字 |
| `radius_container` | 8px | 容器圆角 |
| `radius_item` | 4px | 菜单项圆角 |
| `item_height` | 36px | 菜单项高度 |
| `font_size` | 14px | 菜单文字 |
| `font_family` | 系统原生 `NATIVE_FONT_FAMILY` | 字体 |
| `animation` | 160ms easeOutQuad 滑入 + 淡入 | 菜单弹出 |
| `shadow` | blur 24, offset (0,4), alpha 100 | 容器阴影 |

**实现要点**：
- 图标资源：复用 `pc/` 现有圆形图标，按 6 态（PAUSED/IDLE/RECORDING/TRANSCRIBING/INJECTING/ERROR）生成预缓存
- 菜单：按 0.2 结构实现
- 「启用 Voicing」开关：切换 PAUSED ↔ IDLE，通过 Qt signal 通知后端
- 「自动 Enter」/「标点」/「开机自启」：切换 config 对应字段，通过 Qt signal 通知后端
- 「设置热键...」：打开设置小窗口（见 Step 5）
- 「打开日志」/「打开配置目录」：调用系统默认应用
- 「关于 Voicing」：弹窗显示版本号 + 第三方声明
- 「退出」：调用后端 `app.shutdown()` 协议
- tooltip：实时显示当前状态 + 当前热键
- 定位逻辑：复用 v2.7.2 的 `show_at_position`（Windows 底部向上弹，macOS/Linux 向下弹）

**验收**：Windows 真机托盘菜单弹出、视觉与 v2.7.2 一致、所有项点击响应正确

---

#### Step 5：热键录入——临时设置小窗口（pending）— Claude Code 前端

**决策（2026-04-22）**：方案 A——弹临时 preference dialog，业界标准做法（Discord / ShareX / Snipaste 均如此）。这不是"Desktop 主窗口"，是用完即关的设置对话框，与"纯托盘"定位兼容。

**前置约束**：弹窗打开前 `state` 必须 `== IDLE`，否则托盘菜单灰化「设置热键...」入口。

设置小窗口布局（约 420×380，无标题栏，暗色 Fluent 风格）：
```
┌──────────────────────────────────────────┐  ← bg_container + 8px 圆角 + 阴影
│                                            │
│  设置热键                                  │  ← text_primary 16px 加粗
│                                            │
│  ┌ 按住说话 ─────────────────────────┐   │  ← border_subtle 圆角分组框
│  │  按住此键期间录音，松开自动发送      │   │  ← text_secondary 12px
│  │                                      │   │
│  │  ┌──────────────────────────┐      │   │
│  │  │  Ctrl + Alt + V           │      │   │  ← 当前值 / 捕获中实时显示
│  │  └──────────────────────────┘      │   │
│  │  [录入新热键]                        │   │  ← 点击后变"按下任意键..."
│  └──────────────────────────────────┘   │
│                                            │
│  ┌ 点击切换 ─────────────────────────┐   │
│  │  按一下开始录音，再按一下结束发送    │   │
│  │                                      │   │
│  │  ┌──────────────────────────┐      │   │
│  │  │  Ctrl + Alt + B           │      │   │
│  │  └──────────────────────────┘      │   │
│  │  [录入新热键]                        │   │
│  └──────────────────────────────────┘   │
│                                            │
│       [恢复默认]           [关闭]          │
└──────────────────────────────────────────┘
```

**交互流程**：
1. 用户点托盘菜单「设置热键...」→ 弹出小窗口（modal，居中）
2. 窗口打开时：**完全卸载主热键 hook**（避免录入时误触录音）
3. 两个热键区域并列，各自有「录入新热键」按钮
4. 用户点「录入新热键」→ 按钮变"按下任意键..."，该区域进入捕获模式
5. 用户按下组合键 → 实时显示（如 `Ctrl + Alt + M`）
6. 用户全部松开 → 立刻校验：
   - ✓ 合法 → **即时注册到 OS**（不等关窗）→ 成功则更新显示 + config 落盘
   - ✗ 不合法 → 显示红色提示（如"与另一个热键冲突"）→ 恢复旧值
   - ✗ OS 注册失败 → 显示红色提示"可能被其他软件占用" → 恢复旧值
7. 「恢复默认」→ 两个热键恢复默认值（Ctrl+Alt+V / Ctrl+Alt+B），即时注册
8. 「关闭」→ 关闭窗口 + **重新注册两个主热键**（确保状态一致）
9. Esc 也关闭窗口

**校验规则**（同之前）：
- 拒绝：单字母/数字/F 键（无 modifier）
- 拒绝：单 Esc / Enter / Space / Tab / Backspace
- 拒绝：系统占用键黑名单（Win+L / Cmd+Tab / Ctrl+Alt+Del）
- 拒绝：与另一个热键有子集关系（A ⊆ B → 拒绝）
- 拒绝：OS 注册失败

**跨平台键名归一化**：
- 内部存储：`["ctrl", "alt", "v"]`（小写，字母排序）
- Windows/Linux 显示：`Ctrl + Alt + V`
- macOS 显示：`⌃ ⌥ V`

**视觉规范**：
- 窗口背景/圆角/阴影/字体：完全复用 Step 4 的设计 token
- 分组框：`border_subtle` 1px 边框 + 4px 圆角
- 「录入新热键」按钮：`accent` 色文字，hover 加底色
- 校验成功：`accent` 色 ✓
- 校验失败：`#E85C4A` 红色 ✗ + 红色提示文字
- 窗口可拖拽（鼠标按住空白区域）

**验收**：
- 录入 Ctrl+Alt+V 即时生效
- 纯字母键被拒绝 + 红色提示
- 两个热键设相同被拒绝
- Esc / 关闭按钮正确关窗
- 恢复默认正确
- 窗口视觉与托盘菜单风格一致

---

#### Step 6：首启隐私声明 + 日志 + 配置（pending）

首启隐私声明弹窗（`tray/privacy_dialog.py`）：
- 首次运行时弹出，告知用户音频会发送到字节跳动服务器进行识别
- 用户点「我知道了」后写入 config.json `privacy_accepted: true`，不再弹出
- 用户点「退出」→ 直接退出应用

配置文件 `%APPDATA%/Voicing/desktop/config.json`：
```json
{
  "version": 1,
  "privacy_accepted": false,
  "enabled": true,
  "hotkey_hold": ["ctrl", "alt", "v"],
  "hotkey_toggle": ["ctrl", "alt", "b"],
  "auto_enter": false,
  "enable_punctuation": true,
  "autostart": false,
  "asr": {
    "engine": "doubao_ime",
    "credential_path": "doubao-credentials.json",
    "sample_rate": 16000
  },
  "audio": {
    "min_duration_ms": 200,
    "max_duration_seconds": 60,
    "vad_rms_threshold": 0.005
  }
}
```

日志：
- 路径：`%APPDATA%/Voicing/desktop/logs/desktop-YYYY-MM-DD.log`
- 按日 rotate，保留 7 天
- INFO 默认，`VOICING_DESKTOP_LOG=DEBUG` 打开 DEBUG
- 绝不记录：原始音频、识别原文
- 必须记录：状态切换、ASR 耗时、热键注册结果、错误堆栈

schema 校验：缺字段填默认值；非法时备份为 `.bak.<timestamp>` 后重建

**验收**：首启弹窗出现 / 删 config 重启自动重建 / 非法字段备份+重建

---

#### Step 7：测试矩阵（pending）

单元测试（pytest）：
- `test_config.py`：默认值 / schema 校验 / 备份恢复
- `test_normalize.py`：键名归一化 + 跨平台显示
- `test_state.py`：状态机全部转换 + 双热键 + 暂停 + 边界条件
- `test_injector_smoke.py`：剪贴板保存还原

集成测试（手工 checklist）：
- Windows 11：hold 热键 → 说话 → 注入记事本 / VS Code / 浏览器
- Windows 11：toggle 热键 → 说话 → 再点 → 注入
- 暂停开关关闭 → 热键无响应 → 图标灰色
- 网络断开 → 热键 → ERROR 红闪
- 删 token → 热键 → 自动重注册
- 两个热键设相同 → 被拒绝

性能基准：
- 端到端延迟（按下到出字）≤ 2s
- 录音内存 ≤ 50MB
- 空闲 CPU ≤ 1%

**验收**：单元测试全绿；集成测试 Windows 11 全通过

---

#### Step 8：风险矩阵与回滚（pending）

| 风险 | 触发 | 检测 | 缓解 |
|---|---|---|---|
| 豆包协议变更 | 字节升级 server | 启动自检 + ASR 失败率 | 升级 doubaoime-asr commit / 长期 Whisper fallback |
| 上游废弃 | 6 月无 commit | `gh repo view` | fork 维护 |
| device_id 被封 | 高频请求 | 401/403 | 多 device_id 池 + 限流 |
| opus.dll 缺失 | 用户机器 | 启动自检 | 安装包内置 dll |
| 热键被占用 | IDE/IM 冲突 | 注册返回 false | UI 提示改键 |
| macOS 辅助功能 | 首次运行 | 启动自检 | 引导用户授权 |

回滚：
- PoC 在独立分支 + 独立目录，main 始终 v2.7.2 可发布
- 失败 → `git checkout main` + 删分支
- 并入主干前需用户二次确认

合规：
- README 声明第三方非官方组件
- 不 vendor doubaoime-asr 源码
- 首启隐私声明弹窗

---

#### Step 9：交付物（pending）

- `poc/desktop_asr/` 完整可运行代码
- `poc/desktop_asr/README.md` 安装与使用
- `poc/desktop_asr/docs/architecture.md` 数据流图 + 状态机
- `poc/desktop_asr/docs/known-issues.md` 排障手册
- `findings.md` #29+ 技术决策依据
- 不涉及：CHANGELOG / CI workflow（PoC 不入 release pipeline）

---

#### Step 10：Codex 审查 checklist

1. 计划是否覆盖所有用户硬约束？
2. 双热键（hold + toggle）状态机是否有遗漏分支？
3. 暂停（PAUSED）状态下所有热键是否确实被忽略？
4. doubaoime-asr 真实可用性是否有未验证假设？
5. Windows opus.dll 安装路径是否已固化？
6. 跨平台差异（macOS 辅助功能 / Linux Wayland 阻断）是否充分？
7. 两个热键的冲突检测逻辑是否完备？
8. 法律 / 隐私（首启声明 + README 声明 + 不 vendor）是否有遗漏？
9. 测试矩阵是否覆盖关键路径？
10. 回滚策略是否安全？
11. 状态机的 ERROR 分支（注入失败、剪贴板异常、RE_REGISTER）是否完整？
12. 剪贴板还原的 hash 防覆盖是否合理？
13. Worker 线程取消语义（audio event / asyncio cancel）是否明确？
14. 单实例保护的崩溃恢复（幽灵 PID 清理）是否健壮？
15. credentials.json 的并发写入保护是否周全？
16. ASR engine 抽象接口契约是否为未来 fallback 留了口子？
17. 配置热重载的语义边界是否清晰？

---

#### Step 11：ASR 引擎抽象契约（pending）

为未来 Whisper fallback / 其他引擎预留接口，`asr/engine.py` 定义：

```python
from typing import Protocol
from dataclasses import dataclass

@dataclass
class ASRResult:
    text: str
    duration_ms: int
    engine: str  # "doubao_ime" / "whisper_local" / ...
    raw_response: dict | None = None  # debug 用

class ASREngine(Protocol):
    async def transcribe(self, pcm: bytes, sample_rate: int, *, enable_punctuation: bool) -> ASRResult: ...
    async def health_check(self) -> bool: ...
    async def close(self) -> None: ...
```

`asr/doubao_ime.py` 实现此接口。新增 engine 只需再实现一个类，不动上层代码。

---

#### Step 12：启动自检（pending）

`app.py` 启动流程：

```
1. 单实例检查（失败 → 弹窗提示后退出）
2. 读 config.json（失败 → schema fallback）
3. 首启隐私声明弹窗（若 privacy_accepted=false）
4. 启动自检（healthcheck.py）：
   - import doubaoime_asr 成功？
   - credentials 文件可读写？
   - 麦克风设备可枚举？
   - 网络可 ping keyhub.zijieapi.com？
5. 自检失败 → 托盘图标进入 ERROR + tooltip 提示具体失败项 + 菜单加「重试自检」
6. 自检通过 → 注册热键 → 进入 IDLE
```

---

#### Step 13：软关闭协议（pending）

退出流程（`app.shutdown()`）：

```
1. 若 state in {RECORDING, TRANSCRIBING, INJECTING}：
   - 取消所有 worker（audio_event.set() + asr_task.cancel()）
   - 等待 worker join（最多 2s，超时强杀）
2. 卸载全局热键 hook（keyboard.unhook_all() / pynput.stop()）
3. 关闭音频设备（stream.close()）
4. flush 日志 + 关闭 handler
5. 清理单实例锁（mutex.close() / 删 PID 文件）
6. QApplication.quit()
```

SIGINT / SIGTERM / Windows close event 都走此流程，禁止直接 os._exit()。

---

#### Step 14：PoC → 正式版过渡（Phase 3 占位）

Status: 预留，PoC 通过后规划

规划要点（不在本次 Codex 审查范围）：
- 目录重命名：`poc/desktop_asr/` → `pc-desktop/`
- 与现有 `pc/` WebSocket 模式的关系：并存 / 替代 / 合并？
- 版本号：v3.0.0（架构 breaking change）
- Android 端去留决策
- release pipeline：是否新增 `voicing-desktop-windows-x64.exe` / macOS / Linux 资产
- CHANGELOG / README / CI workflow 同步更新

---

**当前阻塞**：等 Codex 审查反馈后进入 Step 1 实施
