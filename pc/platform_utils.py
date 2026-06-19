import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


APP_NAME = "Voicing"

WINDOWS_HOTSPOT_PREFIXES = ("192.168.137.",)
MACOS_HOTSPOT_PREFIXES = ("192.168.2.",)
LINUX_HOTSPOT_PREFIXES = ("10.42.0.",)


def get_platform() -> str:
    if sys.platform.startswith("win"):
        return "windows"
    if sys.platform == "darwin":
        return "darwin"
    if sys.platform.startswith("linux"):
        return "linux"
    raise RuntimeError(f"Unsupported platform: {sys.platform}")


def get_log_dir() -> Path:
    platform_name = get_platform()
    if platform_name == "windows":
        return Path(os.environ.get("APPDATA", Path.home())) / APP_NAME / "logs"
    if platform_name == "darwin":
        return Path.home() / "Library" / "Logs" / APP_NAME
    return Path.home() / ".local" / "share" / APP_NAME / "logs"


def get_data_dir() -> Path:
    platform_name = get_platform()
    if platform_name == "windows":
        return Path(os.environ.get("APPDATA", Path.home())) / APP_NAME
    if platform_name == "darwin":
        return Path.home() / "Library" / "Application Support" / APP_NAME
    return Path.home() / ".local" / "share" / APP_NAME


def open_file_in_default_app(path: Path) -> None:
    target = str(path)
    platform_name = get_platform()
    if platform_name == "windows":
        os.startfile(target)
        return
    if platform_name == "darwin":
        subprocess.Popen(["open", target])
        return
    subprocess.Popen(["xdg-open", target])


def open_file_in_text_editor(path: Path) -> None:
    target = str(path)
    platform_name = get_platform()
    if platform_name == "windows":
        subprocess.Popen(["notepad.exe", target])
        return
    if platform_name == "darwin":
        subprocess.Popen(["open", "-t", target])
        return
    subprocess.Popen(["xdg-open", target])


def get_native_font_family() -> str:
    platform_name = get_platform()
    if platform_name == "windows":
        return "'Segoe UI', 'Microsoft YaHei UI', sans-serif"
    if platform_name == "darwin":
        return "'-apple-system', 'SF Pro Text', 'PingFang SC', sans-serif"
    return "'Ubuntu', 'Cantarell', 'Noto Sans CJK SC', sans-serif"


def get_default_server_ip() -> str:
    platform_name = get_platform()
    if platform_name == "windows":
        return "192.168.137.1"
    if platform_name == "darwin":
        return "192.168.2.1"
    return "10.42.0.1"


def get_default_hotspot_ip() -> str:
    """Backward-compatible alias for the preferred local discovery address."""
    return get_default_server_ip()


def get_preferred_hotspot_prefixes() -> tuple[str, ...]:
    platform_name = get_platform()
    if platform_name == "windows":
        return WINDOWS_HOTSPOT_PREFIXES
    if platform_name == "darwin":
        return MACOS_HOTSPOT_PREFIXES
    return LINUX_HOTSPOT_PREFIXES


def get_known_hotspot_prefixes() -> tuple[str, ...]:
    return WINDOWS_HOTSPOT_PREFIXES + MACOS_HOTSPOT_PREFIXES + LINUX_HOTSPOT_PREFIXES


def is_wayland_session() -> bool:
    if get_platform() != "linux":
        return False
    session_type = os.environ.get("XDG_SESSION_TYPE", "").strip().lower()
    return session_type == "wayland" or bool(os.environ.get("WAYLAND_DISPLAY"))


def has_remote_desktop_keyboard_portal() -> bool:
    if get_platform() != "linux":
        return False
    try:
        return _get_remote_desktop_available_device_types() & 1 != 0
    except Exception:
        return False


def _get_remote_desktop_available_device_types() -> int:
    gdbus = shutil.which("gdbus")
    if gdbus:
        return _get_remote_desktop_available_device_types_with_gdbus(gdbus)
    return _get_remote_desktop_available_device_types_with_qtdbus()


def _get_remote_desktop_available_device_types_with_gdbus(gdbus: str) -> int:
    env = system_subprocess_env()
    result = subprocess.run(
        [
            gdbus,
            "call",
            "--session",
            "--dest",
            "org.freedesktop.portal.Desktop",
            "--object-path",
            "/org/freedesktop/portal/desktop",
            "--method",
            "org.freedesktop.DBus.Properties.Get",
            "org.freedesktop.portal.RemoteDesktop",
            "AvailableDeviceTypes",
        ],
        capture_output=True,
        check=True,
        env=env,
        text=True,
        timeout=3,
    )
    match = re.search(r"\b(\d+)\b", result.stdout)
    if not match:
        return 0
    return int(match.group(1))


def system_subprocess_env() -> dict[str, str]:
    """Return an environment suitable for launching host system tools.

    PyInstaller sets LD_LIBRARY_PATH to its extraction directory so the frozen
    app loads bundled libraries. That path can break external system tools such
    as gdbus by forcing them to load Voicing's bundled GLib stack instead of
    the distro-matched system libraries.
    """
    env = os.environ.copy()
    original_library_path = env.get("LD_LIBRARY_PATH_ORIG")
    if original_library_path is not None:
        env["LD_LIBRARY_PATH"] = original_library_path
    elif getattr(sys, "frozen", False):
        env.pop("LD_LIBRARY_PATH", None)
    return env


def _get_remote_desktop_available_device_types_with_qtdbus() -> int:
    from PyQt5.QtCore import QCoreApplication
    from PyQt5.QtDBus import QDBusConnection, QDBusInterface

    _app = QCoreApplication.instance() or QCoreApplication([])
    bus = QDBusConnection.sessionBus()
    if not bus.isConnected():
        return 0
    iface = QDBusInterface(
        "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.DBus.Properties",
        bus,
    )
    reply = iface.call("Get", "org.freedesktop.portal.RemoteDesktop", "AvailableDeviceTypes")
    if reply.errorMessage() or not reply.arguments():
        return 0
    return int(reply.arguments()[0])


def ensure_runtime_supported() -> None:
    if is_wayland_session() and not has_remote_desktop_keyboard_portal():
        raise RuntimeError(
            "当前检测到 Wayland 会话，但没有可用的 RemoteDesktop portal 键盘能力。"
            "请确认 xdg-desktop-portal 与 GNOME portal 正在运行，或切换到 Ubuntu on Xorg 后再启动。"
        )
