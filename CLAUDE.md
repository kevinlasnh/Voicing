# Voicing 开发规范

## 开发联调工作流（双端实时调试）

### 已注册测试设备

| 类型 | 名称 | Flutter ID | 平台 |
|------|------|------------|------|
| 手机 | Pixel 5 | `0B221FDD40005P` | android-arm64 / Android 14 |
| 电脑 | 本机 Windows | `windows` | windows-x64 |

> 新增设备时直接更新这张表。Agent 应优先用表里的 ID 跑 `flutter run -d <id>`，避免选错设备。

### 触发词

当用户说"**启动开发环境**" / "**启动联调**" / "**开始热重启测试**"时，agent 必须按下方"标准启动序列"执行，**不要询问、不要逐项确认**，直接连续跑完。

### 标准启动序列

```bash
# Step 1: 检查 Pixel 5 是否在线（必须先做）
flutter devices --machine | grep -q "0B221FDD40005P" || echo "❌ Pixel 5 未连接"

# Step 2: PC 端热重启（脚本会自动 kill 旧进程再启动新进程）
powershell -ExecutionPolicy Bypass -File ".claude/skills/pc-hot-restart/restart_pc_dev.ps1"

# Step 3: Flutter 后台运行到 Pixel 5（保留 hot reload 能力）
cd android/voice_coding && flutter run -d 0B221FDD40005P
```

### 双端改动后的迭代规则

| 改动位置 | 生效方式 | 命令 |
|----------|---------|------|
| `pc/voice_coding.py` 等 PC 端 Python | **必须 PC 热重启**（Python 长进程不会自动重载） | `powershell -ExecutionPolicy Bypass -File ".claude/skills/pc-hot-restart/restart_pc_dev.ps1"` |
| `android/voice_coding/lib/**.dart` UI / 业务逻辑 | **Flutter 热重载**（`r` 键，毫秒级） | 在 `flutter run` 终端按 `r` |
| Dart 状态/类结构改动 / 新增 import | **Flutter 热重启**（`R` 键，约 1-2s） | 在 `flutter run` 终端按 `R` |
| `pubspec.yaml` 依赖变更 | 必须停掉 flutter run，`flutter pub get`，再 `flutter run` | — |

### 设备连接自检

每次开始联调前 agent 自动跑一次：

```bash
flutter devices --machine
```

并解析 JSON 检查 Pixel 5 (`0B221FDD40005P`) 在线。**不在线就直接报告用户**"Pixel 5 未检测到，请检查 USB 连接 / 是否解锁屏幕 / 是否信任本电脑"，**不要继续后续步骤**。

### 关键约束

- **Flutter run 必须用 `run_in_background: true` 启动**，否则会阻塞 agent 后续工具调用
- **PC 热重启脚本是同步的**（kill + start 即返回），不需要后台
- **手机端 UI 改动优先用热重载（`r`）**，只有改了状态机 / 类结构才用热重启（`R`）
- **每次关键改动后必须更新 CHANGELOG.md**（参见下方"强制规则"）

---

## 当前状态（2026-04-17）

- 当前版本：`v2.7.2`
- 最新 Release：`https://github.com/kevinlasnh/Voicing/releases/latest`
- 最新构建产物：
  - `voicing.apk`
  - `voicing-windows-x64.exe`
  - `voicing-macos-arm64.dmg`
  - `voicing-linux-x86_64`
- PC 端 UDP 发现：按可用私有 IPv4 接口分别发送定向广播，同时覆盖热点和同一路由器局域网
- Release 安全性：GitHub Actions 已改为 SHA pin，正式 Android Release 强制校验签名 secrets，并附带 `SHA256SUMS.txt`

## ⚠️ 强制规则

### 每次代码修改后必须更新 CHANGELOG

**以下情况必须撰写 CHANGELOG：**
- 代码有功能改动（新增、修改、删除功能）
- Bug 修复
- UI/UI 样式变更
- 配置文件变更
- 依赖库版本变更

**流程：**
1. 修改代码
2. **立即更新 CHANGELOG.md**
3. Git commit
4. Git push

### PC 端代码修改后必须热重启

**修改 PC 端代码 (`pc/voice_coding.py`) 后，必须强制进行热重启操作！**

**热重启命令：**
```powershell
powershell -ExecutionPolicy Bypass -File ".claude/skills/pc-hot-restart/restart_pc_dev.ps1"
```

**原因**：PC 端是 Python 长期运行的进程，修改代码后不会自动生效，必须手动重启。

### Flutter 构建必须使用 Java 17/21

**问题**：系统 JAVA_HOME 可能指向不兼容的 Java 版本（如 Java 25），导致 Gradle 构建失败。

**错误特征**：
```
Error resolving plugin [id: 'dev.flutter.flutter-plugin-loader', version: '1.0.0']
> 25.0.1
```
这里的 `25.0.1` 是 Java 版本号，说明使用了不兼容的 Java 版本。

**当前现状**：
- 本机 `flutter doctor --verbose` 显示 Android toolchain 正在使用 Java 25
- 本地 `flutter build apk --release` 会因 Java 25 / Gradle 兼容性失败
- GitHub Actions 发布环境使用 Java 17，正式 Release 会强制要求 Android release signing secrets

**解决方案**：安装兼容的 JDK 17/21，并在 `android/voice_coding/android/local.properties` 中指定 Java 路径（此文件不提交到 Git）：
```properties
org.gradle.java.home=C:\\path\\to\\jdk-17-or-21
```

**注意**：不要在 `gradle.properties` 中设置本地路径，否则会导致 CI 构建失败。

**Flutter 启动命令（PowerShell）**：
```powershell
cd C:\Zero\Doc\Cloud\GitHub\Voicing\android\voice_coding
flutter run
```

---

## 项目架构

### PC 端 (Python)
- **主程序**: `pc/voice_coding.py`
- **依赖**: `pc/requirements.txt`

### Android 端 (Flutter)
- **主程序**: `android/voice_coding/lib/main.dart`
- **连接状态机**: `android/voice_coding/lib/voicing_connection_controller.dart`
- **恢复策略**: `android/voice_coding/lib/connection_recovery_policy.dart`
- **协议常量**: `android/voice_coding/lib/voicing_protocol.dart`
- **依赖**: `android/voice_coding/pubspec.yaml`

---

## 开发命令

### PC 端热重启
```powershell
powershell -ExecutionPolicy Bypass -File ".claude/skills/pc-hot-restart/restart_pc_dev.ps1"
```

### PC 端打包
```bash
cd pc
pyinstaller --onefile --windowed --name=VoiceCoding voice_coding.py
```

### Android 端运行
```bash
cd android/voice_coding
flutter run
```

### Android 端验证
```bash
cd android/voice_coding
flutter test
flutter analyze --no-fatal-infos --no-fatal-warnings
```

### PC 端验证
```bash
cd pc
python -m unittest discover -s tests
python -m py_compile voice_coding.py network_recovery.py voicing_protocol.py
```

---

## 当前协议约束（v2.7.2）

- UDP 发现改为**定向广播**：枚举所有私有 IPv4 接口，按子网分别发送，同时覆盖热点和局域网
- `TYPE_TEXT` 现在带 `send_mode`
  - `submit`：普通手动发送，可选 `auto_enter`
  - `shadow`：语音分段增量发送，不直接触发 Enter
  - `commit`：只提交 Enter，不重复输入文本
- `ack` 现在带 `clear_input`
  - 仅 `submit` 由服务端确认后清空输入框
  - `shadow / commit` 改为客户端自己控制 finalize 与清空时机

---

## 设计规范

### 颜色
- 背景深色: `#3D3B37`
- 文字白色: `#ECECEC`
- 成功绿色: `#5CB87A`
- 警告橙色: `#E5A84B`
- 错误红色: `#E85C4A`
- 灰色占位: `#6B6B6B`

### 间距
- 边缘 padding: 16px
- 组件内 padding: 14px
- 组件间距: 12px
- 圆角: 12px

### 字体
- 正文: 16px
- 状态文字: 15px, fontWeight 600
- 提示文字: 13px

---

## CI/CD 规则 (GitHub Actions)

### ⚠️ Android Gradle 构建配置

**问题根源**: GitHub Actions runner 网络环境特殊，配置不当会导致 Gradle 下载失败。

**必须遵守的规则**:

1. **gradle.properties 不能包含本地代理配置**
   ```gradle
   # ❌ 错误 - 会导致 CI 构建失败
   systemProp.https.proxyHost=127.0.0.1
   systemProp.https.proxyPort=7890
   ```

2. **gradle-wrapper.properties 使用官方源**
   ```properties
   # ✅ 正确
   distributionUrl=https\://services.gradle.org/distributions/gradle-8.12-all.zip
   ```

3. **Gradle wrapper 文件必须提交到仓库**
   - `android/voice_coding/gradlew`
   - `android/voice_coding/gradlew.bat`
   - `android/voice_coding/gradle/wrapper/gradle-wrapper.jar`
   - `android/voice_coding/gradle/wrapper/gradle-wrapper.properties`

4. **GitHub Actions workflow 配置**
   ```yaml
   - name: Set up Java
     uses: actions/setup-java@v4
     with:
       distribution: 'zulu'
       java-version: '17'

   - name: Set up Flutter
     uses: subosito/flutter-action@v2
     with:
       flutter-version: 3.27.0
       cache: true

   - name: Build APK
     run: flutter build apk --release
   ```

**常见错误**: `java.net.ConnectException: Connection refused`
- 原因: gradle.properties 配置了本地代理
- 解决: 删除代理配置或使用 `gradle.properties` 模板文件

---

## 历史开发状态 (2026-02-04)

### ✅ 已完成功能

#### PC 端托盘图标优化 (v2.3.0) - 最新
- **圆形图标**：256px 高清，圆形外轮廓
- **图标缓存**：预缓存 normal/dim/paused 三种状态，闪烁均匀
- **悬停提示**：鼠标悬停显示 "Voicing"
- **只响应右键**：左键不触发菜单
- **菜单预加载**：首次打开快速

#### PC 端托盘菜单 (v1.8.0)
- **Windows 11 Fluent Design 风格** - 完整实现
- **悬停高亮效果** - 使用 `paintEvent` + `WA_TransparentForMouseEvents` 解决
- **日志系统** - 日志文件位于 `%APPDATA%\Voicing\logs\`
- **菜单项**:
  - 📡 同步输入（开关）
  - 🚀 开机自启（开关）
  - 📋 打开日志
  - 🚪 退出应用

#### 关键技术实现

**PyQt5 悬停高亮解决方案** (重要！):
```python
# 问题：PyQt5 自定义 QWidget 的 :hover CSS 伪状态不工作
# 解决方案：

# 1. 使用 paintEvent 手动绘制背景
def paintEvent(self, event):
    painter = QPainter(self)
    if self._hovered:
        painter.setBrush(QColor(255, 255, 255, 15))
    painter.drawRoundedRect(rect, 4, 4)

# 2. 子控件必须设置鼠标事件穿透
self.icon_label.setAttribute(Qt.WA_TransparentForMouseEvents)
self.text_label.setAttribute(Qt.WA_TransparentForMouseEvents)

# 3. 使用 enterEvent/leaveEvent 追踪悬停状态
def enterEvent(self, event):
    self._hovered = True
    self.update()
```

### 📁 关键文件位置

| 文件 | 说明 |
|------|------|
| `pc/voice_coding.py` | PC 端主程序 |
| `pc/voice_coding.py:695-800` | `MenuItemWidget` 类 - 菜单项组件 |
| `pc/voice_coding.py:802-970` | `ModernMenuWidget` 类 - 菜单容器 |
| `pc/voice_coding.py:972-1070` | `ModernTrayIcon` 类 - 托盘图标 |
| `pc/voice_coding.py:138-170` | `setup_logging()` 日志配置 |

### 🔧 开发工具

**PC 热重启命令**:
```powershell
powershell -ExecutionPolicy Bypass -File ".claude/skills/pc-hot-restart/restart_pc_dev.ps1"
```

### ⚠️ 注意事项

1. **不要使用 QSS :hover** - PyQt5 自定义 QWidget 不支持
2. **子控件必须穿透鼠标事件** - 否则 enterEvent/leaveEvent 不会触发
3. **使用 state.tray_icon** - 不要传 None 给 update_tray_icon_pyqt()

