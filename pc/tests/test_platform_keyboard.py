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

    def test_get_paste_hotkey_non_macos_uses_ctrl(self):
        with patch("platform_keyboard.get_platform", return_value="linux"):
            self.assertEqual(platform_keyboard.get_paste_hotkey(), ("ctrl", "v"))

    def test_paste_from_clipboard_uses_pyautogui_hotkey(self):
        backend = MagicMock()
        with patch("platform_keyboard.ensure_runtime_supported"):
            with patch("platform_keyboard._is_linux_wayland", return_value=False):
                with patch("platform_keyboard._get_pyautogui", return_value=backend):
                    with patch("platform_keyboard.get_paste_hotkey", return_value=("ctrl", "v")):
                        platform_keyboard.paste_from_clipboard()
        backend.hotkey.assert_called_once_with("ctrl", "v", interval=0.02)

    def test_paste_from_clipboard_wayland_uses_portal(self):
        backend = MagicMock()
        with patch("platform_keyboard.ensure_runtime_supported"):
            with patch("platform_keyboard._is_linux_wayland", return_value=True):
                with patch("platform_keyboard._get_remote_desktop_portal_backend", return_value=backend):
                    platform_keyboard.paste_from_clipboard()
        backend.paste_from_clipboard.assert_called_once()

    def test_press_enter_wayland_uses_portal(self):
        backend = MagicMock()
        with patch("platform_keyboard.ensure_runtime_supported"):
            with patch("platform_keyboard._is_linux_wayland", return_value=True):
                with patch("platform_keyboard._get_remote_desktop_portal_backend", return_value=backend):
                    platform_keyboard.press_enter()
        backend.press_enter.assert_called_once()

    def test_type_text_at_cursor_restores_clipboard_and_auto_enters(self):
        clipboard = MagicMock()
        clipboard.paste.return_value = "old"
        with patch("platform_keyboard.ensure_runtime_supported"):
            with patch("platform_keyboard._get_clipboard_backend", return_value=clipboard):
                with patch("platform_keyboard.paste_from_clipboard") as mock_paste:
                    with patch("platform_keyboard.press_enter") as mock_enter:
                        with patch("platform_keyboard.threading.Event") as event_factory:
                            event_factory.return_value.wait = MagicMock()
                            platform_keyboard.type_text_at_cursor(
                                "hello",
                                auto_enter=True,
                                enter_delay_sec=0.3,
                                restore_delay_sec=0.4,
                            )

        clipboard.paste.assert_called_once()
        self.assertEqual(clipboard.copy.call_args_list[0].args, ("hello",))
        self.assertEqual(clipboard.copy.call_args_list[1].args, ("old",))
        mock_paste.assert_called_once()
        mock_enter.assert_called_once()
        self.assertEqual(event_factory.return_value.wait.call_args_list[0].args, (0.3,))
        self.assertEqual(event_factory.return_value.wait.call_args_list[1].args, (0.4,))

    def test_type_text_at_cursor_without_auto_enter(self):
        clipboard = MagicMock()
        clipboard.paste.return_value = "old"
        with patch("platform_keyboard.ensure_runtime_supported"):
            with patch("platform_keyboard._get_clipboard_backend", return_value=clipboard):
                with patch("platform_keyboard.paste_from_clipboard"):
                    with patch("platform_keyboard.press_enter") as mock_enter:
                        with patch("platform_keyboard.threading.Event") as event_factory:
                            event_factory.return_value.wait = MagicMock()
                            platform_keyboard.type_text_at_cursor("hello", auto_enter=False)

        mock_enter.assert_not_called()
        event_factory.return_value.wait.assert_called_once_with(0.1)

    def test_remote_desktop_portal_availability_checks_keyboard_bit(self):
        backend = platform_keyboard.RemoteDesktopPortalKeyboardBackend()
        with patch.object(backend, "_available_device_types", return_value=7):
            self.assertTrue(backend.is_available())

    def test_remote_desktop_portal_availability_rejects_missing_keyboard_bit(self):
        backend = platform_keyboard.RemoteDesktopPortalKeyboardBackend()
        with patch.object(backend, "_available_device_types", return_value=2):
            self.assertFalse(backend.is_available())

    def test_remote_desktop_portal_paste_sequence(self):
        backend = platform_keyboard.RemoteDesktopPortalKeyboardBackend()
        with patch.object(backend, "_ensure_started") as mock_started:
            with patch.object(backend, "_send_key_sequence") as mock_send:
                backend.paste_from_clipboard()
        mock_started.assert_called_once()
        mock_send.assert_called_once_with(
            (
                (platform_keyboard.KEYSYM_CTRL_L, platform_keyboard.KEY_STATE_PRESSED),
                (platform_keyboard.KEYSYM_V, platform_keyboard.KEY_STATE_PRESSED),
                (platform_keyboard.KEYSYM_V, platform_keyboard.KEY_STATE_RELEASED),
                (platform_keyboard.KEYSYM_CTRL_L, platform_keyboard.KEY_STATE_RELEASED),
            )
        )

    def test_remote_desktop_portal_enter_sequence(self):
        backend = platform_keyboard.RemoteDesktopPortalKeyboardBackend()
        with patch.object(backend, "_ensure_started") as mock_started:
            with patch.object(backend, "_send_key_sequence") as mock_send:
                backend.press_enter()
        mock_started.assert_called_once()
        mock_send.assert_called_once_with(
            (
                (platform_keyboard.KEYSYM_RETURN, platform_keyboard.KEY_STATE_PRESSED),
                (platform_keyboard.KEYSYM_RETURN, platform_keyboard.KEY_STATE_RELEASED),
            )
        )

    def test_remote_desktop_portal_ensure_started_runs_portal_flow(self):
        backend = platform_keyboard.RemoteDesktopPortalKeyboardBackend()
        with patch.object(backend, "is_available", return_value=True):
            with patch.object(
                backend,
                "_call_request",
                side_effect=[
                    {"session_handle": "/org/freedesktop/portal/desktop/session/test"},
                    {},
                    {},
                ],
            ) as mock_call:
                with patch.object(backend, "_dbus_object_path", side_effect=lambda value: f"path:{value}"):
                    backend._ensure_started()

        self.assertEqual(backend._session_handle, "/org/freedesktop/portal/desktop/session/test")
        self.assertEqual(mock_call.call_args_list[0].args[0], "CreateSession")
        self.assertEqual(mock_call.call_args_list[1].args[0], "SelectDevices")
        self.assertEqual(mock_call.call_args_list[2].args[0], "Start")
        # 'types' 必须是 uint 变体（QVariant 包裹的 QDBusArgument），否则
        # portal 会以 "Expected type 'u' ... got 'i'" 拒绝 SelectDevices。
        select_options = mock_call.call_args_list[1].args[2]
        self.assertIn("types", select_options)
        from PyQt5.QtCore import QVariant
        self.assertIsInstance(select_options["types"], QVariant)

    def test_remote_desktop_portal_ensure_started_requires_keyboard_capability(self):
        backend = platform_keyboard.RemoteDesktopPortalKeyboardBackend()
        with patch.object(backend, "is_available", return_value=False):
            with self.assertRaises(RuntimeError):
                backend._ensure_started()

    def test_remote_desktop_portal_send_key_sequence_uses_notify_keysym(self):
        backend = platform_keyboard.RemoteDesktopPortalKeyboardBackend()
        backend._session_handle = "/session"
        reply = MagicMock()
        reply.errorMessage.return_value = ""
        iface = MagicMock()
        iface.call.return_value = reply

        with patch.object(backend, "_remote_desktop_interface", return_value=iface):
            with patch.object(backend, "_dbus_object_path", side_effect=lambda value: f"path:{value}"):
                backend._send_key_sequence(((1, platform_keyboard.KEY_STATE_PRESSED),))

        self.assertEqual(iface.call.call_count, 1)
        call_args = iface.call.call_args.args
        self.assertEqual(call_args[0], "NotifyKeyboardKeysym")
        self.assertEqual(call_args[1], "path:/session")
        self.assertEqual(call_args[2], {})
        # keysym 保持普通 int（本机 portal 内省期望 'i'）；state 必须是 uint
        # QDBusArgument，否则会被以 "got 'i'" 拒绝。
        self.assertEqual(call_args[3], 1)
        from PyQt5.QtDBus import QDBusArgument
        self.assertIsInstance(call_args[4], QDBusArgument)

    def test_remote_desktop_portal_send_key_sequence_resets_session_on_error(self):
        backend = platform_keyboard.RemoteDesktopPortalKeyboardBackend()
        backend._session_handle = "/session"
        reply = MagicMock()
        reply.errorMessage.return_value = "boom"
        iface = MagicMock()
        iface.call.return_value = reply

        with patch.object(backend, "_remote_desktop_interface", return_value=iface):
            with patch.object(backend, "_dbus_object_path", side_effect=lambda value: value):
                with self.assertRaises(RuntimeError):
                    backend._send_key_sequence(((1, platform_keyboard.KEY_STATE_PRESSED),))

        self.assertIsNone(backend._session_handle)

    def test_wl_clipboard_backend_uses_wl_tools(self):
        backend = platform_keyboard._WlClipboardBackend()
        with patch("platform_keyboard.subprocess.check_output", return_value="old") as mock_paste:
            self.assertEqual(backend.paste(), "old")
        mock_paste.assert_called_once_with(["wl-paste", "--no-newline"], text=True)

        with patch("platform_keyboard.subprocess.run") as mock_run:
            backend.copy("new")
        mock_run.assert_called_once_with(["wl-copy"], input="new", text=True, check=True)

    def test_get_clipboard_backend_prefers_wl_tools_on_wayland(self):
        with patch("platform_keyboard._is_linux_wayland", return_value=True):
            with patch("platform_keyboard.shutil.which", side_effect=lambda command: f"/usr/bin/{command}"):
                self.assertIsInstance(platform_keyboard._get_clipboard_backend(), platform_keyboard._WlClipboardBackend)

    def test_get_clipboard_backend_falls_back_to_pyperclip(self):
        with patch("platform_keyboard._is_linux_wayland", return_value=True):
            with patch("platform_keyboard.shutil.which", return_value=None):
                self.assertIsInstance(
                    platform_keyboard._get_clipboard_backend(),
                    platform_keyboard._PyperclipClipboardBackend,
                )

    def test_press_enter_windows_prefers_sendinput(self):
        with patch("platform_keyboard.ensure_runtime_supported"):
            with patch("platform_keyboard._is_linux_wayland", return_value=False):
                with patch("platform_keyboard.get_platform", return_value="windows"):
                    with patch("platform_keyboard._press_enter_windows") as mock_windows:
                        platform_keyboard.press_enter()
        mock_windows.assert_called_once()

    def test_press_enter_windows_falls_back_to_pyautogui(self):
        backend = MagicMock()
        with patch("platform_keyboard.ensure_runtime_supported"):
            with patch("platform_keyboard._is_linux_wayland", return_value=False):
                with patch("platform_keyboard.get_platform", return_value="windows"):
                    with patch("platform_keyboard._press_enter_windows", side_effect=RuntimeError("boom")):
                        with patch("platform_keyboard._get_pyautogui", return_value=backend):
                            platform_keyboard.press_enter()
        backend.press.assert_called_once_with("enter")

    def test_press_enter_non_windows_uses_pyautogui(self):
        backend = MagicMock()
        with patch("platform_keyboard.ensure_runtime_supported"):
            with patch("platform_keyboard._is_linux_wayland", return_value=False):
                with patch("platform_keyboard.get_platform", return_value="linux"):
                    with patch("platform_keyboard._get_pyautogui", return_value=backend):
                        platform_keyboard.press_enter()
        backend.press.assert_called_once_with("enter")


if __name__ == "__main__":
    unittest.main()
