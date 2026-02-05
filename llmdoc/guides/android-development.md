# 如何进行 Android 端开发

## 开发环境准备

1. **安装 Flutter SDK**: 确保 Flutter 版本为 3.27.0 或更高。
2. **配置 Java 版本**: Flutter 构建需要 Java 17 或 21。
   - 检查系统 JAVA_HOME 是否指向兼容版本
   - 本机 Java 路径: `C:\dev\java21\jdk-21.0.2`
3. **安装 Android SDK**: 通过 Android Studio 或 Flutter SDK 安装。

## 运行和调试

1. **连接设备**: 通过 USB 连接 Android 设备或启动模拟器。
2. **进入项目目录**: `cd C:\Zero\Doc\Cloud\GitHub\Voice-Coding\android\voice_coding`
3. **运行应用**:
   ```powershell
   C:\dev\flutter\bin\flutter.bat run -d 0B221FDD40005P
   ```
   （将 `0B221FDD40005P` 替换为实际设备 ID）
4. **热重载**: 修改代码后按 `r` 键触发热重载，按 `R` 键触发热重启。

## 打包 APK

1. **进入项目目录**: `cd android/voice_coding`
2. **构建 Release 版本**:
   ```bash
   flutter build apk --release
   ```
3. **APK 输出位置**: `build/app/outputs/flutter-apk/app-release.apk`

## Java 版本配置

如果遇到 Gradle 构建失败（如 Java 版本不兼容），在 `android/voice_coding/android/local.properties` 中指定 Java 路径：

```properties
org.gradle.java.home=C:\\dev\\java21\\jdk-21.0.2
```

**注意**: `local.properties` 文件不应提交到 Git。

## 关键代码位置索引

| 功能 | 文件位置 |
|------|----------|
| 应用入口和主题 | `android/voice_coding/lib/main.dart:9-55` |
| 主页面状态管理 | `android/voice_coding/lib/main.dart:64-789` |
| WebSocket 连接 | `android/voice_coding/lib/main.dart:161-188` |
| 消息处理 | `android/voice_coding/lib/main.dart:190-211` |
| UDP 自动发现 | `android/voice_coding/lib/main.dart:231-282` |
| 文本发送 | `android/voice_coding/lib/main.dart:284-302` |
| 自动发送监听 | `android/voice_coding/lib/main.dart:305-352` |
| 下拉菜单 UI | `android/voice_coding/lib/main.dart:504-718` |
| 文本输入框 | `android/voice_coding/lib/main.dart:739-769` |
| 依赖配置 | `android/voice_coding/pubspec.yaml` |
| Android 权限 | `android/voice_coding/android/app/src/main/AndroidManifest.xml` |

## 依赖安装

如果首次运行项目，需要安装依赖：

```bash
flutter pub get
```

## 常见问题

1. **Gradle 构建失败**: 检查 Java 版本，确认 `local.properties` 配置正确。
2. **网络权限错误**: 确认 `AndroidManifest.xml` 包含必要的权限。
3. **WebSocket 连接失败**: 确认 PC 端服务已启动，且设备在同一局域网。
