[app]

# App name
title = Voice Coding

# Package name
package.name = voicecoding

# Package domain
package.domain = org.voicecoding

# Source code directory
source.dir = .

# Source files to include
source.include_exts = py,png,jpg,kv,atlas,json

# Application version
version = 1.0.0

# Application requirements
requirements = python3,kivy,websocket-client

# Supported orientations
orientation = portrait

# Android permissions
android.permissions = INTERNET

# Android API level
android.api = 33
android.minapi = 21
android.ndk = 25b
android.sdk = 33

# Use SDL2 backend
android.bootstrap = sdl2

# Fullscreen mode
fullscreen = 0

# Icon (optional - can add later)
# icon.filename = %(source.dir)s/icon.png

# Presplash (optional)
# presplash.filename = %(source.dir)s/presplash.png

# Log level
log_level = 2

# Architecture to build for
android.archs = arm64-v8a, armeabi-v7a

# Allow backup
android.allow_backup = True

[buildozer]

# Buildozer log level
log_level = 2

# Display warning on Android if package is not found
warn_on_root = 1
