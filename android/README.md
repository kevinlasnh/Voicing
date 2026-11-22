# Voicing Android App

[English](README.md) | [简体中文](README.zh-CN.md)

The Android client. Streams text from the phone's voice keyboard to the desktop in real time.

## Features

- Auto-send to the computer after voice input finishes (always on)
- Press Enter to send manually
- "Auto Enter" toggle: with chunked voice input, fires Enter only once after a silence window (off by default, persisted across launches)
- "Undo last input" restores the previously sent text
- "Refresh connection" forces a manual reconnect
- "Scan to connect" under the More menu — pairs with the PC by scanning its QR code; each new PC is appended to the paired-device list instead of replacing the previous one, and re-scanning the same `device_id` only merges its address history
- Multiple paired PCs stay connected at the same time: each device has its own WebSocket, heartbeat, reconnect backoff and Happy Eyeballs candidate race, so several PCs on the same WiFi can be online concurrently
- "Device selection" — the last entry of the More menu (below "Scan to connect"). Tapping it opens a secondary menu to the left in the same style as the dropdown, listing every paired device with live status (connected / connecting / disconnected, with sync off shown as a warning) and a check mark on the current target; the delete button at the end of a row un-pairs that device after a confirmation dialog
- Text, shadow incremental updates and Auto Enter are sent only to the selected device; a late ACK from another device cannot clear the input box
- The header status bar shows "status · current device name" (for example `Connected · My PC`)
- Paired devices are persisted as schema v3 (`saved_servers` list plus `active_device_key`); old v1/v2 single-device `saved_server` data migrates automatically on first launch with no re-scan needed, and a single-device `saved_server` (the active device) is still written for downgrade compatibility
- Each device record remembers its `device_id`, the most recent successful IP, the full candidate-IP pool, and which phone network every address succeeded on (schema v2 address book)
- On launch, foreground resume, and manual refresh, the saved addresses of every paired PC are ranked for the current network and the best candidates are raced in parallel — returning to a previously paired network reconnects in about 1–2 s without re-scanning
- Re-scanning the same PC merges both the candidate IPs and the per-network history, so scanning on a new LAN does not drop the old LAN address
- The PC refreshes its QR and WebSocket listener at runtime, so the desktop app does not need a restart after a LAN switch
- After the desktop listener is up, QR payloads prefer the IPs that the PC actually bound successfully
- Android-native WebSocket ranks WiFi candidates for LAN targets and uses the system default network (VPN tunnel) for Tailscale CGNAT targets, so a VPN no longer blocks the connection
- Android-native IME-height listener keeps the input field tracking the keyboard as it expands/collapses
- Fast reconnect after screen-off / screen-on, prefers showing "Connected" while reconnecting
- Live connection status (Connected / Connecting… / Disconnected)
- Dark Material Design 3 theme
- The wire protocol (port 9527, message types) and the QR payload are unchanged, so the new APK stays compatible with existing desktop builds — no PC update is required
- Protocol-contract test coverage

## Install

Download `voicing.apk` from [GitHub Releases](https://github.com/kevinlasnh/Voicing/releases/latest) and install it.
You can also fetch `SHA256SUMS.txt` and verify the digest before installing.

Or build it yourself:

```bash
cd android/voice_coding
flutter pub get
flutter build apk --release
```

## Usage

1. Run the desktop app on the computer; start a hotspot or join the same LAN
2. From the desktop tray menu, click "Show QR code"
3. Connect the phone to the same network and open Voicing
4. First use or new PC: tap "More → Scan to connect" on the phone and scan the desktop's QR (every scan adds a PC to the paired list instead of replacing the previous one, and the new PC becomes the current send target)
5. The status bar shows "Connected · <device name>" for the current send target; later launches will rank the saved addresses for the current network and try the best candidates in parallel. If both ends move to a new LAN, wait for the desktop to refresh its QR, then scan once to merge the new network into the address book — after that no re-scan is needed on that network. Switching back to the old LAN keeps using its saved successful addresses. On v2.9.4+, QR payloads avoid preferring desktop addresses that failed to bind
6. To send to another paired PC: open More → Device selection (last entry, below "Scan to connect"), then pick the device in the left-side submenu. Text, shadow deltas and Auto Enter go only to the selected device
7. Switch to a voice keyboard, talk, and the text shows up at the cursor on the computer
8. On Linux/GNOME Wayland desktops the PC app always sends a plain Ctrl+V and no longer distinguishes terminals from normal windows; since terminal emulators do not treat Ctrl+V as paste, use it with regular input surfaces. If GNOME asks for RemoteDesktop keyboard permission after login or app start, approve it before sending text
9. Open "More" to enable "Auto Enter" (good for chat scenarios — only one Enter is fired per chunked voice utterance)

## Build notes

- The GitHub Actions release pipeline uses Java 17 and produces `voicing.apk` as expected
- Tag releases build Android / Windows / Linux and publish them as GitHub Release assets; a `workflow_dispatch` manual build now also publishes a fresh GitHub Release automatically (tag `v<version>` from the repository version files, APK + Linux DEB/standalone + `SHA256SUMS.txt`; no Windows EXE), while still keeping the workflow artifacts on the run page
- If your local default Java points to 25, `flutter build apk --release` will fail; set `org.gradle.java.home` in `android/local.properties` to a compatible JDK 17/21
- After changes to `MainActivity.kt`, the Manifest, or Gradle config, you must reinstall the full APK — Flutter hot restart does not refresh the native layer
- The same applies to native bridges like keyboard-height handling and the WiFi-bound WebSocket — verify with a fresh APK install
- Production releases now require `key.properties`; for local debug verification you can pass `-Pvoicing.allowDebugReleaseSigning=true` as an explicit override. Silent fallback to debug signing is no longer allowed
- Android Gradle resolves dependencies through the official `google()` / `mavenCentral()` first, with the Aliyun mirror as a fallback only — this avoids transient mirror 502s from blocking the GitHub Actions release build

## Tech stack

- Flutter 3.27.0 (CI)
- Dart SDK: `^3.5.4`
- web_socket_channel: `^2.4.5`
- shared_preferences: `^2.3.3`
- mobile_scanner: `^5.2.3`
- OkHttp: `4.12.0` (Android-native WiFi-bound WebSocket)
- Material Design 3
