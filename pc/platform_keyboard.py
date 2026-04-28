from __future__ import annotations

import ctypes

from platform_utils import ensure_runtime_supported, get_platform


_PYAUTOGUI = None


def _get_pyautogui():
    global _PYAUTOGUI
    if _PYAUTOGUI is None:
        import pyautogui

        pyautogui.FAILSAFE = False
        pyautogui.PAUSE = 0.01
        _PYAUTOGUI = pyautogui
    return _PYAUTOGUI


def get_paste_hotkey() -> tuple[str, ...]:
    platform = get_platform()
    if platform == "darwin":
        return ("command", "v")
    if platform == "linux":
        return ("ctrl", "shift", "v")
    return ("ctrl", "v")


def press_enter() -> None:
    ensure_runtime_supported()
    if get_platform() == "windows":
        try:
            _press_enter_windows()
            return
        except Exception:
            pass

    _get_pyautogui().press("enter")


def paste_from_clipboard() -> None:
    ensure_runtime_supported()
    _get_pyautogui().hotkey(*get_paste_hotkey(), interval=0.02)


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
