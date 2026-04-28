import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import platform_keyboard


class PlatformKeyboardTests(unittest.TestCase):
    def test_get_paste_hotkey_macos_uses_command(self):
        with patch("platform_keyboard.get_platform", return_value="darwin"):
            self.assertEqual(platform_keyboard.get_paste_hotkey(), ("command", "v"))

    def test_get_paste_hotkey_linux_uses_terminal_paste(self):
        with patch("platform_keyboard.get_platform", return_value="linux"):
            self.assertEqual(platform_keyboard.get_paste_hotkey(), ("ctrl", "shift", "v"))

    def test_get_paste_hotkey_windows_uses_ctrl(self):
        with patch("platform_keyboard.get_platform", return_value="windows"):
            self.assertEqual(platform_keyboard.get_paste_hotkey(), ("ctrl", "v"))

    def test_paste_from_clipboard_uses_pyautogui_hotkey(self):
        backend = MagicMock()
        with patch("platform_keyboard.ensure_runtime_supported"):
            with patch("platform_keyboard._get_pyautogui", return_value=backend):
                with patch("platform_keyboard.get_paste_hotkey", return_value=("ctrl", "v")):
                    platform_keyboard.paste_from_clipboard()
        backend.hotkey.assert_called_once_with("ctrl", "v", interval=0.02)

    def test_press_enter_windows_prefers_sendinput(self):
        with patch("platform_keyboard.ensure_runtime_supported"):
            with patch("platform_keyboard.get_platform", return_value="windows"):
                with patch("platform_keyboard._press_enter_windows") as mock_windows:
                    platform_keyboard.press_enter()
        mock_windows.assert_called_once()

    def test_press_enter_windows_falls_back_to_pyautogui(self):
        backend = MagicMock()
        with patch("platform_keyboard.ensure_runtime_supported"):
            with patch("platform_keyboard.get_platform", return_value="windows"):
                with patch("platform_keyboard._press_enter_windows", side_effect=RuntimeError("boom")):
                    with patch("platform_keyboard._get_pyautogui", return_value=backend):
                        platform_keyboard.press_enter()
        backend.press.assert_called_once_with("enter")


if __name__ == "__main__":
    unittest.main()
