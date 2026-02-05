# 如何发布新版本

完整的版本发布流程指南，包括本地构建、CHANGELOG 更新、Git 标签推送和 CI/CD 发布。

1. **更新 CHANGELOG**: 在 `CHANGELOG.md` 中添加新版本条目，格式为 `## [版本号] - 日期`，列出所有变更。参考 `CLAUDE.md` 中的强制规则。

2. **提交代码**: `git add` 和 `git commit` 提交代码和 CHANGELOG。

3. **创建 Git 标签**: 使用 `git tag v2.3.1` 创建版本标签 (必须以 `v` 开头，与 CHANGELOG 版本一致)。

4. **推送标签**: `git push origin v2.3.1` 推送标签触发 GitHub Actions 工作流。

5. **验证构建**: 在 GitHub Actions 页面查看构建状态，确认 `build-android` 和 `build-windows` 两个 job 成功完成，Release 自动创建。

## 本地构建

### PC 端
```powershell
cd pc
pip install -r requirements.txt
pyinstaller VoiceCoding.spec
```
输出: `pc/dist/VoiceCoding.exe`

### Android 端
```powershell
cd android/voice_coding
flutter pub get
flutter build apk --release
```
输出: `android/voice_coding/build/app/outputs/flutter-apk/app-release.apk`

## 生成 Android 图标
```powershell
cd android/voice_coding
flutter pub run flutter_launcher_icons
```

## CI/CD 故障排查

### Gradle 构建失败
- **错误**: `java.net.ConnectException: Connection refused`
- **原因**: `android/voice_coding/android/gradle.properties` 包含本地代理配置
- **解决**: 删除 `systemProp.https.proxy*` 配置，本地 Java 路径应在 `local.properties` 中设置

### Java 版本不兼容
- **错误**: `Error resolving plugin > 25.0.1`
- **原因**: 系统使用不兼容的 Java 版本 (如 Java 25)
- **解决**: 在 `android/voice_coding/android/local.properties` 设置 `org.gradle.java.home=C:\dev\java21\jdk-21.0.2`

### EXE 图标缺失
- **原因**: PyInstaller 未包含 `--icon` 和 `--add-data` 参数
- **解决**: 确保 `pc/assets/icon.ico` 存在，使用完整命令: `pyinstaller --onefile --windowed --name=VoiceCoding --icon=assets/icon.ico --add-data "assets;assets" voice_coding.py`

### APK 网络连接失败
- **原因**: `AndroidManifest.xml` 缺少网络权限
- **解决**: 添加 `INTERNET`、`ACCESS_NETWORK_STATE`、`ACCESS_WIFI_STATE` 权限
