# 构建与部署架构

## 1. Identity

- **是什么**: 双平台自动化构建与发布系统
- **用途**: 将 PC 端 Python 代码和 Android 端 Flutter 代码打包为可分发的 EXE 和 APK 文件

## 2. Core Components

### PC 端构建
- `pc/VoiceCoding.spec` (PyInstaller Spec): PyInstaller 配置文件，定义单文件打包参数、资源嵌入、UPX 压缩
- `pc/requirements.txt` (pyinstaller, PyQt5, websockets, pyautogui): Python 依赖列表
- `pc/assets/icon_1024.png`: 托盘图标源文件 (1024x1024)
- `pc/assets/icon.ico`: EXE 文件图标 (多尺寸 ICO)

### Android 端构建
- `android/voice_coding/pubspec.yaml` (flutter_launcher_icons): Flutter 配置，包含图标生成插件配置
- `android/voice_coding/android/app/build.gradle` (applicationId, namespace): 应用构建配置，定义包名、签名、编译选项
- `android/voice_coding/android/build.gradle` (Maven repositories): 项目级 Gradle 配置，使用阿里云镜像加速
- `android/voice_coding/android/gradle/wrapper/gradle-wrapper.properties`: Gradle 8.12 官方分发源
- `android/voice_coding/android/gradle.properties`: JVM 参数配置，无代理设置
- `android/voice_coding/android/app/src/main/AndroidManifest.xml`: 网络权限声明 (INTERNET, ACCESS_NETWORK_STATE, ACCESS_WIFI_STATE)

### CI/CD 配置
- `.github/workflows/release.yml` (build-android, build-windows, release jobs): GitHub Actions 工作流，自动构建并创建 Release

## 3. Execution Flow (LLM Retrieval Map)

### PC 端构建流程
1. **依赖安装**: `pip install -r requirements.txt` 安装 PyInstaller 等依赖
2. **资源打包**: PyInstaller 通过 `--add-data "assets;assets"` 将图标资源嵌入 EXE
3. **EXE 生成**: `pyinstaller --onefile --windowed --name=VoiceCoding --icon=assets/icon.ico` 生成单文件可执行程序
4. **输出重命名**: `VoiceCoding.exe` → `voicing.exe`

### Android 端构建流程
1. **图标生成**: `flutter pub run flutter_launcher_icons` 从 `assets/icons/icon_1024.png` 生成各 DPI 图标
2. **依赖获取**: `flutter pub get` 下载 Dart 依赖
3. **Gradle 构建**: `flutter build apk --release` 调用 Gradle 构建 APK
4. **输出重命名**: `app-release.apk` → `voicing.apk`

### CI/CD 工作流
1. **触发**: 推送 Git 标签 (如 `v2.3.1`) 触发 `.github/workflows/release.yml`
2. **并行构建**:
   - `build-android` job: Ubuntu + Java 17 + Flutter 3.27.0 → 生成 `voicing.apk`
   - `build-windows` job: Windows + Python 3.14 + PyInstaller → 生成 `voicing.exe`
3. **Changelog 提取**: 从 `CHANGELOG.md` 提取对应版本的更新日志
4. **Release 创建**: `softprops/action-gh-release@v1` 创建 GitHub Release，上传构建产物

### 图标管理流程
1. **设计**: 1024x1024 PNG 图标 (麦克风 + 声波，蓝色渐变 `#4A90E2` → `#00D4FF`)
2. **PC 端**: 运行时使用 `pc/voice_coding.py` (`load_base_icon`, `create_icon_*`) 动态生成状态图标
3. **Android 端**: `flutter_launcher_icons` 插件自动生成自适应图标 (Adaptive Icon)，背景色 `#1A1A2E`

## 4. Design Rationale

- **单文件打包**: PyInstaller `--onefile` 简化分发，用户无需安装 Python 运行时
- **资源嵌入**: `--add-data` 确保图标资源打包进 EXE，避免路径依赖
- **阿里云镜像**: 加速国内 Gradle 依赖下载，提高 CI/CD 稳定性
- **无代理配置**: `gradle.properties` 不包含本地代理设置，避免 CI 构建失败
- **语义化版本**: CHANGELOG.md 版本号与 Git 标签保持一致 (如 `v2.3.1`)
- **debug 签名**: 当前使用 debug key 签名 APK，生产环境需配置正式签名
