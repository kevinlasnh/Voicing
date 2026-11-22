<div align="center">

<img src="android/voice_coding/assets/icons/icon_1024.png" width="120" alt="Voicing" style="border-radius: 50%;">

# Voicing

**Pipe your phone's voice-to-text straight into your desktop AI agent**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/kevinlasnh/Voicing)](https://github.com/kevinlasnh/Voicing/releases/latest)
[![Platform](https://img.shields.io/badge/platform-Windows%20%7C%20macOS%20%7C%20Linux%20%7C%20Android-blueviolet)](#)
[![Version](https://img.shields.io/badge/version-2.10.4-green)](#)

**English** | [简体中文](README.zh-CN.md)

Tired of typing while talking to AI? Voicing lets your mouth replace your hands.

</div>

---

> **Note**: macOS and Linux desktop builds are still in beta. Stability is not yet guaranteed. Official CI/Release artifacts cover Windows, Linux and Android only; the macOS app must be built from source (see Build & release).

## What it does

Voicing turns your phone's voice keyboard into your computer's "mouth" — speak on your phone, and the text lands directly at the cursor on your computer.

- **QR pairing** — scan the desktop's QR code once and the device is remembered; every new PC is added to the paired-device list instead of replacing the previous one
- **Multiple PCs at once** — pair several desktops on the same WiFi and keep them connected simultaneously; each paired PC has its own WebSocket, heartbeat, reconnect backoff and candidate race
- **Device selection** — choose the send target under More → Device selection; the left-side submenu mirrors the header layout (same width/gap/style) and lists every paired PC with a status light, keeps the current target on the same persistent highlight used by the menu plus a green check at the trailing position used by Auto Enter, slowly scrolls long names like a music-player title, and un-pairs a device by long-pressing its row and confirming
- **Cross-network instant re-pairing** — the phone remembers which network each saved address worked on (schema v2 address book), ranks the best match for the current network, and races the top candidates in parallel (Happy Eyeballs). Once a PC has been paired once in each of several networks, coming back to any of them reconnects in about 1–2 s without re-scanning
- **No broadcast required** — after launch, the phone tries the saved IP pool directly; no UDP discovery
- **PC runtime network refresh** — when the desktop switches to a new LAN, the QR code and WebSocket listener refresh on the fly with no app restart
- **Bound-IP QR safety** — once the listener is up, QR codes advertise only the IPs the desktop actually bound successfully
- **Physical NIC priority with a Tailscale fallback** — both ends prefer real WiFi/LAN, and the desktop additionally advertises its Tailscale address in the QR payload. The phone reaches that address through the VPN tunnel, so connecting keeps working even when Android blocks sockets from bypassing the VPN
- **Auto-send on speech end** — finished sentences are sent automatically; no manual confirm
- **Auto Enter (optional)** — submit to the agent as soon as you stop speaking
- **Manual Enter still works** — press Enter to submit, useful when you want to edit first
- **Undo** — accidentally sent something? One tap to take it back
- **Auto reconnect** — wakes from screen-off and prefers showing "connected" while reconnecting
- **Stable Linux paste** — GNOME Wayland always sends a plain Ctrl+V, with no terminal focus probing, so pasting no longer depends on accessibility bus state
- **Cross-platform** — a Windows / macOS / Linux desktop codebase plus an Android phone client; official builds cover Windows, Linux and Android, while the macOS app is built from source
- **Compact** — ~32 MB APK and ~50–60 MB desktop bundles; the Linux DEB installs its declared desktop-integration dependencies

## Quick start

### 1. Download

Grab the right file from [Releases](https://github.com/kevinlasnh/Voicing/releases/latest):

| Platform | File | Requirements |
|------|------|------|
| Windows | `voicing-windows-x64.exe` | Win 10/11 (64-bit) |
| Linux | `voicing-linux-amd64.deb` or `voicing-linux-x86_64` | Ubuntu 22.04+ GNOME X11, or GNOME Wayland with RemoteDesktop portal |
| Android | `voicing.apk` | Android 5.0+ |

Each release also ships `SHA256SUMS.txt` so you can verify the SHA-256 digest before installing. A tag release publishes the four build artifacts listed above (APK, Windows EXE, Linux DEB and Linux standalone binary) plus `SHA256SUMS.txt`.

> **macOS**: no official DMG is published anymore (the macOS CI job was removed). The desktop code is still maintained — build the `.app` from source with the command in [Build & release](#build--release) and run it locally.

### 2. Connect

```
Run the desktop app → start a hotspot / Internet sharing / join the same LAN → desktop shows the QR code → scan with the phone
```

- **Windows**: run `voicing-windows-x64.exe` and turn on "Mobile hotspot"
- **macOS**: build the `.app` from source (see Build & release), then enable "Internet Sharing" or join the same LAN
- **Linux**: install `voicing-linux-amd64.deb`, or run the standalone binary with `chmod +x voicing-linux-x86_64`; start a Wi-Fi hotspot or join the same LAN. GNOME Wayland may ask you to approve a RemoteDesktop keyboard session when Voicing starts or when text is pasted.

When the status bar shows `Connected` you're good to go. The device that currently receives your text is the highlighted row under More → Device selection.

After a successful scan the phone remembers this PC and its candidate IP pool, including which network each address worked on. Each newly scanned PC is appended to the paired-device list instead of replacing the previous one, and all paired PCs attempt their connection in parallel, so several computers can be online at the same time; use More → Device selection to choose which one receives text. If you pair the same PC once on two different networks (home Wi-Fi and office Wi-Fi, or a phone hotspot), returning to either network reconnects automatically in about 1–2 s — no re-scan. Saved candidates are raced in parallel instead of tried one by one, and the ranking adapts to the current network (same network first, then the same local subnet, then the Tailscale fallback). When the desktop switches to a new LAN, the QR code and WebSocket listener refresh in place; re-scanning merges the new IP into the pool without dropping old networks. Upgrading from 2.9.14 keeps every saved candidate pool and migrates the single saved PC into the multi-device list automatically (storage schema v3), so no re-scan is needed.

### 3. Use it

1. On the computer, click the cursor where you want text to appear
2. On the phone, switch to a voice keyboard and start talking
3. The text appears on the computer

On Linux/GNOME Wayland the desktop app always sends a plain Ctrl+V: terminals and normal windows are no longer distinguished, and no terminal-side configuration is needed. Note that terminal emulators do not treat Ctrl+V as paste by default (GNOME Terminal and Ghostty use Ctrl+Shift+V), so the desktop app now targets regular input surfaces such as browsers, editors, and chat windows; use the terminal's own shortcut to paste inside a terminal.

> **Recommended setup**: [Doubao Input](https://shurufa.doubao.com/) + [DJI Mic Mini](https://www.dji.com/mic-mini) + [DJI Mic Mobile Receiver](https://store.dji.com/product/dji-mic-series-mobile-receiver) — accurate ASR, lavalier mic plugged straight into the phone, best overall experience.

## Features

### Phone

- Auto-send to the computer once a voice utterance is finished
- Press Enter to send manually
- "Auto Enter" toggle: with chunked voice input, only one Enter is fired after silence (off by default)
- "Undo last input" restores the previously sent text
- "Refresh connection" forces a manual reconnect
- "Scan to connect" (More menu) adds the scanned PC to the paired-device list; re-scanning the same PC only merges its address history
- "Device selection" (More menu, below "Scan to connect") opens a left-side submenu listing every paired PC with its status light; the current target stays highlighted with the same effect as tapping a menu row and shows the same trailing green check as Auto Enter (the slot is reserved on every row, so text width does not shift); the menus stay open after selection (only tapping outside closes them); long names slowly scroll back and forth. Text, shadow deltas and Auto Enter are sent only to that PC. Long-press a row to un-pair that PC after a confirmation dialog

### Desktop

Tray icon menu (right-click on Windows; left-click on macOS; left-click or right-click on Linux):

| Item | Function |
|--------|------|
| Show QR code | Display the current pairing QR for this PC |
| Sync input | Toggle whether phone text is accepted |
| Auto-start | Register at login via the OS mechanism: Windows Run key, macOS LaunchAgent, Linux GNOME autostart `.desktop` |
| Open log | Open today's log in the default text editor |
| Quit | Exit the app |

Tray icon states:
- Blinking = waiting for the phone to connect
- Solid = connected
- Greyed = sync disabled

## How it works

1. The desktop displays a pairing QR with `device_id/ip/ips/port/name/os`, refreshing the physical IPv4 address pool at runtime and preferring the WebSocket listener's actually bound IPs
2. The phone scans the QR and runs a WebSocket (port 9527) connectivity probe; on success it adds this PC to the paired-device list (a re-scanned `device_id` is merged, not duplicated)
3. The phone persists multiple candidate IPs for every paired PC — hotspot and various LAN addresses are all kept — and records the phone network each address succeeded on. Paired devices and the active send target are stored as schema v3 (`saved_servers` list plus `active_device_key`); old single-device data migrates automatically, and a single-device record is still written for downgrade compatibility. Re-scanning the same `device_id` merges both the candidate pool and the per-network history rather than overwriting it
4. All paired PCs connect concurrently, each with its own heartbeat, reconnect backoff and candidate race, so several computers on the same WiFi can be online at the same time
5. On later launches or manual refresh, the phone ranks the saved addresses for the current network and races the best candidates in parallel (120 ms stagger, first handshake wins); UDP discovery is no longer used
6. The PC WebSocket server rebinds to the current LAN IP whenever the address pool changes, so it never lingers on stale addresses
7. QR payloads avoid advertising addresses that failed to bind; macOS interface names are handled conservatively instead of assuming `en0` is WiFi
8. The desktop lists LAN addresses first and appends its Tailscale address (read from the `tailscale` CLI) as a fallback candidate, binding and advertising both. The Android WebSocket ranks WiFi candidates for LAN targets (plain physical WiFi, then WiFi whose VPN capability is affected, then a VPN network that inherited the WiFi transport), while a target inside the Tailscale CGNAT range is reached through the system default network, i.e. the VPN tunnel
9. Phone text (voice or typed) streams to the desktop in real time; with several paired PCs it is sent only to the one selected under More → Device selection (shadow deltas and Auto Enter follow the same target), and a late ACK from another device cannot clear the input
10. The desktop pastes via the clipboard and emits an Enter when needed; Linux X11 uses the normal Ctrl+V path, while GNOME Wayland uses the RemoteDesktop portal keyboard permission
11. GNOME Wayland always sends a plain Ctrl+V: terminal focus is no longer probed and there is no paste mode switch, so paste behavior is fully deterministic

## Development

### Setup

```bash
git clone https://github.com/kevinlasnh/Voicing.git
cd Voicing

# Desktop (Windows / macOS / Linux)
cd pc
pip install -r requirements.txt
python voice_coding.py --dev

# Android
cd android/voice_coding
flutter pub get
flutter run
```

### Project layout

```
Voicing/
├── pc/                          # Desktop (Python + PyQt5)
│   ├── voice_coding.py          # Entry, tuning and compatibility façade
│   ├── network_interfaces.py    # NIC discovery/filtering, address snapshot cache
│   ├── voicing_server.py        # WebSocket server, client registry, sync broadcast
│   ├── tray_ui.py               # Tray icon and menus (native QMenu on Linux)
│   ├── qr_dialog.py             # QR dialog and scan-success overlay
│   ├── voicing_tuning.py        # All tunables, VOICING_* env overrides
│   ├── voicing_state.py         # Shared runtime state and Qt signal bridge
│   ├── device_identity.py       # PC device_id / name / os persistence
│   ├── platform_utils.py        # Platform detection and shared utilities
│   ├── platform_keyboard.py     # Keyboard simulation abstraction
│   ├── platform_autostart.py    # Auto-start abstraction
│   ├── platform_instance.py     # Single-instance detection
│   ├── voicing_protocol.py      # Protocol constants
│   ├── network_recovery.py      # Network recovery helpers
│   └── requirements.txt         # Python dependencies
├── android/voice_coding/        # Android (Flutter)
│   ├── lib/
│   │   ├── main.dart            # UI layer, More menu and device-selection submenu
│   │   ├── voicing_connection_controller.dart  # Connection state machine
│   │   ├── voicing_protocol.dart               # Protocol constants
│   │   ├── saved_server.dart    # Paired-PC persistence (schema v3 device list, v2 address book)
│   │   ├── server_address_book.dart # Per-network address history and ranking
│   │   ├── network_profile.dart # Phone network fingerprint (interfaces/subnets)
│   │   ├── connection_race.dart # Happy Eyeballs parallel dialing
│   │   ├── connection_tuning.dart # Connection tuning constants
│   │   ├── voicing_websocket.dart # Android WiFi-bound WebSocket / Dart fallback
│   │   ├── app_theme.dart       # Theme and design tokens
│   │   └── app_logger.dart      # Logging wrapper
│   └── pubspec.yaml             # Flutter dependencies
├── protocol/                    # Shared protocol contract
│   └── voicing_protocol_contract.json
├── .github/workflows/
│   └── release.yml              # Automated build & release
├── CHANGELOG.md
├── CONTRIBUTING.md
└── LICENSE
```

### Build & release

Production releases run through GitHub Actions and build three platforms (Android / Windows / Linux); the macOS job was removed, so official releases no longer produce a macOS DMG. A tag release publishes the four build artifacts (`voicing.apk`, `voicing-windows-x64.exe`, `voicing-linux-amd64.deb`, `voicing-linux-x86_64`) plus `SHA256SUMS.txt`:

```bash
git tag v2.10.4
git push origin v2.10.4
```

Manual builds use the `workflow_dispatch` trigger from the Actions page (Build And Release → Run workflow) or:

```bash
gh workflow run release.yml --ref main
```

A manual run publishes a fresh GitHub Release automatically: it derives the version from the repository version files (`pubspec.yaml` / `APP_VERSION`, never from a branch name), creates tag `vX.Y.Z` at the built commit, and uploads the APK, Linux DEB, Linux standalone binary and `SHA256SUMS.txt` to that Release. Workflow artifacts (`android-apk`, `linux-deb`, `linux-bin`) are still kept on the run page. Manual releases do not build a Windows EXE; tag-push releases keep it.

Local debug builds:

```bash
# Windows
cd pc && pyinstaller --onefile --windowed --name=Voicing \
  --icon=assets/icon.ico --add-data "assets;assets" voice_coding.py

# macOS (.app bundle — source build only; no longer produced by official CI/Release)
cd pc && pyinstaller --windowed --name=Voicing \
  --icon=assets/icon.icns --add-data "assets:assets" voice_coding.py

# Linux
cd pc && pyinstaller --onefile --name=Voicing \
  --add-data "assets:assets" voice_coding.py

# Android
cd android/voice_coding && flutter build apk --release
```

Note: a local Android release build needs a compatible JDK 17/21 and a valid signing config. The GitHub Actions release pipeline pins Java 17 and enforces release-signing secrets. Android Gradle resolves dependencies through the official `google()` / `mavenCentral()` first, with the Aliyun mirror as a fallback only.

## FAQ

**Phone can't connect to the PC?**
1. Check that both are on the same WiFi hotspot or LAN
2. Make sure the PC firewall allows TCP 9527
3. First-time setup or a new PC: run "Show QR code" on the desktop and "Scan to connect" on the phone (each successful scan adds a PC to the paired list instead of replacing the previous one)
4. After the screen wakes up the phone enters fast-reconnect mode automatically — usually no manual refresh is needed
5. Right after switching to a new LAN, the desktop refreshes the QR and listener automatically; if it still fails, tap "Refresh connection" on the phone or re-scan the desktop QR to merge the new IP into the candidate pool
6. If the PC is on macOS, make sure Voicing has been restarted after updating to v2.9.4 or later so QR codes no longer prefer a misclassified `en0/en1` interface

**Several PCs share the same WiFi — how do I choose which one receives text?**
Pair each PC once by scanning its QR code; every scan is added to the paired-device list and the previous PC is not replaced, and the PC you just scanned becomes the current target. All paired PCs keep their own connection. Open More → Device selection (the last entry, below "Scan to connect"), which opens a left-side submenu with every paired PC and its live status; the current target stays highlighted (same effect as tapping a menu row) and long names slowly scroll back and forth. Text, shadow deltas and Auto Enter are then sent only to the selected PC; the header keeps showing only the connection state.

**Local Flutter APK build fails with a Java / Gradle error?**
If your default Java is 25, `flutter build apk --release` will fail. Install JDK 17/21 and set `org.gradle.java.home=...` in `android/voice_coding/android/local.properties`. Production releases use the Java 17 environment in GitHub Actions.

**Text landed in the wrong place?**
Make sure the cursor is in the right input field before you start speaking.

**Why does pasting not work inside a terminal on Linux?**
That is expected. Voicing now always sends a plain Ctrl+V, and terminal emulators do not treat Ctrl+V as paste by default. Use the terminal's own shortcut (for example Ctrl+Shift+V in GNOME Terminal or Ghostty) to paste inside a terminal.

**Does Auto-start work on Linux?**
On Ubuntu GNOME, yes. Voicing writes `~/.config/autostart/voicing.desktop` and GNOME launches it after login. On GNOME Wayland, the app can auto-start, but the RemoteDesktop keyboard permission is still controlled by GNOME; approve the prompt after login or app start if it appears.

**Where are the logs?**
Open the tray icon menu → "Open log".
- Windows: `%APPDATA%\Voicing\logs\`
- macOS: `~/Library/Logs/Voicing/`
- Linux: `~/.local/share/Voicing/logs/`

## Contributing

Issues and Pull Requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT License](LICENSE)
