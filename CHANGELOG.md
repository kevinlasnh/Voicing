# Changelog / 更新日志

All notable changes to this project will be documented in this file.
本文件记录本项目所有重要变更。

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
格式遵循 [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)，版本号遵循 [Semantic Versioning](https://semver.org/spec/v2.0.0.html)。

> **Bilingual policy / 双语说明**: From v2.9.3 onward, each release block is written bilingually (English first, 中文 second). Older release blocks below remain in their original Chinese to preserve linguistic accuracy of historical records. / 自 v2.9.3 起，每个版本块按英文 + 中文双语并排维护；以下早期版本块保留原始中文以确保历史准确性。

---

## [Unreleased]

---

## [2.10.2] - 2026-11-22

### Changed

- Android: the header status cell is back to the plain connection state (`Connected` / `Connecting…` / `Disconnected`) and no longer appends the current device name
- Android: the "Device selection" row in the More menu is now a normal row like every other entry — one small icon plus the four-character label, no device name and no arrow, so all rows share the same height and padding
- Android: the device submenu is laid out as the symmetric left neighbour of the More menu: same width as the header status cell, same gap as the two header buttons, same container/menu-item style and row height. The selected target is shown by the same persistent highlight used when tapping a More-menu row; the green check mark and the trailing delete button were removed
- Android: a long name in a device row now slowly scrolls back and forth like a music-player song title, while short names stay static
- Android: un-pairing a device is now done by long-pressing its row and confirming the dialog (cancel/delete)

### Notes

- No protocol, QR payload or desktop behaviour change: the APK and existing desktop builds stay interchangeable

### 变更

- 手机端：顶部状态格恢复为纯连接状态（已连接 / 连接中… / 未连接），不再拼接当前设备名
- 手机端：「更多功能操作」里的「设备选择」改为与其他项完全一致的一行——统一小图标 + 四字文本，不显示设备名、没有额外箭头，所有行高度与内边距统一
- 手机端：设备子菜单按「更多功能操作」的对称左邻居布局：宽度与顶部状态格一致、与主界面两按钮间距一致、容器与菜单项样式及单元格高度一致。当前发送目标用与点击右侧菜单行相同的常驻高亮表示；去掉了绿色对勾和行尾删除按钮
- 手机端：设备名过长时像音乐播放器歌名一样缓慢来回滚动，短名字保持静止
- 手机端：解绑设备改为长按该设备行，弹出确认框后选择取消/删除

### 说明

- 协议、QR payload 与桌面端行为均未变化：新版 APK 与现有桌面端继续互通

---

## [2.10.1] - 2026-11-22

### Changed

- CI: manual `workflow_dispatch` builds now automatically create or update the GitHub Release for the repository version. The workflow derives the version from `pubspec.yaml` / `APP_VERSION`, creates tag `vX.Y.Z` at the built commit and publishes the APK, Linux DEB, Linux standalone binary and `SHA256SUMS.txt`; the run no longer stops at workflow artifacts. Tag-push releases keep the extra Windows EXE
- CI: release notes are now always extracted from `CHANGELOG.md` for the resolved version (both trigger paths), and the workflow fails if the matching bilingual block is missing, so every automated Release has complete notes
- Docs/agents: a new mandatory release rule requires bumping the version and CHANGELOG whenever all tasks are completed, pushing the changes and triggering the Action so a fresh GitHub Release is published; the APK is installed by the user from the Release, while agents only download the Linux DEB when a local reinstall is needed

### Notes

- No runtime code change: Android and desktop behaviour is identical to 2.10.0

### 变更

- CI：`workflow_dispatch` 手动构建现在会自动创建/更新 GitHub Release。workflow 从 `pubspec.yaml` / `APP_VERSION` 推导版本号，在本次构建的 commit 上创建 tag `vX.Y.Z`，并发布 APK、Linux DEB、Linux standalone 二进制与 `SHA256SUMS.txt`，不再只停留在 workflow artifact。tag 推送发布仍额外包含 Windows EXE
- CI：两条触发路径都会从 `CHANGELOG.md` 提取对应版本的发布说明，缺少该版本双语块时 workflow 直接失败，确保每次自动 Release 都有完整说明
- 文档/Agent：新增强制发版规则——每轮全部任务完成后必须升版本号、写 CHANGELOG、push 并触发 Action，从而自动发布新的 GitHub Release；APK 由用户从 Release 自行安装，agent 只在需要本地重装 Linux 时下载 DEB

### 说明

- 无运行时代码改动：Android 与桌面端行为与 2.10.0 完全一致

---

## [2.10.0] - 2026-11-22

### Added

- Android: multi-device pairing. Every newly scanned PC is appended to the paired-device list instead of replacing the previous one, and re-scanning the same `device_id` only merges its address book and candidate history, so no duplicate entry appears
- Android: all paired PCs now connect concurrently, each with its own WebSocket, heartbeat, reconnect backoff and Happy Eyeballs candidate race, so several PCs on the same WiFi can stay online at the same time
- Android: a "Device selection" entry at the bottom of the "More" menu, right below "Scan to connect". Tapping it opens a secondary menu to the left in the same style as the existing dropdown, listing every paired PC with live status (connected / connecting / disconnected, with sync off shown as a warning) and a check mark on the current send target; each row offers a delete button to un-pair that PC after a confirmation dialog
- Android: the header status bar now shows "status · current device name", for example `Connected · My PC`

### Changed

- Android: text, shadow incremental updates and Auto Enter are routed only to the currently selected device; switching the target leaves the other connections untouched
- Android: only the active device's ACK may clear the input box; a late ACK from another device is ignored, so the text being typed for the active device is never erased
- Android: paired-device storage upgraded to schema v3 — a `saved_servers` list plus `active_device_key`. Existing v1/v2 `saved_server` data migrates automatically on first launch and no re-scan is needed; a single-device `saved_server` (equal to the active device) keeps being written so downgrading to an older APK still finds a usable PC
- CI: tag releases (`vX.Y.Z`) now build Android / Windows / Linux only. The macOS job was removed as requested, so official releases no longer produce a macOS DMG; the release assets are `voicing.apk`, `voicing-windows-x64.exe`, `voicing-linux-amd64.deb`, `voicing-linux-x86_64` plus `SHA256SUMS.txt`
- CI: added a `workflow_dispatch` manual build (Actions page or `gh workflow run release.yml --ref main`). It builds only the current APK and the Linux DEB / standalone binary and keeps them as workflow artifacts; it does not create a GitHub Release

### Notes

- The wire protocol (port 9527, message types) and the QR payload are unchanged, and the PC side needs no update: the existing desktop build stays compatible with the new APK, so updating the Android app is sufficient
- Upgrading from 2.9.14 preserves the saved candidate pools and migrates the single saved PC into the multi-device list automatically (storage schema v3), so no re-scan is needed
- The macOS desktop code is retained and can still be built from source, but official CI/Release no longer provides macOS artifacts

### 新增

- 手机端：多设备配对。每扫描一台新 PC 都会追加到已配对设备列表，不再覆盖上一台；同一 `device_id` 重新扫码只合并地址簿与候选历史，不产生重复项
- 手机端：全部已配对 PC 并发建立 WebSocket 连接，每台都有独立的心跳、重连退避与 Happy Eyeballs 候选竞速，同一 WiFi 下可以同时在线多台电脑
- 手机端：「更多功能操作」最下方（「扫码连接」下面）新增「设备选择」入口。点击后向左侧弹出二级菜单，风格与现有下拉菜单一致，列出全部已配对设备及其实时状态（已连接 / 连接中 / 未连接，同步关闭显示为警告色），当前发送目标带勾选标记；每行行尾提供删除按钮，确认后可解绑该设备
- 手机端：顶部状态栏显示「状态 · 当前设备名」，例如「已连接 · 我的电脑」

### 变更

- 手机端：文本、shadow 增量与 Auto Enter 只发往当前选中的设备；切换发送目标不会影响其它设备的连接
- 手机端：只有当前活跃设备的 ACK 才能清空输入框；其它设备的迟到 ACK 会被忽略，不会误清正在给当前设备输入的内容
- 手机端：配对存储升级为 schema v3 —— `saved_servers` 列表 + `active_device_key`。旧 v1/v2 的 `saved_server` 数据首次启动自动迁移，无需重新扫码；同时继续写一份单设备 `saved_server`（等于活跃设备），降级到旧版 APK 仍能读到一台可用设备
- CI：tag 发布（`vX.Y.Z`）只构建 Android / Windows / Linux。按用户要求删除了 macOS job，官方 Release 不再产出 macOS DMG；发布资产为 `voicing.apk`、`voicing-windows-x64.exe`、`voicing-linux-amd64.deb`、`voicing-linux-x86_64` 加 `SHA256SUMS.txt`
- CI：新增 `workflow_dispatch` 手动构建（GitHub Actions 页面或 `gh workflow run release.yml --ref main`），只构建当前 APK 与 Linux DEB / standalone 二进制，作为 workflow artifact 下载；不会创建 GitHub Release

### 说明

- 通信协议（端口 9527、消息类型）与 QR payload 均未变更，PC 端无需改动：现有桌面端可直接与新版 APK 互通，只需更新 Android 端
- 从 2.9.14 升级会保留原有候选池，并将单台已保存设备自动迁移进多设备列表（存储 schema v3），无需重新扫码
- macOS 桌面端代码仍然保留、可从源码自行构建，但官方 CI/Release 不再提供 macOS 产物

---

## [2.9.14] - 2026-11-20

### Added

- Android: a per-address network history (saved-server schema v2). Every candidate IP now records the phone network it last succeeded on, success/failure counts and the last-success time; v1 `ip`/`ips` data is migrated in place, so upgrading does not require a re-scan and the existing candidate pool is preserved
- Android: network-aware candidate ranking — an address that previously worked on the current network ranks first, then addresses inside the current local subnet, then dual-side Tailscale addresses; unreachable foreign LAN ranges (for example a PC's docker bridge) are pushed to the end
- Android: Happy Eyeballs style parallel probing for both QR pairing and saved-device reconnects. Candidates are dialled with a 120 ms stagger (at most 3 in flight), the first successful handshake wins and the others are cancelled, so coming back to a previously paired network reconnects in about 1–2 s instead of the old serial worst case of N×2–3 s
- Android: native network snapshot bridge (`getNetworkSnapshot` plus the `voicing/network_state_events` stream) reporting IPv4 interfaces, prefix lengths and transports without new permissions; while disconnected or connecting, a network change immediately re-ranks and reconnects, and a live connection is left untouched
- PC: `voicing_tuning` module centralising all tunables (timeouts, cache TTLs, rebind hysteresis, WebSocket keepalive) with `VOICING_*` environment overrides and effective-value logging at startup

### Changed

- PC: `voice_coding.py` (2,185 lines) split into focused modules — `network_interfaces`, `voicing_server`, `tray_ui`, `qr_dialog`, `voicing_tuning`, `voicing_state` — while the entry point stays a compatibility façade
- PC: interface discovery is cached and shared between the tray, QR dialog and WebSocket listener (median `refresh_server_interfaces` 7.77 ms → 0.24 ms, QR payload build 9.59 ms → 0.26 ms, startup to tray-ready 406 ms → ~196 ms)
- PC: container and bridge interfaces (`docker0`, `veth*`, `br-*`, `virbr*`, `lxc*`, `podman*`, CNI/Calico/Kube bridges) are excluded from QR and listener candidates
- PC: the WebSocket server tunes keepalive/close timeouts, keeps a diagnostic client registry and writes connect / disconnect / injection results (remote address, duration, message counts) to the daily log file instead of console-only output
- PC: listener rebinding now requires two consecutive fresh snapshots of a changed address set, so a flapping interface no longer tears the listener down repeatedly

### Fixed

- Android: the parallel connection race could hang forever when its result was awaited, because the handle completed a private completer that nobody consumed

### Notes

- The wire protocol and the QR payload schema are unchanged; the desktop build and the APK remain interchangeable with 2.9.13.

### 新增

- 手机端：地址簿按网络维度记录历史（saved_server schema v2）。每个候选 IP 记录「在哪个手机网络成功过、成功/失败次数、最近成功时间」；v1 的 `ip`/`ips` 数据原地迁移，升级无需重新扫码，已有候选池完整保留
- 手机端：网络画像感知的候选排序 —— 本网络成功过的地址优先，其次是当前本地子网内地址，再次是双端 Tailscale 地址；不可达的其它网络 LAN 段（例如 PC 的 docker 网桥）被压到末尾
- 手机端：扫码配对与已保存重连都改为 Happy Eyeballs 并行探测。候选按 120ms 间隔错峰启动（最多 3 路），首个握手成功的候选胜出并取消其余；回到曾配对过的网络约 1~2 秒自动连回，取代旧版串行最坏 N×2~3 秒
- 手机端：原生网络快照桥（`getNetworkSnapshot` 与 `voicing/network_state_events` 事件流），上报 IPv4 接口、前缀长度与接口类型，不新增任何权限；断线/连接中遇到网络变化会立即重排并重连，已连接则不受打扰
- PC 端：新增 `voicing_tuning` 模块集中全部可调参数（超时、缓存 TTL、重绑防抖、WebSocket keepalive），支持 `VOICING_*` 环境变量覆盖，启动时打印生效值

### 变更

- PC 端：`voice_coding.py`（2185 行）按职责拆分为 `network_interfaces` / `voicing_server` / `tray_ui` / `qr_dialog` / `voicing_tuning` / `voicing_state`，入口文件保留兼容导出与装配职责
- PC 端：网卡枚举改为带 TTL 的共享快照（托盘、QR、WebSocket 监听复用）：`refresh_server_interfaces` 中位 7.77ms → 0.24ms，QR payload 构建 9.59ms → 0.26ms，启动到托盘就绪 406ms → 约 196ms
- PC 端：容器/虚拟网桥接口（`docker0`、`veth*`、`br-*`、`virbr*`、`lxc*`、`podman*`、CNI/Calico/Kube 等）不再进入 QR 与监听候选
- PC 端：WebSocket server 调整 keepalive/close 超时，新增诊断用连接注册表，并把连接/断开/注入结果（对端地址、时长、消息数）写入每日文件日志，而不是只 print 到控制台
- PC 端：监听重绑需要连续两次「新枚举」确认同一新地址集合，接口抖动不再反复断开重建监听

### 修复

- Android：并行竞速在等待结果时可能永久挂起（句柄完成的是私有 Completer，调用方永远等不到）

### 说明

- 通信协议与 QR payload 结构未变，桌面端与 APK 仍与 2.9.13 互通。

---

## [2.9.13] - 2026-09-25

### Fixed

- PC (Linux/Windows/macOS): the Tailscale IPv4 address is now advertised in the QR payload and bound by the WebSocket server as a fallback candidate, after the local network addresses. `tailscale0` was previously filtered out three times over (interface name matched the VPN prefix list, `100.64.0.0/10` is not reported as private, and the `/32` prefix is outside the accepted `1..30` range), so the phone had no route to the desktop once the VPN was active
- Android: a target inside the Tailscale CGNAT range (`100.64.0.0/10`) is now reached through the system default network instead of a WiFi-bound socket, because that address is only reachable through the VPN tunnel
- Android: network selection for other targets is unchanged from v2.9.12 (ranked WiFi candidates plus an `activeNetwork` fallback)
- Combined effect: without a VPN the phone uses the LAN address; with a VPN that permits bypass it still uses the LAN address; with Android's "Block connections without VPN" enabled it uses the Tailscale address over the tunnel

### 修复

- PC (Linux/Windows/macOS): Tailscale IPv4 地址现在会写进 QR payload，并由 WebSocket 服务器一并绑定，排在局域网地址之后作为兜底候选。此前 `tailscale0` 会被三重过滤挡掉（接口名命中 VPN 前缀、`100.64.0.0/10` 不被判定为 private、`/32` 前缀超出允许的 `1..30` 范围），导致 VPN 一开手机就完全无路可走
- Android: 目标落在 Tailscale CGNAT 段（`100.64.0.0/10`）时改用系统默认网络，而不是绑定 WiFi 的 socket，因为该地址只能经 VPN 隧道到达
- Android: 其它目标的选路逻辑与 v2.9.12 一致（WiFi 候选分级 + `activeNetwork` 兜底）
- 综合效果：未开 VPN 时走局域网地址；开了 VPN 且允许绕过时仍走局域网地址；开了 Android「阻止不经过 VPN 的连接」时走 Tailscale 隧道地址

### Notes

- Requires the phone to be signed in to the same tailnet as the desktop. If the desktop has no `tailscale` CLI available, behaviour is exactly as before.
- Only the Android APK and the desktop build need updating; the wire protocol is unchanged.

### 说明

- 需要手机与电脑登录同一个 tailnet。若电脑上没有可用的 `tailscale` 命令，行为与改动前完全一致。
- 通信协议未变，更新桌面端与 Android APK 即可。

---

## [2.9.12] - 2026-09-25

### Fixed

- Android: Voicing now keeps using the WiFi network to reach the PC regardless of any active VPN. The previous implementation required a network to satisfy both `TRANSPORT_WIFI` and `NET_CAPABILITY_NOT_VPN`, and failed immediately with "Physical WiFi network is unavailable" when nothing matched, so enabling Tailscale (or any other VPN) made the phone unable to connect at all
- Android: WiFi candidates are now ranked instead of filtered. A plain physical WiFi network is preferred, a WiFi network whose VPN capability is affected is still used, and a VPN network that inherited the WiFi transport (Android 9+ `setUnderlyingNetworks()` behaviour) is the last resort
- Android: when no WiFi candidate exists at all, the connection falls back to the system default network instead of failing outright
- Android: network selection now logs each candidate's transports and capabilities, so VPN-related connection problems can be diagnosed from a single logcat

### 修复

- Android: 现在无论手机开启什么 VPN，Voicing 都会继续按 WiFi 网络连接 PC。原实现要求网络同时满足 `TRANSPORT_WIFI` 与 `NET_CAPABILITY_NOT_VPN`，一旦没有网络匹配就立刻报 "Physical WiFi network is unavailable"，导致开启 Tailscale 等 VPN 后完全连不上
- Android: WiFi 候选改为分级排序而不是过滤。优先纯物理 WiFi，其次 capability 受 VPN 影响的 WiFi 网络，最后才是继承了 WiFi transport 的 VPN 网络（Android 9+ `setUnderlyingNetworks()` 行为）
- Android: 完全没有任何 WiFi 候选时回退到系统默认网络，而不是直接失败
- Android: 选网过程会记录每个候选的 transport 与 capability，一次 logcat 即可诊断 VPN 相关的连接问题

### Notes

- The PC side is unchanged in this release; only the Android APK needs updating.
- If Android's "Block connections without VPN" option is enabled, the system prevents any socket from bypassing the VPN and no application can work around it. Disable that option, enable "Allow LAN access" in Tailscale, or add the PC to the tailnet instead.

### 说明

- 本版本 PC 端没有任何改动，只需要更新 Android APK。
- 如果开启了 Android 的「阻止不经过 VPN 的连接」，系统会禁止任何绕过 VPN 的 socket，任何应用都无法绕过。请改为关闭该选项、在 Tailscale 中开启 Allow LAN access，或把 PC 加入 tailnet。

---

## [2.9.11] - 2026-09-25

### Changed

- PC (Linux): GNOME Wayland input now always sends a plain Ctrl+V. AT-SPI focus sampling, ACTIVE-window selection, terminal/normal/unresolved classification, bounded retries, terminal focus cache, in-process GI probing, the system Python helper and the startup focus prewarm were all removed
- PC (Linux): The "Paste mode" tray entry was removed from both the custom and the native menu, because there is no longer a paste mode to switch
- PC (Linux): Pasting no longer waits for a focus sampling window or an unresolved-retry budget, so every paste is immediate and behaves identically on each send
- PC (Linux): `python3-gi`, `gir1.2-atspi-2.0`, `at-spi2-core` and `wl-clipboard` are no longer required or declared, because the packaged build no longer shells out to a system Python for AT-SPI
- Packaging (Linux): kept the v2.9.10 DEB normalization (`--root-owner-group`, 0755/0644) and the flat `SHA256SUMS.txt` asset naming

### 变更

- PC (Linux): GNOME Wayland 输入现在固定发送普通 Ctrl+V；AT-SPI 焦点采样、ACTIVE 窗口选择、terminal/normal/unresolved 三态判定、有界重试、终端焦点缓存、进程内 GI 探测、系统 Python helper 与启动预热全部删除
- PC (Linux): 托盘菜单的「粘贴模式」项已从自定义菜单和原生菜单中移除，因为不再有粘贴模式可切换
- PC (Linux): 粘贴不再等待焦点采样窗口或 unresolved 重试预算，每次粘贴都立即生效且行为一致
- PC (Linux): 不再需要也不再声明 `python3-gi`、`gir1.2-atspi-2.0`、`at-spi2-core` 与 `wl-clipboard`，因为打包产物不再为 AT-SPI 调用系统 Python
- Packaging (Linux): 保留 v2.9.10 的 DEB 规范化（`--root-owner-group`、0755/0644）与 `SHA256SUMS.txt` 平铺命名

### Notes

- This release supersedes the terminal-aware paste behavior introduced in v2.9.10. Terminal emulators do not treat Ctrl+V as paste by default (GNOME Terminal and Ghostty use Ctrl+Shift+V), so pasting inside a terminal is no longer a supported scenario. Browsers, editors, and chat windows are unaffected.
- Background: v2.9.10 and the earlier v2.9.5-v2.9.9 releases tried to detect terminal focus through AT-SPI and switch shortcuts accordingly. That detection proved unreliable on cold GNOME logins and whenever the accessibility bus was not ready, so the scenario was removed entirely instead of being tuned further.

### 说明

- 本版本取代 v2.9.10 引入的终端感知粘贴行为。终端程序默认不把 Ctrl+V 当粘贴（GNOME Terminal / Ghostty 使用 Ctrl+Shift+V），因此终端内粘贴不再是支持场景；浏览器、编辑器、聊天窗口等普通输入界面不受影响。
- 背景：v2.9.10 以及更早的 v2.9.5–v2.9.9 都尝试通过 AT-SPI 探测终端焦点并切换快捷键。该判定在 GNOME 冷启动以及辅助功能总线未就绪时不可靠，因此整体移除该场景，而不是继续调优。

---

## [2.9.10] - 2026-07-28

### Fixed

- PC (Linux): GNOME Wayland Auto paste now selects the current non-shell AT-SPI `ACTIVE` window first and only trusts focused controls inside that window, preventing stale `FOCUSED` state from a previous app from choosing Ctrl+V in a terminal
- PC (Linux): terminals such as Ghostty that expose a generic `Unnamed` AT-SPI frame are now identified from the active accessible process executable basename; window titles and clipboard text are never used for classification or diagnostics
- PC (Linux): Auto paste now uses terminal / normal / unresolved decisions with bounded retries; sparse or conflicting focus evidence cancels the attempt and preserves the phone input instead of guessing a shortcut
- PC (Linux): the first RemoteDesktop portal session reconciles focus evidence from before and after authorization, and partial portal failures now release any pressed Ctrl/Shift modifiers
- PC (Linux): Wayland clipboard writes require `wl-clipboard`, are read back before sending keys, and only restore a previous clipboard value when it was actually readable after a longer paste settle delay
- PC (Linux): startup performs a read-only AT-SPI prewarm, system-Python fallback is used when in-process samples are all uncertain, and structured diagnostics omit text and window titles
- Packaging (Linux): release runners and Debian dependencies now include AT-SPI, Python GI, and `wl-clipboard` runtime requirements; DEB contents are normalized to root ownership, 0755 directories/executables, and 0644 metadata/icons

### 修复

- PC (Linux): GNOME Wayland 自动粘贴现在先选择当前非 Shell 的 AT-SPI `ACTIVE` 窗口，只信任该窗口子树内的 focused 控件，避免上一个应用残留的 `FOCUSED` 状态让终端误走 Ctrl+V
- PC (Linux): 对 Ghostty 这类只暴露通用 `Unnamed` AT-SPI frame 的终端，现在会读取当前 accessible 对应进程的可执行文件 basename 来识别；分类和诊断均不使用窗口标题或剪贴板正文
- PC (Linux): 自动粘贴改为 terminal / normal / unresolved 三态并进行有界重试；焦点证据稀疏或冲突时会取消本次发送并保留手机输入，不再猜测快捷键
- PC (Linux): 首次 RemoteDesktop portal 会话会协调授权前后的焦点证据；portal 中途失败时会补偿释放已按下的 Ctrl/Shift 修饰键
- PC (Linux): Wayland 剪贴板强制使用 `wl-clipboard`，发送按键前回读验证写入结果，并在更长的粘贴等待后只对确实可读的旧剪贴板执行恢复
- PC (Linux): 启动时执行只读 AT-SPI 预热；进程内样本全不确定时会使用 system-Python helper；结构化诊断不会记录文本或窗口标题
- Packaging (Linux): Release runner 与 Debian 依赖现在包含 AT-SPI、Python GI 和 `wl-clipboard` 运行时要求；DEB 内容统一为 root 所有权、目录/可执行文件 0755、元数据/图标 0644

---

## [2.9.9] - 2026-06-22

### Fixed

- PC (Linux): GNOME Wayland Auto paste now samples AT-SPI focus for a 500 ms window and votes on terminal vs normal focus, reducing one-off focus glitches that could send the wrong paste shortcut

### 修复

- PC (Linux): GNOME Wayland 自动粘贴现在会在 500ms 窗口内采样 AT-SPI 焦点并投票判断终端/普通窗口，减少单次焦点抖动导致发错粘贴快捷键的情况

---

## [2.9.8] - 2026-06-19

### Fixed

- PC/Android: Auto Enter commit now waits for the desktop ACK before clearing phone input, and the desktop only returns a clearing ACK after Enter was actually sent
- PC: Auto Enter now waits a little longer after paste before sending Enter, improving reliability on GNOME Wayland terminals and slower target apps
- PC (Linux): Auto paste no longer treats completely unresolved focus as terminal without a recent terminal signal, so regular windows continue to paste when AT-SPI focus detection is flaky

### 修复

- PC/Android: Auto Enter commit 现在等待桌面端 ACK 后才清空手机输入；桌面端也只有在 Enter 确实发出后才返回清空 ACK
- PC: Auto Enter 在粘贴后等待更长一点再发送 Enter，提高 GNOME Wayland 终端和较慢目标应用里的可靠性
- PC (Linux): 自动粘贴不再把没有近期终端命中的完全未知焦点当作终端，避免 AT-SPI 焦点不稳定时普通窗口收到终端粘贴快捷键

---

## [2.9.7] - 2026-06-19

### Fixed

- PC (Linux): GNOME Wayland Auto paste now prioritizes stable terminal handling by retrying AT-SPI focus detection and using the terminal-safe Ctrl+Shift+V path when focus cannot be resolved reliably

### Docs

- Clarified Linux/GNOME Wayland usage in the public docs:
  - Auto paste is the recommended default; confirmed normal fields use Ctrl+V, while terminal or unresolved focus uses Ctrl+Shift+V
  - Linux auto-start uses GNOME autostart `.desktop`, while GNOME Wayland RemoteDesktop keyboard permission may still require user approval after login or app start

### 修复

- PC (Linux): GNOME Wayland 自动粘贴现在优先保证终端处理稳定性，会重试 AT-SPI 焦点检测，并在焦点无法可靠确认时走终端安全的 Ctrl+Shift+V 路径

### 文档

- 补充公开文档中的 Linux/GNOME Wayland 使用说明：
  - 日常推荐保持自动粘贴；确认的普通输入框走 Ctrl+V，终端或无法稳定确认的焦点走 Ctrl+Shift+V
  - Linux 开机自启使用 GNOME autostart `.desktop`；GNOME Wayland 的 RemoteDesktop 键盘授权在登录或启动后仍可能需要用户手动允许

---

## [2.9.6] - 2026-06-19

### Fixed

- **PC (Linux): packaged Wayland builds now detect RemoteDesktop portal keyboard capability correctly**
  - The Linux `.deb` and standalone binary no longer inherit PyInstaller's bundled `LD_LIBRARY_PATH` when probing the system `gdbus` command
  - This fixes a false startup error on GNOME Wayland where the portal was available, but the packaged app reported no RemoteDesktop keyboard capability

### Tests

- PC:
  - `QT_QPA_PLATFORM=offscreen ../.venv/bin/python -m unittest discover -s tests`
  - Local frozen PyInstaller smoke test: the packaged binary reaches WebSocket startup on GNOME Wayland instead of failing the portal capability check

### 修复

- **PC (Linux): 打包后的 Wayland 版本现在能正确检测 RemoteDesktop portal 键盘能力**
  - Linux `.deb` 和独立二进制在探测系统 `gdbus` 命令时不再继承 PyInstaller 注入的 `LD_LIBRARY_PATH`
  - 修复 GNOME Wayland 上 portal 明明可用，但打包版启动时误报没有 RemoteDesktop 键盘能力的问题

### 测试

- PC:
  - `QT_QPA_PLATFORM=offscreen ../.venv/bin/python -m unittest discover -s tests`
  - 本地 frozen PyInstaller smoke test：打包二进制在 GNOME Wayland 上能进入 WebSocket 启动阶段，不再失败于 portal 能力检查

---

## [2.9.5] - 2026-06-19

### Added

- **PC: GNOME Wayland input support via RemoteDesktop portal**
  - Linux startup now allows Wayland sessions when the XDG RemoteDesktop portal exposes keyboard capability
  - GNOME Wayland text paste keeps the existing phone/WebSocket protocol unchanged and uses portal keyboard events for Ctrl+V and Enter
  - Wayland clipboard handling prefers `wl-copy` / `wl-paste`, while Windows, macOS, and Linux X11 keep the existing clipboard and hotkey behavior
- Release artifacts now include a Linux `.deb` package alongside the standalone `voicing-linux-x86_64` binary

### Changed

- PC text injection is now centralized in the platform keyboard layer instead of being implemented directly in `voice_coding.py`
- Linux runtime errors now report a missing RemoteDesktop portal keyboard capability instead of blocking all Wayland sessions unconditionally
- GNOME Wayland paste now defaults to Auto mode: terminal focus detected via AT-SPI uses Ctrl+Shift+V, normal fields use Ctrl+V, and the tray menu can switch to normal, terminal, or compatibility modes manually

### Fixed

- **PC: GNOME Wayland tray no longer shows two menus on right-click** — Linux now uses the native system context menu (left and right click both open the same menu), while Windows and macOS keep the custom Fluent menu
- **PC: Linux tray icon no longer flickers every 200ms** — `setIcon` is now only called when the icon state actually changes (SNI/AppIndicator hosts rebuild the icon on every `setIcon`)
- **PC: no more black flash at the top-left corner on Linux/Wayland startup** — offscreen pre-warm no longer shows the window, since Wayland forbids client-side window positioning
- **PC: GNOME Wayland RemoteDesktop portal calls no longer rejected with `Expected type 'u' ... got 'i'`** — `SelectDevices` `types` and `NotifyKeyboardKeysym` `state` are now sent as D-Bus uint32 via a typed `QDBusArgument` instead of a Python int
- **PC: tray menus no longer draw separator lines between items** — both the Linux native context menu and the Windows/macOS custom Fluent menu now render as a flat list with spacing instead of divider lines
- **PC: QR dialog no longer flashes a ghost QR below center when arriving** — the open animation now unmapped before its end-of-animation resize so the Wayland compositor does not repaint a stale buffer at the new origin (a residual one-frame self-flash at arrival is still being investigated)
- **PC (Windows/macOS): custom tray menu width now fits its content** — the menu width is tightened to the longest item instead of the oversized default from `adjustSize()`
- **PC (Linux): native tray menu no longer has excess right-side whitespace** — item padding is tightened via stylesheet so the menu width tracks the text instead of the over-generous default
- **PC: failed desktop injection no longer clears phone input** — the desktop ACK only requests clearing the phone input after text was successfully injected
- **PC: clipboard restoration now runs after failed paste/Enter attempts** — the previous clipboard and PRIMARY selection are restored in a `finally` path
- **Android: native WiFi WebSocket close is now best-effort** — reconnect/dispose cleanup no longer leaves an unhandled Future when the native connection fails before returning an id

### Docs

- README / README.zh-CN now document GNOME Wayland support and the first-run RemoteDesktop keyboard permission prompt

### Tests

- PC:
  - `.venv/bin/python -m py_compile pc/voice_coding.py pc/platform_utils.py pc/platform_keyboard.py pc/platform_autostart.py pc/platform_instance.py pc/network_recovery.py pc/voicing_protocol.py pc/device_identity.py`
  - `.venv/bin/python -m unittest discover -s pc/tests`
- Android:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`

### 新增

- **PC: 通过 RemoteDesktop portal 支持 GNOME Wayland 输入**
  - Linux 启动检查现在会在 XDG RemoteDesktop portal 暴露键盘能力时允许 Wayland 会话启动
  - GNOME Wayland 文本粘贴保持手机端和 WebSocket 协议不变，通过 portal 键盘事件发送 Ctrl+V 和 Enter
  - Wayland 剪贴板优先使用 `wl-copy` / `wl-paste`，Windows、macOS 和 Linux X11 保持原有剪贴板与快捷键行为
- Release 产物现在同时包含 Linux `.deb` 安装包和独立的 `voicing-linux-x86_64` 二进制

### 变更

- PC 文本注入逻辑集中到平台键盘层，不再由 `voice_coding.py` 直接操作剪贴板和粘贴快捷键
- Linux 运行时错误改为提示缺少 RemoteDesktop portal 键盘能力，不再无条件阻断所有 Wayland 会话
- GNOME Wayland 粘贴默认使用自动模式：通过 AT-SPI 检测到终端焦点时发送 Ctrl+Shift+V，普通输入框发送 Ctrl+V；托盘菜单可手动切换为普通、终端或兼容模式

### 修复

- **PC: 桌面注入失败时不再清空手机输入** —— 只有文本成功注入后，桌面端 ACK 才会要求手机清空输入
- **PC: 粘贴或 Enter 失败后仍会恢复剪贴板** —— 旧剪贴板和 PRIMARY selection 恢复逻辑进入 `finally` 路径
- **Android: native WiFi WebSocket close 改为 best-effort** —— native 连接尚未返回 id 就失败时，重连/释放路径不会留下未处理 Future

### 文档

- README / README.zh-CN 补充 GNOME Wayland 支持和首次运行 RemoteDesktop 键盘授权提示

### 测试

- PC:
  - `.venv/bin/python -m py_compile pc/voice_coding.py pc/platform_utils.py pc/platform_keyboard.py pc/platform_autostart.py pc/platform_instance.py pc/network_recovery.py pc/voicing_protocol.py pc/device_identity.py`
  - `.venv/bin/python -m unittest discover -s pc/tests`
- Android:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`

---

## [2.9.4] - 2026-05-02

### Fixed

- **PC: QR payload now prefers actually bound WebSocket listener IPs**
  - Fixed a same-LAN QR pairing failure where the QR code could advertise an interface candidate that the desktop failed to bind
  - The desktop now keeps the fresh candidate IP pool separate from the actual bound listener IP pool, preserving runtime network-change rebinds while making QR payloads safer
  - QR payload `ip/ips` now prefer bound listener addresses after the WebSocket server starts; before first bind they fall back to the current physical IPv4 candidate list

- **PC: macOS interface classification is now conservative**
  - macOS `en0/en1/enX` names are no longer treated as fixed WiFi/Ethernet roles
  - This avoids prioritizing the wrong address on Macs with Ethernet, Thunderbolt docks, or changing interface order

- **Android: physical WiFi selection excludes VPN networks more explicitly**
  - The native Android WebSocket path now requires `NET_CAPABILITY_NOT_VPN` when selecting the WiFi `Network`
  - This reduces the chance of binding Voicing traffic to a VPN/proxy network object when VPN software is active

### Docs

- README and Android-facing connection docs now describe that QR codes prefer actually bound listener IPs and that macOS interface names are handled conservatively

### Tests

- PC:
  - `python -m py_compile pc\voice_coding.py pc\voicing_protocol.py pc\device_identity.py pc\network_recovery.py`
  - `python -m unittest discover -s pc\tests`
- Android:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`
  - `flutter build apk --debug`
- General:
  - `git diff --check`

### 修复

- **PC: QR payload 优先使用 WebSocket 实际监听成功的 IP**
  - 修复同一局域网扫码配对时，二维码可能发布了桌面端未实际绑定成功的候选 IP，导致手机优先连接失败的问题
  - 桌面端现在将“当前理论候选 IP 池”和“实际绑定成功 IP 池”拆开，既保留运行时网络变化重绑能力，又让 QR payload 更可靠
  - WebSocket server 启动后，QR payload 的 `ip/ips` 优先使用实际监听地址；首次绑定完成前才 fallback 到当前物理 IPv4 候选池

- **PC: macOS 网卡分类改为保守策略**
  - 不再假设 macOS 的 `en0/en1/enX` 分别固定代表 WiFi 或以太网
  - 避免 Mac 接入以太网、Thunderbolt 扩展坞或接口顺序变化后，错误优先发布不可达地址

- **Android: 物理 WiFi 选择更明确排除 VPN**
  - Android 原生 WebSocket 选取 WiFi `Network` 时改为显式要求 `NET_CAPABILITY_NOT_VPN`
  - 降低 VPN / 代理开启时 Voicing 流量绑定到错误 Network 的概率

### 文档

- README 与 Android 连接说明补充：QR 码优先展示实际监听 IP，macOS 网卡命名按保守策略处理

### 测试

- PC:
  - `python -m py_compile pc\voice_coding.py pc\voicing_protocol.py pc\device_identity.py pc\network_recovery.py`
  - `python -m unittest discover -s pc\tests`
- Android:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`
  - `flutter build apk --debug`
- General:
  - `git diff --check`

---

## [2.9.3] - 2026-04-26

### Fixed

- **Android: preserve the same PC's old-LAN candidate IPs after re-scan**
  - Fixed: after switching both ends from LAN A to LAN B and re-scanning successfully, switching back to LAN A failed to auto-reconnect
  - When the QR scan saves a PC with the same `device_id`, the new QR's `ip/ips` are now merged into the existing `saved_server.candidateIps`
  - The newly connected IP is still promoted to primary, but old LAN / hotspot IPs are no longer overwritten
  - When the user confirms replacing the PC with a different one, the old candidate pool is **not** merged, preventing cross-device IP bleed

### Docs

- README and Android README updated: re-scanning the same PC keeps historical LAN candidate IPs, so switching back to an older network still auto-reconnects

### Tests

- Android:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`
  - `flutter build apk --debug`
- PC:
  - `python -m py_compile pc/voice_coding.py pc/voicing_protocol.py pc/device_identity.py pc/network_recovery.py`
  - `python -m unittest discover -s pc/tests`
- General:
  - `git diff --check`

### 修复

- **Android: 扫码后保留同一 PC 的旧局域网候选 IP**
  - 修复手机和电脑从 A 局域网切到 B 局域网、重新扫码成功后，再切回 A 局域网不能自动重连的问题
  - Android 扫码成功保存同一 `device_id` 的 PC 时，会将本次 QR 的 `ip/ips` 与旧 `saved_server.candidateIps` 合并
  - 新连接成功的 IP 仍会提升为主 IP，但旧局域网 / 热点 IP 不再被覆盖丢失
  - 用户确认替换为另一台 PC 时不会合并旧候选池，避免跨设备串地址

### 文档

- README 和 Android README 补充说明：同一 PC 多次扫码会保留历史局域网候选 IP，切回旧网络后仍应自动重连

### 测试

- Android:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`
  - `flutter build apk --debug`
- PC:
  - `python -m py_compile pc/voice_coding.py pc/voicing_protocol.py pc/device_identity.py pc/network_recovery.py`
  - `python -m unittest discover -s pc/tests`
- General:
  - `git diff --check`

---

## [2.9.2] - 2026-04-26

### 修复

- **PC: 运行时网络切换后 QR/监听刷新**
  - 修复 PC 端和 Android 端都不重启、只一起切换到新局域网后，手机扫描 PC QR 码爆红的问题
  - PC 端不再只使用启动时缓存的 `SERVER_INTERFACES`
  - WebSocket server 会在运行时刷新物理 IPv4 地址快照，发现地址池变化后关闭旧监听并重新绑定当前局域网 IP
  - QR 弹窗打开和 5 秒刷新时重新生成当前 `ip/ips` payload，重新扫码即可更新 Android 保存的候选 IP 池

### 改进

- **PC: 快速网卡枚举**
  - 新增 `psutil` 作为桌面端运行时网卡枚举主路径，避免 QR 打开或 server 后台循环高频启动 PowerShell
  - 保留原有命令行网卡枚举作为 fallback，确保缺少 `psutil` 时仍可启动
- **Release: Android 依赖解析稳定性**
  - Android Gradle 仓库顺序改为官方 `google()` / `mavenCentral()` 优先，阿里云镜像只作为 fallback，避免镜像 502 导致 GitHub Actions release 构建失败

### 文档

- README 和 Android README 补充 v2.9.2 网络切换行为：PC 端运行中刷新 QR 码与 WebSocket 监听地址，切换局域网后无需重启 PC 端软件
- Android README 补充 release 构建仓库顺序策略

### 测试

- PC:
  - `python -m py_compile pc/voice_coding.py pc/voicing_protocol.py pc/device_identity.py pc/network_recovery.py`
  - `python -m unittest discover -s pc/tests`
- Android:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`

---

## [2.9.1] - 2026-04-24

### 修复

- **Android: QR-only 连接路径**
  - 手机端启动、恢复前台和手动刷新时不再依赖 UDP 广播发现
  - 已保存设备会直接按 IP 池逐个尝试连接，适配热点、学校/公司局域网等多网络切换场景
  - 无保存设备时保持未连接，引导用户通过“更多功能操作 → 扫码连接”完成首次配对

- **PC: 停止运行时 UDP 广播**
  - 桌面端不再启动 UDP 广播线程
  - 保留物理网卡枚举，用于 QR payload 的主 IP 和候选 IP 列表

- **Android: 键盘和扫码 UI**
  - 修复键盘打开时点击“扫码连接”导致二维码区域先出现在上方、再跟随输入区下移的问题
  - 改用 Android 原生 `WindowInsetsAnimationCompat` 逐帧键盘高度驱动输入区，键盘展开/收起时输入框高度更实时
  - 修复 App 首次点击“更多功能操作”时菜单冷绘制卡顿
  - 微调顶部“已连接/未连接/连接中”和“更多功能操作”文字位置

### 文档

- README 更新为 2.9.1 QR-only 当前行为：首次扫码配对，后续按保存的 IP 池自动重连，不再描述 UDP 优先发现路径

### 测试

- Android:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`
  - `JAVA_HOME=C:\dev\java21\jdk-21.0.2 flutter build apk --debug`
- PC:
  - `python -m py_compile pc/voice_coding.py pc/voicing_protocol.py pc/device_identity.py pc/network_recovery.py`
  - `python -m unittest discover -s pc/tests`

---

## [2.9.0] - 2026-04-24

### 新增

- **QR 扫码连接**
  - PC 托盘菜单新增“显示 QR 码”，二维码包含 `device_id/ip/ips/port/name/os`
  - Android 更多功能菜单新增“扫码连接”，输入区切换为相机预览和四角扫描框
  - 扫码后先做 WebSocket 连通性 probe，成功才保存设备并正式重连

- **单设备持久化**
  - Android 新增 `saved_server` JSON 存储，保存 PC 身份、最近成功地址、候选地址列表、端口、名称、系统和最近连接时间
  - 旧 `manual_server_ip` / `manual_server_port` 自动迁移到 `saved_server`
  - App 启动和手动刷新时优先等待 UDP 广播，失败后回退保存过的 PC 地址候选
  - 同一台 PC 的热点 IP、局域网 IP 可同时保存，网络切换后会逐个候选重连
  - 扫到不同 `device_id` 时会要求确认替换

- **公司网络 / VPN 场景支持**
  - PC 端过滤 VPN 和虚拟网卡，QR 优先展示物理热点/以太网/WiFi 地址，并携带全部可达候选
  - PC WebSocket server 监听全部可广播物理地址，网络变化后自动刷新监听地址
  - Android 端新增 WiFi-bound 原生 WebSocket 通道，通过 `ConnectivityManager` + OkHttp 让普通连接优先走物理 WiFi Network
  - Android Manifest 显式允许局域网明文 `ws://`，匹配当前 PC 端 WebSocket 协议

### 改进

- Android 首屏保持原有状态栏、更多功能操作和输入框；扫码入口只保留在“更多功能操作”中
- “刷新连接”会真实重连，已连接状态下不会被旧 WebSocket 回调闪回“未连接”
- QR 扫码失败提示细分为非 Voicing QR、版本不兼容、二维码损坏
- 相机权限拒绝时显示设置引导，并保留手动 IP fallback
- PC QR 弹窗加入扫码成功绿色对勾反馈，并避免普通自动重连误触发成功态
  - PC QR 弹窗动画改为单顶层窗口绘制，减少 Windows/Qt compositor 下的随机闪屏

### 测试

- Android:
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`
  - `flutter build apk --debug`
- PC:
  - `python -m py_compile pc/voice_coding.py pc/voicing_protocol.py pc/device_identity.py pc/network_recovery.py`
  - `python -m unittest discover -s pc/tests`
  - 真机验证：PC 热点、学校局域网、扫码保存、多 IP 候选 fallback 已闭环

---

## [2.7.3] - 2026-04-23

### 修复

- **PC: 托盘菜单视觉边缘精确对齐鼠标**
  - 之前菜单左下角与鼠标点击位置仍有 ~8px 偏移，原因是外层 `QVBoxLayout` 留了 8px 阴影边距
  - 现在按 `layout().contentsMargins()` 动态补偿（X 减 `shadow.left()`，Windows 上 Y 加 `shadow.bottom()`），让视觉菜单边缘而非 widget 外框对齐鼠标
  - macOS / Linux 同步按 `shadow.top()` 补偿向下展开方向

- **PC: 连续右键托盘图标可反复弹出菜单**
  - 修复 `Qt.Popup` 在 Windows 上"吃掉"第二次右键点击导致菜单无法再次弹出的问题
  - 在 `mousePressEvent` 中检测外部右键点击是否落在托盘图标矩形内，是则 `QTimer.singleShot(0)` 立刻在新位置重开菜单
  - 左键点击托盘图标不再触发菜单（仅右键响应）
  - 点击菜单外部区域仍正常关闭菜单（`Qt.Popup` 内建行为保留）

### 文档

- **新增"开发联调工作流"章节到 CLAUDE.md**
  - 记录已注册测试设备（Pixel 5 / Windows）
  - 标准启动序列（PC 热重启 + Flutter run）
  - 双端改动后的迭代规则（热重载 vs 热重启）
  - 触发词规范（"启动开发环境" / "启动联调"）

### 测试

- PC：
  - `python -m py_compile pc/voice_coding.py`
  - Windows 本地手动验证：右键托盘图标，菜单视觉左下角精确贴合鼠标点击位置

---

## [2.7.2] - 2026-04-17

### 修复

- **PC: 托盘右键菜单贴合鼠标位置**
  - Windows：菜单左下角对齐鼠标点击位置（符合 `TrackPopupMenu` 的 `TPM_LEFTALIGN | TPM_BOTTOMALIGN` 标准行为）
  - 修复 Windows 任务栏内点击时菜单被强制推到任务栏上方留出 30-50px 缝隙的问题
  - macOS / Linux 保持菜单左上角对齐图标（向下展开）的标准行为

### 测试

- PC：
  - `python -m unittest discover -s pc/tests`
  - `python -m py_compile pc/voice_coding.py`
  - Windows 本地手动验证：右键托盘图标，菜单左下角贴合鼠标位置

---

## [2.7.1] - 2026-04-17

### 改进

- **PC: UDP 自动发现支持局域网与热点双模**
  - 桌面端现在会枚举可广播的私有 IPv4 接口，并分别向每个子网发送定向 UDP 广播
  - 手机连同一路由器或连电脑热点时，都能收到对应可达 IP 的发现报文
  - 命令探测失败时不再猜测 `/24` 前缀，改为回退到 `<broadcast>`，避免把广播打到错误子网

- **PC: 网络接口过滤更安全**
  - 过滤回环、链路本地、组播、未指定地址，以及不适合做局域网发现的 `/31`、`/32` 地址
  - Windows / Linux / macOS 三平台接口解析都增加了更严格的候选筛选，降低误把 VPN / 虚拟接口当作发现接口的概率

- **GitHub Actions Release 链路加固**
  - workflow 中使用的第三方 Actions 全部改为 full commit SHA pin
  - 默认 token 权限收紧为只读，仅发布 job 保留 `contents: write`
  - `checkout` 关闭持久化凭据，减少构建阶段的 token 暴露面
  - Release 新增 `SHA256SUMS.txt`，下载后可校验产物完整性

### 修复

- **Android Release 不再允许静默退回 debug signing**
  - GitHub Actions 现在会强制检查正式签名 secrets，缺失时直接 fail
  - Android Gradle 在执行 release 任务时，若未配置签名且未显式开启本地调试豁免，会直接阻断构建

### 测试

- Android：
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
  - `flutter test`
- PC：
  - `python -m unittest discover -s pc/tests`
  - `cd pc && python -m unittest discover -s tests`
  - `python -m py_compile pc/voice_coding.py pc/network_recovery.py pc/platform_utils.py pc/voicing_protocol.py`
  - 新增三平台接口解析与广播地址计算测试

---

## [2.7.0] - 2026-04-16

### 新增

- **macOS 桌面端支持（Apple Silicon / arm64）**
  - PC 端拆出平台抽象层，支持 macOS 的日志目录、托盘菜单、自启和输入热键
  - 发布产物新增 `voicing-macos-arm64.dmg`
  - macOS `.app` bundle 写入 `LSUIElement=true`，以托盘常驻应用形态运行

- **Ubuntu 22.04 GNOME on X11 桌面端支持**
  - PC 端支持 Linux 的日志目录、`.desktop` 自启、托盘交互和 Ctrl+V 输入
  - 发布产物新增 `voicing-linux-x86_64`
  - 程序启动时会显式阻断 Wayland，会话不满足条件时直接提示，避免静默输入失败

- **跨平台桌面端测试覆盖**
  - 新增平台工具、键盘和自启模块测试
  - 桌面端测试命令同时支持仓库根目录和 `pc` 目录执行

### 改进

- **GitHub Actions Release 流程重构**
  - Android / Windows / macOS / Linux 构建先上传 workflow artifacts
  - 最终由单独的 publish job 聚合全部产物并一次性创建 GitHub Release
  - 固定 macOS runner 为 `macos-14`，Linux runner 为 `ubuntu-22.04`

- **Android release 签名链路**
  - 支持通过 GitHub Secrets 生成 `key.properties` 和 release keystore
  - 未配置 secrets 时仍保持 debug signing，兼容本地开发与现有 CI 环境

### 测试

- Android：
  - `flutter test`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
- PC：
  - `python -m unittest discover -s pc/tests`
  - `python -m unittest discover -s tests`
  - `python -m py_compile pc/voice_coding.py pc/platform_utils.py pc/platform_keyboard.py pc/platform_autostart.py pc/platform_instance.py`

---

## [2.6.2] - 2026-04-15

### 修复

- **Android: 息屏唤醒后的前台恢复体验**
  - 亮屏时会重建 UDP 发现监听，并立即进入前台恢复窗口
  - 恢复窗口内使用 500ms 快速重试，不再回退到常规 3/6/12 秒指数退避
  - 如果亮屏前已经连上，恢复期间状态栏保持显示"已连接"，避免闪成"未连接"

- **自动 Enter 与自动发送链路解耦**
  - `TYPE_TEXT` 新增 `send_mode`，区分 `submit`、`shadow`、`commit`
  - Shadow 增量输入不再直接触发 Enter，改为静默窗口后统一 finalize
  - 解决部分输入法一次语音分多段 commit 时，多次 Enter 被某些聊天框解释为换行的问题

- **协议 ACK 改为显式控制清空输入框**
  - `ack` 消息新增 `clear_input`
  - 仅手动 `submit` 会由服务端确认后清空输入框
  - Shadow / commit 不再依赖 ACK 到达时序来清空输入框，降低自动发送链路脆弱性

- **PC: 自动 Enter 注入更稳定**
  - 粘贴后增加 settle delay，再通过 Win32 `SendInput` 发送 Enter
  - 新增 commit 模式，支持只提交 Enter 而不重复输入文本

### 测试

- Android：
  - `flutter test`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
- PC：
  - `python -m unittest discover -s tests`
  - `python -m py_compile voice_coding.py network_recovery.py voicing_protocol.py`

---

## [2.6.1] - 2026-04-14

### 修复

- **Android: 菜单圆角区域水波纹溢出**
  - 问题：点击"自动 Enter"切换状态时，菜单圆角区域闪现白色直角效果
  - 原因：InkWell 水波纹效果未被裁剪到圆角边界内
  - 修复：使用 ClipRRect 裁剪第一个和最后一个菜单项，防止水波纹溢出

---

## [2.6.0] - 2026-04-14

### 新增

- **自动 Enter 功能**
  - Android: 菜单新增"自动 Enter"开关，默认关闭（红色 ✗）
  - 点击切换状态，带淡入淡出 + 颜色渐变动画（红色 ✗ ↔ 绿色 ✓）
  - 状态持久化到本地，App 重启后恢复上次设置
  - PC: 接收到文本后，根据 `auto_enter` 标志自动按 Enter 键
  - 通信协议: `TYPE_TEXT` 消息新增 `auto_enter` 字段

---

## [2.5.1] - 2026-04-14

### 改进

- **Android: 自动发送功能改为默认启用**
  - 移除菜单中的"自动发送"手动开关
  - 语音输入完成后始终自动发送到电脑，无需手动开启
  - 移除 `shared_preferences` 依赖

- **Android: 新增"连接中..."状态显示**
  - 重连过程中 header 显示橙色"连接中..."，替代直接显示"未连接"

- **Android: UI 细节优化**
  - 底部提示更新为"语音自动发送 · 回车手动发送"
  - 硬编码 `Colors.white` 替换为主题 token `AppColors.textPrimary`
  - 提取重复的文字样式为 `AppTextStyles` 常量
  - 菜单项和菜单按钮添加显式涟漪反馈色

### 修复

- **PC: 托盘菜单首次右键卡顿**
  - 问题：启动后首次右键托盘图标时菜单弹出有明显延迟
  - 原因：Qt 延迟渲染机制导致首次 show() 时才编译 stylesheet 和计算布局
  - 修复：启动时预热渲染菜单（屏幕外 show+hide），消除首次打开延迟

---

## [2.5.0] - 2026-04-14

### 改进

- **Android 架构拆分**
  - `main.dart` 仅保留 UI 组合逻辑
  - 新增 `voicing_connection_controller.dart` 承担连接状态机、自动发送和 UDP 恢复逻辑
  - 新增 `app_theme.dart` 抽离设计 token 与主题
  - 新增 `app_logger.dart`，移除生产代码中的 `print`

- **双端协议耦合加固**
  - 新增共享协议契约文件 `protocol/voicing_protocol_contract.json`
  - Android 新增 `voicing_protocol.dart` 统一协议常量与报文解析
  - PC 新增 `voicing_protocol.py` 统一端口、消息类型与报文构造
  - Android / PC 分别新增协议契约测试，避免消息结构再次漂移
  - Android 端显式处理 `sync_disabled`，PC 端补充 `sync_enabled: false`

- **UI 细节优化**
  - 修复 Android 菜单中“自动发送”文字与开关过于贴近的问题，增加稳定间距

### 修复

- **GitHub Actions Release Notes**
  - 修复标签 `vX.Y.Z` 与 `CHANGELOG.md` 中 `[X.Y.Z]` 的提取不一致问题
  - 当 changelog 缺少对应版本条目时，工作流会直接失败而不是生成空说明

- **仓库配置卫生**
  - `android/voice_coding/android/local.properties` 改为本地未跟踪文件，不再进入版本控制
  - 同步修正文档中本地 Java 配置与打包命令描述

### 测试

- Android：
  - `flutter test test/connection_recovery_policy_test.dart test/voicing_protocol_contract_test.dart`
  - `flutter analyze --no-fatal-infos --no-fatal-warnings`
- PC：
  - `python -m unittest tests.test_network_recovery tests.test_protocol_contract`
  - `python -m py_compile voice_coding.py network_recovery.py voicing_protocol.py`

---

## [2.4.2] - 2026-04-11

### 修复

- **Android 息屏唤醒后的假断连**
  - 前台恢复时不再信任休眠前的旧 WebSocket，而是直接强制重建连接
  - WebSocket 连接新增 8 秒超时，避免状态卡在 `connecting`
  - 新增连接代次隔离，旧 socket 的 `onDone` / `onError` 不再覆盖新连接状态
  - 即使 UDP 广播的 IP 和端口没有变化，只要当前未连接，广播也会触发恢复重连

- **PC 端热点地址漂移**
  - UDP 广播改为每轮重新检测热点 IP，避免电脑网络恢复后继续广播旧地址

### 测试

- **Android 连接恢复策略测试**
  - 新增 `android/voice_coding/test/connection_recovery_policy_test.dart`
  - 覆盖前台恢复、心跳超时、同 IP UDP 恢复、连接冷却窗口

- **PC 广播恢复逻辑测试**
  - 新增 `pc/tests/test_network_recovery.py`
  - 覆盖热点 IP 变化判定和 UDP 广播负载生成

---

## [2.4.1] - 2026-04-08

### 改进

- **Android UI 优化（基于 UI Skill 规范）**
  - 提取 AppSpacing/AppColors 设计常量，消除全文硬编码的 magic numbers
  - 间距对齐 4px 网格系统（13.5→12, 12.5→12）
  - 触摸目标添加 minHeight: 44pt（符合移动端最低标准）
  - GestureDetector 替换为 InkWell，添加 Material 涟漪触摸反馈
  - 下拉菜单从 3 个独立浮动卡片改为单一分组卡片 + Divider 分隔（iOS grouped list 风格）
  - 动画时长统一为 250ms（原 200/250/300ms 混用）
  - 底部提示添加细分隔线
  - 菜单关闭逻辑提取为 _closeMenu() 方法

- **PC 端托盘菜单 UI 优化**
  - 菜单项添加按压视觉反馈（pressed state: white 10% 背景）
  - 添加 Escape 键关闭菜单（Windows 11 Fluent Design 标准行为）
  - 菜单项间距从 2px 调整为 4px（更舒适的视觉间距）

---

## [2.4.0] - 2026-04-08

### 修复

- **Android 待机断连问题**
  - 根因：App 不处理 `paused` 生命周期，无心跳机制，息屏后 WebSocket 静默死亡
  - 新增心跳机制：每 15 秒发送 ping，30 秒无响应判定连接死亡
  - 完善生命周期处理：息屏时停止心跳省电，亮屏时立即验证连接有效性
  - 改进重连策略：指数退避（3s → 6s → 12s → 最大 30s），替代固定 3 秒重试
  - 发送失败时立即触发断连处理

- **PC 端异步阻塞**
  - 问题：`type_text()` 在 async WebSocket handler 中同步调用，阻塞整个事件循环
  - 修复：使用 `asyncio.to_thread()` 将阻塞操作放入线程池

### 改进

- **EXE 图标裁剪为圆形**
  - 将正方形图标裁剪为圆形，与 Android 端统一风格
  - 重新生成多尺寸 ICO 文件（256/128/64/48/32/16px）

- **PC 端代码质量**
  - 5 处裸 `except:` 改为 `except Exception:`，避免吞掉所有异常
  - `AppState` 添加 `threading.Lock` 保护 `connected_clients` 等共享状态
  - UDP 广播轮询从 `time.sleep` 循环改为 `threading.Event.wait`，退出更优雅
  - 删除未使用的 pystray 兼容代码（~120 行），项目已完全使用 PyQt5

- **依赖优化**
  - 移除 `pystray` 依赖（不再使用）
  - `requirements.txt` 版本约束从 `>=` 改为 `~=`，防止跨大版本升级

- **CI/CD**
  - Python 构建版本从 3.14（未稳定）改为 3.12
  - `.gitignore` 添加签名密钥模式（`*.jks`, `*.keystore`, `*.key`, `*.pem`）

---

## [2.3.1] - 2026-02-04

### 🔥 关键修复

- **Android 网络权限修复**
  - 问题：APK 无法连接 PC 端
  - 原因：AndroidManifest.xml 缺少网络权限声明
  - 解决：添加 INTERNET、ACCESS_NETWORK_STATE、ACCESS_WIFI_STATE 权限

- **Windows EXE 图标修复**
  - 问题：EXE 文件图标显示为默认图标，托盘图标显示为纯蓝色
  - 原因：PyInstaller 打包时未包含图标资源
  - 解决：添加 `--icon` 和 `--add-data` 参数

### 🔧 技术改进

- **ICO 文件优化**
  - 创建多尺寸 ICO 文件（256/128/64/48/32/16px）
  - 确保 Windows 各种显示场景下图标清晰

- **CI/CD 更新**
  - GitHub Actions release.yml 添加图标打包步骤
  - 添加 PNG 转 ICO 自动化流程

---

## [2.3.0] - 2026-02-04

### 🎨 品牌更新

- **应用重命名：Voice Coding → Voicing** 🎯
  - 更现代、简洁的品牌名称
  - **Android 端**：
    - `AndroidManifest.xml` 应用标签更新
    - `pubspec.yaml` 包名更新
    - `main.dart` 应用标题更新
  - **PC 端**：
    - 应用名称、互斥锁名称、日志目录全部更新
    - 托盘提示文字更新
    - 错误消息更新

### 🔧 构建修复

- **Flutter 构建 Java 版本问题修复**
  - 问题：系统 JAVA_HOME 指向 Java 25，导致 Gradle 构建失败
  - 错误特征：`Error resolving plugin > 25.0.1`
  - 解决：在 `gradle.properties` 中指定 Java 21 路径
  - 新增规则到 `CLAUDE.md` 防止再次发生

- **Windows EXE 图标修复** 🎯
  - 问题：GitHub Actions 构建的 EXE 缺少图标资源
  - 表现：EXE 文件图标为默认图标，托盘图标显示为纯蓝色
  - 解决：PyInstaller 添加 `--icon` 和 `--add-data` 参数
  - 新增 PNG 转 ICO 步骤

- **Android 网络权限修复** 🔥
  - 问题：AndroidManifest.xml 缺少网络权限声明
  - 表现：APK 无法连接 PC 端
  - 解决：添加 INTERNET、ACCESS_NETWORK_STATE、ACCESS_WIFI_STATE 权限

### 🎯 PC 端托盘图标优化

- **圆形图标**：托盘图标改为圆形外轮廓，与微信等主流应用风格一致
- **图标放大**：256px 高清图标，系统自动缩放
- **悬停提示**：鼠标悬停显示 "Voicing" 提示窗口
- **只响应右键**：左键不再触发菜单，只有右键才显示菜单

### 🐛 Bug 修复

- **闪烁均匀化**：预缓存所有图标状态，解决闪烁时快时慢的问题
- **首次菜单加速**：预加载菜单组件，首次打开不再卡顿
- **闪烁速度**：调整为 200ms 间隔

### 📝 文档更新

- `CLAUDE.md` 新增 Flutter 构建 Java 版本规则
- 记录本机 Java 21 路径：`C:\dev\java21\jdk-21.0.2`
- 记录 Flutter 启动命令
- **README 添加应用图标** - 在标题区域展示 128px 应用图标

---

## [2.2.1] - 2026-02-04

### 🎨 优化改进

- **PC 端托盘图标优化** 🎯
  - 透明背景：去掉深蓝色底色，改为透明背景
  - 放大图标：麦克风占满更多空间，托盘中更清晰
  - 简化状态逻辑：
    - 已连接：正常彩色图标（去掉绿色边框）
    - 等待连接：图标闪烁（透明度变化）
    - 暂停：灰色图标（去掉暂停条）

### 🔧 技术改进

- 重新生成 `pc/assets/icon_1024.png` 为透明背景版本
- 简化 `create_icon_connected()` 函数，直接返回原图
- 简化 `create_icon_paused()` 函数，只做灰度转换

---

## [2.2.0] - 2026-02-04

### 🎨 新增功能

- **自定义应用图标** 🎯
  - 设计了专属 Voice Coding 图标（麦克风+声波元素）
  - 蓝色渐变配色（#4A90E2 → #00D4FF）
  - 深色背景（#1A1A2E）
  - **Android 端**：支持自适应图标（Adaptive Icon）
  - **PC 端**：托盘图标同步更新为新设计
    - 已连接：图标 + 绿色边框
    - 等待连接：正常图标（闪烁动画）
    - 暂停：灰度图标 + 暂停条标记

### 🔧 技术改进

- **Android 端**
  - 添加 `flutter_launcher_icons` 依赖自动生成各尺寸图标
  - 配置 `assets/icons/` 目录存放原始图标资源
  - 生成完整 mipmap 资源集（mdpi ~ xxxhdpi）
  - 配置 `mipmap-anydpi-v26` 自适应图标 XML

- **PC 端**
  - 新增 `load_base_icon()` 函数加载 PNG 图标
  - 重写 `create_icon_*()` 系列函数使用新图标
  - 更新 `ModernTrayIcon` 类使用新图标
  - 更新 `VoiceCoding.spec` 打包配置

### 📁 新增文件

- `android/voice_coding/assets/icons/icon_1024.png` - Android 原始设计稿
- `pc/assets/icon_1024.png` - PC 端图标资源
- `drawable-*/ic_launcher_foreground.png` - 前景图层
- `mipmap-anydpi-v26/ic_launcher.xml` - 自适应图标配置
- `values/colors.xml` - 背景色定义

---

## [2.1.0] - 2026-02-03

### ✨ 新增功能

- **自动发送** 🎯
  - 语音输入实时同步到电脑
  - 智能检测输入法 composing 状态（下划线）
  - 下划线消失时自动发送（输入法完成优化后）
  - 增量发送：只发送新增内容，不影响已有文本
  - 支持连续多段语音输入
  - 开关状态记忆：重启APP后保持上次的开关状态

### 🔧 技术改进

- 使用 `TextEditingController.addListener()` 监听文本状态变化
- 检测 `composing.isValid` 判断输入法是否正在组合文本
- 自动重置 `_lastSentLength` 防止发送失败

---

## [2.0.1] - 2026-02-03

### 🐛 修复问题

- **GitHub Actions 构建修复** - 修复 Android APK 构建失败问题
  - 移除 gradle.properties 中的本地代理配置
  - 修正 Gradle wrapper 配置

---

## [2.0.0] - 2026-02-03

> **重大更新** - 架构简化，专注 PC + Android 双端体验

### ✨ 新增功能

- **UDP 自动发现** 📡
  - 手机 APK 自动发现并连接 PC 服务器
  - PC 端每 2 秒广播服务器信息（IP、端口、设备名）
  - Android 端监听 UDP 广播端口 9530
  - 无需手动配置 IP 地址，支持任意网段
  - 兼容非默认热点 IP（如 192.168.0.1、10.0.0.1 等）

- **撤回功能** 🔄
  - Android 端可恢复最近发送的文本
  - 点击"撤回上次输入"即可恢复

### 🗑️ 移除功能

- Web 端功能（HTTP/HTTPS 服务器和 Web UI）
- PWA 安装支持
- ngrok 隧道功能

### 🔧 变更优化

- **架构简化** - 专注于 PC EXE + Android APK 双端
- **依赖精简** - 移除 cryptography、pyngrok、pyyaml
- **包名更新** - Android 应用 ID: `com.voicecoding.app`
- **构建优化** - GitHub Actions 配置更新

### 📦 下载

- [Android APK](https://github.com/kevinlasnh/Voicing/releases/latest) - 安装到手机
- [Windows EXE](https://github.com/kevinlasnh/Voicing/releases/latest) - 电脑端运行

---

## [1.8.0] - 2026-02-03

### ✨ 新增功能

- **Windows 11 Fluent Design 风格托盘菜单** 🎨
  - 深色半透明背景
  - 圆角设计 + 柔和阴影
  - 滑出动画效果
  - 悬停高亮效果

- **日志系统** 📋
  - 日志文件位置：`%APPDATA%\Voicing\logs\`
  - 托盘菜单"打开日志"快捷入口

### 🐛 修复问题

- PyQt5 菜单悬停高亮效果
- 菜单点击崩溃问题
- 菜单位置对齐问题

---

## [1.6.0] - 2026-02-02

### ✨ 新增功能

- **手动刷新连接** - Android 端新增"刷新连接"按钮
- **PC 热重启脚本** - 开发快速重启

### 🎨 UI 重新设计

- 状态栏连接状态 + 刷新按钮分栏显示
- 输入框配色与状态栏统一
- 移除输入框边框，简洁统一

---

## [1.0.0] - 2026-01-21

### 🎉 首次发布

- **PC 端**：系统托盘应用，接收手机文本并在光标处输入
- **Android 端**：Flutter 原生应用
- **WebSocket** 实时通信
- **开机自启**功能
- **自动断线重连**
- **Anthropic 风格 UI 设计**
