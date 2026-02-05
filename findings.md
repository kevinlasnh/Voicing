# Voicing 技术发现记录

> 记录项目开发过程中的重要技术发现和解决方案

---

## 关键技术实现

### 1. PyQt5 悬停高亮解决方案

**问题**：PyQt5 自定义 QWidget 的 CSS `:hover` 伪状态不工作

**解决方案**：
```python
# 1. 使用 paintEvent 手动绘制背景
def paintEvent(self, event):
    painter = QPainter(self)
    if self._hovered:
        painter.setBrush(QColor(255, 255, 255, 15))  # 白色 6% 透明度
    painter.drawRoundedRect(rect, 4, 4)

# 2. 子控件必须设置鼠标事件穿透
self.icon_label.setAttribute(Qt.WA_TransparentForMouseEvents)
self.text_label.setAttribute(Qt.WA_TransparentForMouseEvents)

# 3. 使用 enterEvent/leaveEvent 追踪悬停状态
def enterEvent(self, event):
    self._hovered = True
    self.update()
```

**位置**：`pc/voice_coding.py:511-539`

---

### 2. 自动发送功能 (Shadow Mode)

**原理**：利用 Flutter 的 `TextEditingController.value.composing` 检测输入法组合状态

```dart
// composing.isValid && !composing.isCollapsed = 输入法正在输入（下划线状态）
// !isComposing = 输入完成（下划线消失）

if (_wasComposing && !isComposing) {
    _sendShadowIncrement();  // 发送增量文本
}
```

**位置**：`android/voice_coding/lib/main.dart:344-362`

---

### 3. 剪贴板方式实现 Unicode 输入

**问题**：pyautogui.type() 无法处理中文等 Unicode 字符

**解决方案**：
```python
# 1. 保存当前剪贴板
old_clipboard = pyperclip.paste()

# 2. 复制新文本到剪贴板
pyperclip.copy(text)

# 3. 模拟 Ctrl+V 粘贴
pyautogui.hotkey('ctrl', 'v')

# 4. 等待完成
time.sleep(0.1)

# 5. 恢复原剪贴板
pyperclip.copy(old_clipboard)
```

**位置**：`pc/voice_coding.py:301-335`

---

### 4. Flutter 构建 Java 版本问题

**问题**：系统 JAVA_HOME 指向 Java 25，Gradle 构建失败

**错误特征**：
```
Error resolving plugin [id: 'dev.flutter.flutter-plugin-loader', version: '1.0.0']
> 25.0.1
```

**解决方案**：
- 在 `android/voice_coding/android/local.properties` 中指定 Java 路径
- **不要**在 `gradle.properties` 中设置（会导致 CI 构建失败）

```properties
org.gradle.java.home=C:\\dev\\java21\\jdk-21.0.2
```

**本机 Java 路径**：`C:\dev\java21\jdk-21.0.2`

---

### 5. GitHub Actions Gradle 配置

**关键规则**：`gradle.properties` 不能包含本地代理配置

```gradle
# ❌ 错误 - 会导致 CI 构建失败
systemProp.https.proxyHost=127.0.0.1
systemProp.https.proxyPort=7890
```

**正确配置**：
- `gradle-wrapper.properties` 使用官方源
- Gradle wrapper 文件必须提交到仓库

---

### 6. PC 热重启

**原因**：PC 端是 Python 长期运行的进程，代码修改后不会自动生效

**热重启命令**：
```powershell
powershell -ExecutionPolicy Bypass -File ".claude/skills/pc-hot-restart/restart_pc_dev.ps1"
```

---

## 设计系统

### 颜色

| 用途 | 颜色值 |
|------|--------|
| 背景深色 | `#3D3B37` |
| 文字白色 | `#ECECEC` |
| 成功绿色 | `#5CB87A` |
| 警告橙色 | `#E5A84B` |
| 错误红色 | `#E85C4A` |
| 灰色占位 | `#6B6B6B` |
| 图标背景 | `#1A1A2E` |

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

## 通信协议

### UDP 发现 (端口 9530)

```json
{
  "type": "voice_coding_server",
  "ip": "192.168.137.1",
  "port": 9527,
  "name": "主机名"
}
```

- PC 端每 2 秒广播一次
- Android 端监听并自动连接

### WebSocket 消息类型 (端口 9527)

| 方向 | 类型 | 用途 |
|------|------|------|
| PC → Android | `connected` | 连接确认 |
| PC → Android | `ack` | 文本接收确认 |
| PC → Android | `pong` | 心跳响应 |
| PC → Android | `sync_state` | 同步状态广播 |
| PC → Android | `sync_disabled` | 同步已禁用 |
| Android → PC | `text` | 文本输入 |
| Android → PC | `ping` | 心跳请求 |

---

## 关键文件位置

| 文件 | 说明 |
|------|------|
| `pc/voice_coding.py` | PC 端主程序 (1124 行) |
| `pc/voice_coding.py:96-109` | AppState 类 |
| `pc/voice_coding.py:457-563` | MenuItemWidget 类 |
| `pc/voice_coding.py:565-740` | ModernMenuWidget 类 |
| `pc/voice_coding.py:742-851` | ModernTrayIcon 类 |
| `android/voice_coding/lib/main.dart` | Android 主程序 (789 行) |
| `.github/workflows/release.yml` | CI/CD 配置 |

---

## 依赖版本

| 端 | 技术 | 版本 |
|------|------|------|
| PC | Python | 3.14 |
| PC | PyQt5 | >=5.15.0 |
| PC | websockets | >=12.0 |
| Android | Flutter | 3.27.0 |
| Android | Dart | ^3.5.4 |
| Android | web_socket_channel | ^2.4.0 |
