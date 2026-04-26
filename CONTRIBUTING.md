# Contributing to Voicing

[English](#english) | [简体中文](#简体中文)

---

## English

Thanks for your interest in contributing to Voicing!

### How to contribute

#### Report a bug

1. Search [Issues](https://github.com/kevinlasnh/Voicing/issues) for an existing report
2. If none exists, open a new issue including:
   - A description of the problem
   - Steps to reproduce
   - Expected behavior
   - Actual behavior
   - Environment info (Windows version, Python version, etc.)

#### Suggest a feature

1. Open a new issue tagged `enhancement`
2. Describe the requirement and the use case

#### Submit code

1. Fork this repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit changes — Conventional Commits preferred, e.g. `fix(android): stabilize recovery flow`
4. Push the branch: `git push origin feature/your-feature`
5. Open a Pull Request

### Code style

- Python code follows PEP 8
- Dart / Flutter code preserves the existing theme tokens and controller layout
- Use meaningful names for variables and functions
- Add comments only when the WHY is non-obvious (bilingual is fine)
- Keep code concise
- Any change to user-visible behavior must update `CHANGELOG.md`, `README.md`, and the relevant subdirectory docs in the same PR

### Dev environment

```bash
# Clone
git clone https://github.com/kevinlasnh/Voicing.git
cd Voicing

# Desktop
cd pc
pip install -r requirements.txt
python voice_coding.py --dev

# Android
cd android/voice_coding
flutter pub get
flutter run
```

### Testing

Before submitting a PR, please make sure:
1. Android passes:
   - `flutter test`
   - `flutter analyze --no-fatal-infos --no-fatal-warnings`
2. PC passes:
   - `python -m unittest discover -s tests`
   - `python -m py_compile voice_coding.py network_recovery.py voicing_protocol.py device_identity.py`
3. The app launches correctly, the phone connects, and text reaches the desktop
4. If Android native code changed (`MainActivity.kt` / Manifest / Gradle), you must reinstall the full APK to verify — Flutter hot restart is not enough

### Release

- Production releases run via GitHub Actions:
  - `git push origin main`
  - `git tag vX.Y.Z`
  - `git push origin vX.Y.Z`
- Android release builds in CI are pinned to Java 17
- Release signing secrets are required; the workflow fails fast if they are missing
- Each release ships `SHA256SUMS.txt` for artifact integrity verification
- Before release, make sure `CHANGELOG.md`, `README.md`, and `android/README.md` reflect the current capabilities

---

## 简体中文

感谢您有兴趣为 Voicing 做出贡献！

### 如何贡献

#### 报告 Bug

1. 在 [Issues](https://github.com/kevinlasnh/Voicing/issues) 中搜索是否已有相同问题
2. 如果没有，创建新 Issue，包含：
   - 问题描述
   - 复现步骤
   - 期望行为
   - 实际行为
   - 环境信息（Windows 版本、Python 版本等）

#### 提交功能建议

1. 创建新 Issue，标记为 `enhancement`
2. 描述功能需求和使用场景

#### 提交代码

1. Fork 本仓库
2. 创建功能分支：`git checkout -b feature/your-feature`
3. 提交更改：优先使用 Conventional Commits，例如 `fix(android): stabilize recovery flow`
4. 推送分支：`git push origin feature/your-feature`
5. 创建 Pull Request

### 代码规范

- Python 代码遵循 PEP 8
- Dart / Flutter 代码保持现有主题 token 与控制器拆分结构
- 使用有意义的变量名和函数名
- 添加必要的注释（中英双语优先）
- 保持代码简洁
- 涉及用户可见行为的改动，需要同步更新 `CHANGELOG.md`、`README.md` 和相关子目录文档

### 开发环境

```bash
# 克隆仓库
git clone https://github.com/kevinlasnh/Voicing.git
cd Voicing

# PC 端
cd pc
pip install -r requirements.txt
python voice_coding.py --dev

# Android 端
cd android/voice_coding
flutter pub get
flutter run
```

### 测试

在提交 PR 前，请确保：
1. Android 端通过：
   - `flutter test`
   - `flutter analyze --no-fatal-infos --no-fatal-warnings`
2. PC 端通过：
   - `python -m unittest discover -s tests`
   - `python -m py_compile voice_coding.py network_recovery.py voicing_protocol.py device_identity.py`
3. 程序能正常启动，手机端能正常连接，文本能正常发送到电脑
4. 如果改动 Android 原生层（`MainActivity.kt` / Manifest / Gradle），必须完整重新安装 APK 后验证，不能只依赖 Flutter hot restart

### 发布

- 正式发布通过 GitHub Actions 触发：
  - `git push origin main`
  - `git tag vX.Y.Z`
  - `git push origin vX.Y.Z`
- Android release 构建在 CI 中固定使用 Java 17
- 正式 Release 现在要求配置 Android release signing secrets，缺失时 workflow 会直接失败
- Release 会附带 `SHA256SUMS.txt`，用于产物完整性校验
- 发布前需确保 `CHANGELOG.md`、`README.md` 和 `android/README.md` 已同步当前版本能力

---

Thanks again for your contribution! / 再次感谢您的贡献！
