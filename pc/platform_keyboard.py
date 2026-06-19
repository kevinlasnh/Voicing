from __future__ import annotations

import ctypes
import json
import os
import shutil
import subprocess
import sys
import threading
import uuid
from dataclasses import dataclass
from enum import Enum
from typing import Any

from platform_utils import ensure_runtime_supported, get_platform, is_wayland_session


_PYAUTOGUI = None
_PORTAL_BACKEND = None

KEY_STATE_RELEASED = 0
KEY_STATE_PRESSED = 1

KEYSYM_RETURN = 0xFF0D
KEYSYM_CTRL_L = 0xFFE3
KEYSYM_SHIFT_L = 0xFFE1
KEYSYM_INSERT = 0xFF63
KEYSYM_V = 0x0076

REMOTE_DESKTOP_DEVICE_KEYBOARD = 1
PORTAL_REQUEST_TIMEOUT_MS = 60000
ATSPI_FOCUS_TIMEOUT_SEC = 0.35


class PasteMode(str, Enum):
    AUTO = "auto"
    NORMAL = "normal"
    TERMINAL = "terminal"
    COMPAT = "compat"


PASTE_MODE_LABELS = {
    PasteMode.AUTO: "自动粘贴",
    PasteMode.NORMAL: "普通粘贴",
    PasteMode.TERMINAL: "终端粘贴",
    PasteMode.COMPAT: "兼容粘贴",
}

TERMINAL_APP_NAMES = {
    "alacritty",
    "com.mitchellh.ghostty",
    "ghostty",
    "gnome-terminal",
    "gnome-terminal-server",
    "io.elementary.terminal",
    "kitty",
    "kgx",
    "konsole",
    "org.gnome.console",
    "org.gnome.ptyxis",
    "org.gnome.terminal",
    "org.kde.konsole",
    "org.wezfurlong.wezterm",
    "ptyxis",
    "qterminal",
    "terminator",
    "tilix",
    "wezterm",
    "xfce4-terminal",
}

_PASTE_MODE = PasteMode.AUTO


def _dbus_uint(value: int):
    """Build a D-Bus ``u`` (uint32) argument.

    PyQt5 marshals a plain Python ``int`` as signed int32 ('i'). Several XDG
    RemoteDesktop portal fields (e.g. ``SelectDevices`` ``types`` and the
    ``state`` arg of ``NotifyKeyboardKeysym``) require unsigned 'u', so we
    build a typed ``QDBusArgument`` to force the right signature. This is used
    for top-level call arguments; for values inside an ``a{sv}`` map wrap the
    result via :func:`_dbus_uint_variant`.
    """
    from PyQt5.QtCore import QMetaType
    from PyQt5.QtDBus import QDBusArgument

    arg = QDBusArgument()
    arg.add(value, QMetaType.UInt)
    return arg


def _dbus_uint_variant(value: int):
    """uint32 wrapped as a variant, for use as a value in an ``a{sv}`` map."""
    from PyQt5.QtCore import QVariant

    return QVariant(_dbus_uint(value))


def _get_pyautogui():
    global _PYAUTOGUI
    if _PYAUTOGUI is None:
        import pyautogui

        pyautogui.FAILSAFE = False
        pyautogui.PAUSE = 0.01
        _PYAUTOGUI = pyautogui
    return _PYAUTOGUI


def get_paste_mode() -> PasteMode:
    return _PASTE_MODE


def set_paste_mode(mode: PasteMode | str) -> PasteMode:
    global _PASTE_MODE
    if not isinstance(mode, PasteMode):
        mode = PasteMode(str(mode))
    _PASTE_MODE = mode
    return _PASTE_MODE


def get_paste_mode_label(mode: PasteMode | None = None) -> str:
    return PASTE_MODE_LABELS[mode or _PASTE_MODE]


def _is_linux_wayland() -> bool:
    return get_platform() == "linux" and is_wayland_session()


def get_paste_hotkey() -> tuple[str, str]:
    return ("command", "v") if get_platform() == "darwin" else ("ctrl", "v")


def press_enter() -> None:
    ensure_runtime_supported()
    if _is_linux_wayland():
        _get_remote_desktop_portal_backend().press_enter()
        return

    if get_platform() == "windows":
        try:
            _press_enter_windows()
            return
        except Exception:
            pass

    _get_pyautogui().press("enter")


def paste_from_clipboard() -> None:
    ensure_runtime_supported()
    if _is_linux_wayland():
        _get_remote_desktop_portal_backend().paste_from_clipboard()
        return

    _get_pyautogui().hotkey(*get_paste_hotkey(), interval=0.02)


def _paste_primary_selection_if_supported() -> str | None:
    if not _is_linux_wayland() or not shutil.which("wl-paste"):
        return None
    try:
        return subprocess.check_output(
            ["wl-paste", "--primary", "--no-newline"],
            text=True,
            stderr=subprocess.DEVNULL,
        )
    except Exception:
        return None


def _copy_to_primary_selection_if_supported(text: str) -> bool:
    if not _is_linux_wayland() or not shutil.which("wl-copy"):
        return False
    try:
        subprocess.run(
            ["wl-copy", "--primary"],
            input=text,
            text=True,
            check=True,
        )
        return True
    except Exception:
        return False


def type_text_at_cursor(
    text: str,
    auto_enter: bool = False,
    enter_delay_sec: float = 0.2,
    restore_delay_sec: float = 0.1,
) -> None:
    """Paste Unicode text at the current cursor and optionally press Enter."""
    ensure_runtime_supported()
    clipboard = _get_clipboard_backend()

    try:
        old_clipboard = clipboard.paste()
    except Exception:
        old_clipboard = ""
    old_primary = _paste_primary_selection_if_supported()

    clipboard.copy(text)
    copied_primary = _copy_to_primary_selection_if_supported(text)
    paste_from_clipboard()

    if auto_enter:
        threading.Event().wait(enter_delay_sec)
        press_enter()

    threading.Event().wait(restore_delay_sec)
    try:
        clipboard.copy(old_clipboard)
    except Exception:
        pass
    if copied_primary and old_primary is not None:
        _copy_to_primary_selection_if_supported(old_primary)


class _PyperclipClipboardBackend:
    def paste(self) -> str:
        import pyperclip

        return pyperclip.paste()

    def copy(self, text: str) -> None:
        import pyperclip

        pyperclip.copy(text)


class _WlClipboardBackend:
    def paste(self) -> str:
        return subprocess.check_output(["wl-paste", "--no-newline"], text=True)

    def copy(self, text: str) -> None:
        subprocess.run(["wl-copy"], input=text, text=True, check=True)


def _get_clipboard_backend():
    if _is_linux_wayland() and shutil.which("wl-copy") and shutil.which("wl-paste"):
        return _WlClipboardBackend()
    return _PyperclipClipboardBackend()


def _get_remote_desktop_portal_backend():
    global _PORTAL_BACKEND
    if _PORTAL_BACKEND is None:
        _PORTAL_BACKEND = RemoteDesktopPortalKeyboardBackend()
    return _PORTAL_BACKEND


@dataclass
class _PortalRequestResult:
    response_code: int | None = None
    results: dict[str, Any] | None = None
    timed_out: bool = False


class RemoteDesktopPortalKeyboardBackend:
    """Keyboard backend for GNOME Wayland through XDG RemoteDesktop portal."""

    def __init__(self, request_timeout_ms: int = PORTAL_REQUEST_TIMEOUT_MS):
        self._session_handle: str | None = None
        self._request_timeout_ms = request_timeout_ms
        self._lock = threading.RLock()

    def is_available(self) -> bool:
        try:
            return self._available_device_types() & REMOTE_DESKTOP_DEVICE_KEYBOARD != 0
        except Exception:
            return False

    def paste_from_clipboard(self) -> None:
        self._ensure_started()
        self._send_key_sequence(_resolve_wayland_paste_sequence())

    def press_enter(self) -> None:
        self._ensure_started()
        self._send_key_sequence(
            (
                (KEYSYM_RETURN, KEY_STATE_PRESSED),
                (KEYSYM_RETURN, KEY_STATE_RELEASED),
            )
        )

    def _ensure_started(self) -> None:
        with self._lock:
            if self._session_handle:
                return

            if not self.is_available():
                raise RuntimeError(
                    "当前 Wayland 会话没有可用的 RemoteDesktop portal 键盘能力。"
                    "请确认 xdg-desktop-portal 与 GNOME portal 正在运行。"
                )

            session_token = "voicing" + uuid.uuid4().hex
            create_results = self._call_request(
                "CreateSession",
                {
                    "session_handle_token": session_token,
                },
            )
            session_handle = create_results.get("session_handle")
            if not session_handle:
                raise RuntimeError("RemoteDesktop portal 未返回 session handle。")
            self._session_handle = str(session_handle)

            try:
                self._call_request(
                    "SelectDevices",
                    self._dbus_object_path(self._session_handle),
                    {
                        "types": _dbus_uint_variant(REMOTE_DESKTOP_DEVICE_KEYBOARD),
                    },
                )
                self._call_request(
                    "Start",
                    self._dbus_object_path(self._session_handle),
                    "",
                    {},
                )
            except Exception:
                self._session_handle = None
                raise

    def _send_key_sequence(self, sequence: tuple[tuple[int, int], ...]) -> None:
        session_handle = self._session_handle
        if not session_handle:
            raise RuntimeError("RemoteDesktop portal session 尚未启动。")

        iface = self._remote_desktop_interface()
        for keysym, state in sequence:
            reply = iface.call(
                "NotifyKeyboardKeysym",
                self._dbus_object_path(session_handle),
                {},
                int(keysym),
                _dbus_uint(int(state)),
            )
            if reply.errorMessage():
                self._session_handle = None
                raise RuntimeError(f"RemoteDesktop portal 键盘事件失败: {reply.errorMessage()}")

    def _call_request(self, method_name: str, *args):
        app, event_loop, timer, qobject, pyqt_slot, qdbus_connection, qdbus_interface = self._qt_imports()
        _ = app

        bus = qdbus_connection.sessionBus()
        if not bus.isConnected():
            raise RuntimeError("无法连接到 D-Bus session bus。")

        handle_token = "voicing" + uuid.uuid4().hex
        request_path = self._request_path(bus, handle_token)
        result = _PortalRequestResult()

        class RequestReceiver(qobject):
            @pyqt_slot("uint", "QVariantMap")
            def response(self, response_code, results):
                result.response_code = int(response_code)
                result.results = dict(results)
                loop.quit()

        receiver = RequestReceiver()
        connected = bus.connect(
            "",
            request_path,
            "org.freedesktop.portal.Request",
            "Response",
            receiver.response,
        )
        if not connected:
            raise RuntimeError("无法监听 RemoteDesktop portal 请求响应。")

        loop = event_loop()
        timeout = timer()
        timeout.setSingleShot(True)

        def on_timeout():
            result.timed_out = True
            loop.quit()

        timeout.timeout.connect(on_timeout)
        timeout.start(self._request_timeout_ms)

        call_args = list(args)
        options = dict(call_args[-1]) if call_args and isinstance(call_args[-1], dict) else {}
        options["handle_token"] = handle_token
        if call_args and isinstance(call_args[-1], dict):
            call_args[-1] = options
        else:
            call_args.append(options)

        iface = self._remote_desktop_interface()
        reply = iface.call(method_name, *call_args)
        if reply.errorMessage():
            timeout.stop()
            bus.disconnect(
                "",
                request_path,
                "org.freedesktop.portal.Request",
                "Response",
                receiver.response,
            )
            raise RuntimeError(f"RemoteDesktop portal {method_name} 调用失败: {reply.errorMessage()}")

        loop.exec()
        timeout.stop()
        bus.disconnect(
            "",
            request_path,
            "org.freedesktop.portal.Request",
            "Response",
            receiver.response,
        )

        if result.timed_out:
            raise RuntimeError(f"RemoteDesktop portal {method_name} 请求超时。")
        if result.response_code != 0:
            raise RuntimeError(f"RemoteDesktop portal {method_name} 请求被拒绝或取消。")
        return result.results or {}

    def _available_device_types(self) -> int:
        _app, _event_loop, _timer, _qobject, _pyqt_slot, qdbus_connection, qdbus_interface = self._qt_imports()
        bus = qdbus_connection.sessionBus()
        if not bus.isConnected():
            return 0
        iface = qdbus_interface(
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.DBus.Properties",
            bus,
        )
        reply = iface.call("Get", "org.freedesktop.portal.RemoteDesktop", "AvailableDeviceTypes")
        if reply.errorMessage() or not reply.arguments():
            return 0
        return int(reply.arguments()[0])

    def _remote_desktop_interface(self):
        _app, _event_loop, _timer, _qobject, _pyqt_slot, qdbus_connection, qdbus_interface = self._qt_imports()
        return qdbus_interface(
            "org.freedesktop.portal.Desktop",
            "/org/freedesktop/portal/desktop",
            "org.freedesktop.portal.RemoteDesktop",
            qdbus_connection.sessionBus(),
        )

    def _dbus_object_path(self, path: str):
        from PyQt5.QtDBus import QDBusObjectPath

        return QDBusObjectPath(path)

    def _request_path(self, bus, handle_token: str) -> str:
        unique_name = bus.baseService().replace(":", "").replace(".", "_")
        return f"/org/freedesktop/portal/desktop/request/{unique_name}/{handle_token}"

    def _qt_imports(self):
        from PyQt5.QtCore import QCoreApplication, QEventLoop, QObject, QTimer, pyqtSlot
        from PyQt5.QtDBus import QDBusConnection, QDBusInterface

        app = QCoreApplication.instance()
        if app is None:
            app = QCoreApplication([])
        return app, QEventLoop, QTimer, QObject, pyqtSlot, QDBusConnection, QDBusInterface


def _resolve_wayland_paste_sequence() -> tuple[tuple[int, int], ...]:
    mode = get_paste_mode()
    if mode == PasteMode.AUTO:
        mode = PasteMode.TERMINAL if is_current_focus_terminal() else PasteMode.NORMAL
    if mode == PasteMode.TERMINAL:
        return _ctrl_shift_v_sequence()
    if mode == PasteMode.COMPAT:
        return _shift_insert_sequence()
    return _ctrl_v_sequence()


def _ctrl_v_sequence() -> tuple[tuple[int, int], ...]:
    return (
        (KEYSYM_CTRL_L, KEY_STATE_PRESSED),
        (KEYSYM_V, KEY_STATE_PRESSED),
        (KEYSYM_V, KEY_STATE_RELEASED),
        (KEYSYM_CTRL_L, KEY_STATE_RELEASED),
    )


def _ctrl_shift_v_sequence() -> tuple[tuple[int, int], ...]:
    return (
        (KEYSYM_CTRL_L, KEY_STATE_PRESSED),
        (KEYSYM_SHIFT_L, KEY_STATE_PRESSED),
        (KEYSYM_V, KEY_STATE_PRESSED),
        (KEYSYM_V, KEY_STATE_RELEASED),
        (KEYSYM_SHIFT_L, KEY_STATE_RELEASED),
        (KEYSYM_CTRL_L, KEY_STATE_RELEASED),
    )


def _shift_insert_sequence() -> tuple[tuple[int, int], ...]:
    return (
        (KEYSYM_SHIFT_L, KEY_STATE_PRESSED),
        (KEYSYM_INSERT, KEY_STATE_PRESSED),
        (KEYSYM_INSERT, KEY_STATE_RELEASED),
        (KEYSYM_SHIFT_L, KEY_STATE_RELEASED),
    )


def is_current_focus_terminal() -> bool:
    info = _get_focused_accessible_info()
    if not info:
        return False
    role = str(info.get("role", "")).lower()
    if role == "terminal":
        return True
    app_name = _normalize_terminal_app_name(str(info.get("app_name", "")))
    return app_name in TERMINAL_APP_NAMES


def _normalize_terminal_app_name(value: str) -> str:
    normalized = value.strip().lower()
    if normalized.endswith(".desktop"):
        normalized = normalized[:-8]
    return normalized


def _get_focused_accessible_info() -> dict[str, str] | None:
    info = _get_focused_accessible_info_in_process()
    if info is not None:
        return info
    return _get_focused_accessible_info_from_system_python()


def _get_focused_accessible_info_in_process() -> dict[str, str] | None:
    try:
        import gi

        gi.require_version("Atspi", "2.0")
        from gi.repository import Atspi
    except Exception:
        return None
    try:
        return _scan_atspi_desktop(Atspi)
    except Exception:
        return None


def _get_focused_accessible_info_from_system_python() -> dict[str, str] | None:
    python = _find_system_python_with_atspi()
    if not python:
        return None
    try:
        result = subprocess.run(
            [python, "-c", _ATSPI_FOCUS_HELPER],
            text=True,
            capture_output=True,
            timeout=ATSPI_FOCUS_TIMEOUT_SEC,
            check=False,
        )
    except Exception:
        return None
    if result.returncode != 0 or not result.stdout.strip():
        return None
    try:
        data = json.loads(result.stdout)
    except Exception:
        return None
    if not isinstance(data, dict):
        return None
    return {
        "app_name": str(data.get("app_name", "")),
        "role": str(data.get("role", "")),
        "name": str(data.get("name", "")),
    }


def _find_system_python_with_atspi() -> str | None:
    current_executable = os.path.abspath(sys.executable)
    for candidate in ("/usr/bin/python3", shutil.which("python3")):
        if not candidate:
            continue
        candidate = os.path.abspath(candidate)
        if candidate == current_executable:
            continue
        if os.path.exists(candidate):
            return candidate
    return None


def _scan_atspi_desktop(Atspi) -> dict[str, str] | None:
    desktop = Atspi.get_desktop(0)
    focused = _find_focused_accessible(Atspi, desktop)
    focused_info = _accessible_info(Atspi, focused) if focused is not None else None
    if focused_info and _is_terminal_accessible_info(focused_info):
        return focused_info

    if _should_scan_active_terminal_fallback(focused_info):
        active_terminal = _find_active_terminal_accessible(Atspi, desktop)
        if active_terminal is not None:
            return _accessible_info(Atspi, active_terminal)
    return focused_info


def _is_terminal_accessible_info(info: dict[str, str]) -> bool:
    if str(info.get("role", "")).lower() == "terminal":
        return True
    app_name = _normalize_terminal_app_name(str(info.get("app_name", "")))
    return app_name in TERMINAL_APP_NAMES


def _should_scan_active_terminal_fallback(info: dict[str, str] | None) -> bool:
    if not info:
        return True
    app_name = _normalize_terminal_app_name(str(info.get("app_name", "")))
    role = str(info.get("role", "")).strip().lower()
    return app_name in {"gnome-shell", "org.gnome.shell"} or role in {
        "desktop frame",
        "desktop icon",
    }


def _find_focused_accessible(Atspi, root, max_depth: int = 7):
    stack = [(root, 0)]
    while stack:
        accessible, depth = stack.pop()
        try:
            state_set = accessible.get_state_set()
            if state_set.contains(Atspi.StateType.FOCUSED):
                return accessible
            child_count = accessible.get_child_count()
        except Exception:
            continue
        if depth >= max_depth:
            continue
        for index in range(min(child_count, 120) - 1, -1, -1):
            try:
                stack.append((accessible.get_child_at_index(index), depth + 1))
            except Exception:
                pass
    return None


def _find_active_terminal_accessible(Atspi, root, max_depth: int = 4):
    stack = [(root, 0)]
    while stack:
        accessible, depth = stack.pop()
        try:
            state_set = accessible.get_state_set()
            if state_set.contains(Atspi.StateType.ACTIVE):
                info = _accessible_info(Atspi, accessible)
                if _is_terminal_accessible_info(info):
                    return accessible
            child_count = accessible.get_child_count()
        except Exception:
            continue
        if depth >= max_depth:
            continue
        for index in range(min(child_count, 80) - 1, -1, -1):
            try:
                stack.append((accessible.get_child_at_index(index), depth + 1))
            except Exception:
                pass
    return None


def _accessible_info(Atspi, accessible) -> dict[str, str]:
    app_name = ""
    try:
        app = accessible.get_application()
        if app is not None:
            app_name = app.get_name() or ""
    except Exception:
        pass
    try:
        role = accessible.get_role_name() or ""
    except Exception:
        role = ""
    try:
        name = accessible.get_name() or ""
    except Exception:
        name = ""
    return {"app_name": app_name, "role": role, "name": name}


_ATSPI_FOCUS_HELPER = r"""
import json
import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi

def info(accessible):
    app_name = ""
    try:
        app = accessible.get_application()
        if app is not None:
            app_name = app.get_name() or ""
    except Exception:
        pass
    try:
        role = accessible.get_role_name() or ""
    except Exception:
        role = ""
    try:
        name = accessible.get_name() or ""
    except Exception:
        name = ""
    return {"app_name": app_name, "role": role, "name": name}

def find_focused(root, max_depth=7):
    stack = [(root, 0)]
    while stack:
        accessible, depth = stack.pop()
        try:
            state_set = accessible.get_state_set()
            if state_set.contains(Atspi.StateType.FOCUSED):
                return accessible
            child_count = accessible.get_child_count()
        except Exception:
            continue
        if depth >= max_depth:
            continue
        for index in range(min(child_count, 120) - 1, -1, -1):
            try:
                stack.append((accessible.get_child_at_index(index), depth + 1))
            except Exception:
                pass
    return None

def is_terminal(info):
    role = str(info.get("role", "")).lower()
    app_name = str(info.get("app_name", "")).strip().lower()
    if app_name.endswith(".desktop"):
        app_name = app_name[:-8]
    terminals = {
        "alacritty", "com.mitchellh.ghostty", "ghostty",
        "gnome-terminal", "gnome-terminal-server",
        "io.elementary.terminal", "kitty", "kgx", "konsole",
        "org.gnome.console", "org.gnome.ptyxis", "org.gnome.terminal",
        "org.kde.konsole", "org.wezfurlong.wezterm", "ptyxis",
        "qterminal", "terminator", "tilix", "wezterm", "xfce4-terminal",
    }
    return role == "terminal" or app_name in terminals

def find_active_terminal(root, max_depth=4):
    stack = [(root, 0)]
    while stack:
        accessible, depth = stack.pop()
        try:
            state_set = accessible.get_state_set()
            if state_set.contains(Atspi.StateType.ACTIVE):
                if is_terminal(info(accessible)):
                    return accessible
            child_count = accessible.get_child_count()
        except Exception:
            continue
        if depth >= max_depth:
            continue
        for index in range(min(child_count, 80) - 1, -1, -1):
            try:
                stack.append((accessible.get_child_at_index(index), depth + 1))
            except Exception:
                pass
    return None

desktop = Atspi.get_desktop(0)
focused = find_focused(desktop)
focused_info = info(focused) if focused is not None else None
if focused_info and is_terminal(focused_info):
    print(json.dumps(focused_info))
else:
    app_name = ""
    role = ""
    if focused_info:
        app_name = str(focused_info.get("app_name", "")).strip().lower()
        if app_name.endswith(".desktop"):
            app_name = app_name[:-8]
        role = str(focused_info.get("role", "")).strip().lower()
    use_active_fallback = (
        focused_info is None
        or app_name in {"gnome-shell", "org.gnome.shell"}
        or role in {"desktop frame", "desktop icon"}
    )
    if use_active_fallback:
        active_terminal = find_active_terminal(desktop)
        if active_terminal is not None:
            print(json.dumps(info(active_terminal)))
        elif focused_info:
            print(json.dumps(focused_info))
    elif focused_info:
        print(json.dumps(focused_info))
"""


def _press_enter_windows() -> None:
    input_keyboard = 1
    keyeventf_keyup = 0x0002
    vk_return = 0x0D
    ulong_ptr = ctypes.c_ulonglong if ctypes.sizeof(ctypes.c_void_p) == 8 else ctypes.c_ulong

    class KEYBDINPUT(ctypes.Structure):
        _fields_ = [
            ("wVk", ctypes.c_ushort),
            ("wScan", ctypes.c_ushort),
            ("dwFlags", ctypes.c_ulong),
            ("time", ctypes.c_ulong),
            ("dwExtraInfo", ulong_ptr),
        ]

    class _INPUTUNION(ctypes.Union):
        _fields_ = [("ki", KEYBDINPUT)]

    class INPUT(ctypes.Structure):
        _anonymous_ = ("data",)
        _fields_ = [
            ("type", ctypes.c_ulong),
            ("data", _INPUTUNION),
        ]

    def build_keyboard_input(vk_code: int, flags: int = 0) -> "INPUT":
        return INPUT(
            type=input_keyboard,
            ki=KEYBDINPUT(
                wVk=vk_code,
                wScan=0,
                dwFlags=flags,
                time=0,
                dwExtraInfo=0,
            ),
        )

    inputs = (
        build_keyboard_input(vk_return),
        build_keyboard_input(vk_return, keyeventf_keyup),
    )
    sent = ctypes.windll.user32.SendInput(
        len(inputs),
        (INPUT * len(inputs))(*inputs),
        ctypes.sizeof(INPUT),
    )
    if sent != len(inputs):
        raise ctypes.WinError(ctypes.get_last_error())
