# Voicing Coding Conventions

## 1. Design System

### Colors
| Usage | Value |
|-------|-------|
| Background dark | `#3D3B37` |
| Text primary | `#ECECEC` |
| Success/connected | `#5CB87A` |
| Warning/sync disabled | `#E5A84B` |
| Error/disconnected | `#E85C4A` |
| Placeholder/disabled | `#6B6B6B` |
| Icon background | `#1A1A2E` |

### Spacing
- Edge padding: `16px`
- Component inner padding: `14px`
- Component gap: `12px`
- Border radius: `12px`

### Typography
| Element | Size | Weight |
|---------|------|--------|
| Body text | 16px | normal |
| Status text | 15px | 600 |
| Hint text | 13px | normal |

## 2. PC End (Python/PyQt5)

### PyQt5 Hover Highlight Pattern
PyQt5 custom QWidget does not support CSS `:hover`. Use this pattern:

```python
class CustomWidget(QWidget):
    def __init__(self):
        self._hovered = False
        # Child widgets MUST have mouse events穿透
        child_widget.setAttribute(Qt.WA_TransparentForMouseEvents)

    def paintEvent(self, event):
        painter = QPainter(self)
        if self._hovered:
            painter.setBrush(QColor(255, 255, 255, 15))  # 6% white
            painter.drawRoundedRect(self.rect(), 4, 4)

    def enterEvent(self, event):
        self._hovered = True
        self.update()

    def leaveEvent(self, event):
        self._hovered = False
        self.update()
```

Reference: `pc/voice_coding.py:511-539`

### Menu Component Specs
- Item height: `36px`
- Item padding: `12px` horizontal
- Container radius: `8px`
- Hover radius: `4px`
- Font: `Segoe UI` / `Microsoft YaHei UI`, 13px

Reference: `pc/voice_coding.py:457-563` (MenuItemWidget)

## 3. Android End (Flutter/Dart)

### State Management
Use `setState()` for local state. No external state management library needed.

Reference: `android/voice_coding/lib/main.dart` (_MainPageState)

### Composing Detection (Auto-Send)
Monitor `TextEditingController.value.composing` for IME completion:

```dart
void _onTextControllerChanged() {
  final isComposing = controller.value.composing.isValid &&
                      !controller.value.composing.isCollapsed;

  if (_wasComposing && !isComposing) {
    _sendShadowIncrement();  // Send new characters only
  }
  _wasComposing = isComposing;
}
```

Reference: `android/voice_coding/lib/main.dart:304-330`

### Component Specs
- TextField: `maxLines: null`, `expands: true`
- Switch: 42x24px, radius 12px
- Status dot: 10x10px circular
- Menu animation: 250ms, easeOutCubic

## 4. Mandatory Rules

### CHANGELOG Update
Required for:
- Feature changes (add/modify/delete)
- Bug fixes
- UI/style changes
- Config changes
- Dependency version changes

Process: Modify code → Update CHANGELOG.md → Git commit → Git push

### PC Hot Restart
After modifying `pc/voice_coding.py`:
```powershell
powershell -ExecutionPolicy Bypass -File ".claude/skills/pc-hot-restart/restart_pc_dev.ps1"
```

Reason: PC is a long-running Python process, changes don't auto-apply.

### Flutter Java Version
Use Java 17/21 for Flutter builds. Set in `android/voice_coding/android/local.properties`:
```properties
org.gradle.java.home=C:\\dev\\java21\\jdk-21.0.2
```

**CRITICAL**: Never add local proxy settings to `gradle.properties` (breaks CI).

### Gradle for CI
- `gradle.properties`: No local proxy config
- `gradle-wrapper.properties`: Use official source
- Commit all gradle wrapper files to repo

Reference: `CLAUDE.md` CI/CD rules section

## 5. Source of Truth

- **Primary**: `CLAUDE.md` - Project-wide conventions
- **PC Architecture**: `/llmdoc/architecture/pc-end.md`
- **Android Architecture**: `/llmdoc/architecture/android-end.md`
- **UI Design**: `/llmdoc/architecture/ui-design-system.md`
- **Build Deployment**: `/llmdoc/architecture/build-deployment.md`
