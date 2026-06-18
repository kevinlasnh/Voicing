from __future__ import annotations

import ctypes
import shutil
import subprocess
import threading
import uuid
from dataclasses import dataclass
from typing import Any

from platform_utils import ensure_runtime_supported, get_platform, is_wayland_session


_PYAUTOGUI = None
_PORTAL_BACKEND = None

KEY_STATE_RELEASED = 0
KEY_STATE_PRESSED = 1

KEYSYM_RETURN = 0xFF0D
KEYSYM_CTRL_L = 0xFFE3
KEYSYM_V = 0x0076

REMOTE_DESKTOP_DEVICE_KEYBOARD = 1
PORTAL_REQUEST_TIMEOUT_MS = 60000


def _get_pyautogui():
    global _PYAUTOGUI
    if _PYAUTOGUI is None:
        import pyautogui

        pyautogui.FAILSAFE = False
        pyautogui.PAUSE = 0.01
        _PYAUTOGUI = pyautogui
    return _PYAUTOGUI


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

    clipboard.copy(text)
    paste_from_clipboard()

    if auto_enter:
        threading.Event().wait(enter_delay_sec)
        press_enter()

    threading.Event().wait(restore_delay_sec)
    try:
        clipboard.copy(old_clipboard)
    except Exception:
        pass


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
        self._send_key_sequence(
            (
                (KEYSYM_CTRL_L, KEY_STATE_PRESSED),
                (KEYSYM_V, KEY_STATE_PRESSED),
                (KEYSYM_V, KEY_STATE_RELEASED),
                (KEYSYM_CTRL_L, KEY_STATE_RELEASED),
            )
        )

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
                        "types": REMOTE_DESKTOP_DEVICE_KEYBOARD,
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
                int(state),
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
