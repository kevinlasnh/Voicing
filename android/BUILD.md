# Android Build Instructions / 安卓构建说明

## Prerequisites / 前置要求

Building Android APK requires **Linux** or **WSL (Windows Subsystem for Linux)**.

构建安卓 APK 需要 **Linux** 或 **WSL (Windows子系统Linux)**。

## Method 1: Using WSL (Windows) / 方法一：使用 WSL

### Step 1: Install WSL
```powershell
# In Windows PowerShell (Admin)
wsl --install -d Ubuntu
```

### Step 2: Setup Build Environment
```bash
# In WSL Ubuntu
sudo apt update
sudo apt install -y python3-pip python3-venv git zip unzip openjdk-17-jdk

# Install buildozer
pip3 install --user buildozer

# Install Android SDK dependencies
sudo apt install -y autoconf libtool pkg-config zlib1g-dev libncurses5-dev libncursesw5-dev libtinfo5 cmake libffi-dev libssl-dev
```

### Step 3: Build APK
```bash
# Navigate to android folder
cd /mnt/c/Zero/Doc/Cloud/GitHub/Voice-Coding/android

# Build debug APK
buildozer android debug

# APK will be in: bin/voicecoding-1.0.0-arm64-v8a-debug.apk
```

## Method 2: Using GitHub Actions (Recommended) / 方法二：使用 GitHub Actions（推荐）

Create `.github/workflows/build-android.yml` to automatically build APK on push.

---

## Quick Alternative: Use Web PWA / 快速替代方案：使用网页版

If building APK is too complex, you can use the **Web PWA version**:

如果构建 APK 太复杂，可以使用**网页版**：

1. PC runs the server (same as before)
2. On phone, open browser and go to: `http://<PC_IP>:9527/app`
3. Add to home screen for app-like experience

---

## Pre-built APK / 预构建 APK

Check the [Releases](https://github.com/yourusername/Voice-Coding/releases) page for pre-built APK.

查看 [Releases](https://github.com/yourusername/Voice-Coding/releases) 页面获取预构建的 APK。
