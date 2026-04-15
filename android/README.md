# Voicing Android App

Android 端应用，通过手机语音输入将文字实时发送到电脑。

## 功能

- 语音输入完成后自动发送到电脑（始终启用）
- 按回车手动发送
- "自动 Enter"开关：语音分段输入静默后统一按一次回车（默认关闭，状态持久化）
- "撤回上次输入"恢复刚才的文本
- "刷新连接"手动重连
- UDP 自动发现 PC，零配置连接
- 息屏/亮屏后快速重连，并优先保持"已连接"状态显示
- 连接状态实时显示（已连接/连接中.../未连接）
- 深色主题 UI（Material Design 3）
- 协议契约测试覆盖

## 安装

从 [GitHub Releases](https://github.com/kevinlasnh/Voicing/releases/latest) 下载 `voicing.apk`，安装到手机。

或自行编译：

```bash
cd android/voice_coding
flutter pub get
flutter build apk --release
```

## 使用

1. 电脑运行 `voicing.exe`，开启 Windows 移动热点
2. 手机连热点，打开 Voicing
3. 状态栏显示"已连接"即可使用
4. 切换到语音输入法，说话，文字自动出现在电脑光标处
5. 点击"更多功能操作"可开启"自动 Enter"（适合聊天场景，语音分段输入只会补一次 Enter）

## 构建说明

- GitHub Actions 发布环境使用 Java 17，可正常产出 `voicing.apk`
- 本地如果默认 Java 指向 25，`flutter build apk --release` 会失败；请在 `android/local.properties` 中通过 `org.gradle.java.home` 指向兼容的 JDK 17/21

## 技术栈

- Flutter 3.27.0 (CI)
- Dart SDK: `^3.5.4`
- web_socket_channel: `^2.4.5`
- shared_preferences: `^2.3.3`
- Material Design 3
