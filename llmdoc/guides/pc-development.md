# PC 端开发指南

## 1. Identity

- **What it is:** PC 端开发环境和操作指南。
- **Purpose:** 帮助开发者快速设置环境、进行开发和调试。

## 2. 开发环境设置

1. **安装 Python 依赖:**
   ```bash
   cd pc
   pip install -r requirements.txt
   ```

2. **准备图标资源:**
   - 确保 `pc/assets/icon_1024.png` 存在。

3. **开发模式运行:**
   - 使用 `--dev` 参数跳过单实例检查，方便快速迭代：
     ```bash
     python pc/voice_coding.py --dev
     ```

## 3. 热重启流程

**重要:** PC 端是长期运行的 Python 进程，代码修改后必须手动重启。

1. **修改代码后，执行热重启命令:**
   ```powershell
   powershell -ExecutionPolicy Bypass -File ".claude/skills/pc-hot-restart/restart_pc_dev.ps1"
   ```

2. **热重启脚本功能:**
   - 查找并终止现有 `voice_coding.py` 进程
   - 重新启动 PC 端应用
   - 支持开发模式（`--dev` 参数）

## 4. 打包命令

1. **使用 PyInstaller 打包:**
   ```bash
   cd pc
   pyinstaller --onefile --windowed --name=VoiceCoding voice_coding.py
   ```

2. **打包产物位置:**
   - 可执行文件: `pc/dist/VoiceCoding.exe`

3. **注意事项:**
   - 确保打包时 `assets/icon_1024.png` 被包含
   - 打包后图标路径自动切换到 `sys._MEIPASS`

## 5. 关键代码位置索引

| 功能 | 位置 |
|------|------|
| 主入口 | `pc/voice_coding.py:1087-1108` |
| 全局状态 | `pc/voice_coding.py:96-109` |
| 日志系统 | `pc/voice_coding.py:115-139` |
| WebSocket 服务器 | `pc/voice_coding.py:345-451` |
| UDP 广播 | `pc/voice_coding.py:210-252` |
| 文本输入 | `pc/voice_coding.py:301-335` |
| MenuItemWidget | `pc/voice_coding.py:457-563` |
| ModernMenuWidget | `pc/voice_coding.py:565-740` |
| ModernTrayIcon | `pc/voice_coding.py:742-851` |
| 开机启动管理 | `pc/voice_coding.py:261-296` |
| 图标处理 | `pc/voice_coding.py:857-943` |

## 6. 调试技巧

1. **查看日志:**
   - 日志位置: `%APPDATA%\Voicing\logs\voice_coding_YYYYMMDD.log`
   - 通过托盘菜单 "打开日志" 快速访问

2. **验证网络连接:**
   - WebSocket 端口: 9527
   - UDP 广播端口: 9530
   - 使用 Wireshark 或类似工具抓包验证

3. **单实例检查:**
   - 生产模式自动启用单实例检查
   - 开发模式使用 `--dev` 参数跳过
