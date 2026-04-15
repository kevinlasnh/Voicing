# Contributing to Voicing / 贡献指南

感谢您有兴趣为 Voicing 做出贡献！

## 如何贡献

### 报告 Bug

1. 在 [Issues](https://github.com/kevinlasnh/Voicing/issues) 中搜索是否已有相同问题
2. 如果没有，创建新 Issue，包含：
   - 问题描述
   - 复现步骤
   - 期望行为
   - 实际行为
   - 环境信息（Windows 版本、Python 版本等）

### 提交功能建议

1. 创建新 Issue，标记为 `enhancement`
2. 描述功能需求和使用场景

### 提交代码

1. Fork 本仓库
2. 创建功能分支：`git checkout -b feature/your-feature`
3. 提交更改：优先使用 Conventional Commits，例如 `fix(android): stabilize recovery flow`
4. 推送分支：`git push origin feature/your-feature`
5. 创建 Pull Request

## 代码规范

- Python 代码遵循 PEP 8
- Dart / Flutter 代码保持现有主题 token 与控制器拆分结构
- 使用有意义的变量名和函数名
- 添加必要的注释（中英双语优先）
- 保持代码简洁
- 涉及用户可见行为的改动，需要同步更新 `CHANGELOG.md`、`README.md` 和相关子目录文档

## 开发环境

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

## 测试

在提交 PR 前，请确保：
1. Android 端通过：
   - `flutter test`
   - `flutter analyze --no-fatal-infos --no-fatal-warnings`
2. PC 端通过：
   - `python -m unittest discover -s tests`
   - `python -m py_compile voice_coding.py network_recovery.py voicing_protocol.py`
3. 程序能正常启动，手机端能正常连接，文本能正常发送到电脑

## 发布

- 正式发布通过 GitHub Actions 触发：
  - `git push origin main`
  - `git tag vX.Y.Z`
  - `git push origin vX.Y.Z`
- Android release 构建在 CI 中固定使用 Java 17

---

再次感谢您的贡献！
