import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import platform_utils


class PlatformUtilsTests(unittest.TestCase):
    def test_get_platform_returns_supported_value(self):
        self.assertIn(platform_utils.get_platform(), {"windows", "darwin", "linux"})

    def test_get_log_dir_windows(self):
        with patch.object(platform_utils.sys, "platform", "win32"):
            with patch.dict(os.environ, {"APPDATA": r"C:\Users\tester\AppData\Roaming"}, clear=False):
                self.assertEqual(
                    platform_utils.get_log_dir(),
                    Path(r"C:\Users\tester\AppData\Roaming") / "Voicing" / "logs",
                )

    def test_get_data_dir_macos(self):
        fake_home = Path("/Users/tester")
        with patch.object(platform_utils.sys, "platform", "darwin"):
            with patch.object(platform_utils.Path, "home", return_value=fake_home):
                self.assertEqual(
                    platform_utils.get_data_dir(),
                    fake_home / "Library" / "Application Support" / "Voicing",
                )

    def test_get_data_dir_linux(self):
        fake_home = Path("/home/tester")
        with patch.object(platform_utils.sys, "platform", "linux"):
            with patch.object(platform_utils.Path, "home", return_value=fake_home):
                self.assertEqual(
                    platform_utils.get_data_dir(),
                    fake_home / ".local" / "share" / "Voicing",
                )

    def test_wayland_runtime_is_allowed_with_keyboard_portal(self):
        with patch.object(platform_utils.sys, "platform", "linux"):
            with patch.dict(os.environ, {"XDG_SESSION_TYPE": "wayland"}, clear=False):
                with patch("platform_utils.has_remote_desktop_keyboard_portal", return_value=True):
                    platform_utils.ensure_runtime_supported()

    def test_wayland_runtime_is_blocked_without_keyboard_portal(self):
        with patch.object(platform_utils.sys, "platform", "linux"):
            with patch.dict(os.environ, {"XDG_SESSION_TYPE": "wayland"}, clear=False):
                with patch("platform_utils.has_remote_desktop_keyboard_portal", return_value=False):
                    with self.assertRaises(RuntimeError):
                        platform_utils.ensure_runtime_supported()

    def test_remote_desktop_keyboard_portal_detects_keyboard_bit(self):
        with patch.object(platform_utils.sys, "platform", "linux"):
            with patch("platform_utils._get_remote_desktop_available_device_types", return_value=7):
                self.assertTrue(platform_utils.has_remote_desktop_keyboard_portal())

    def test_remote_desktop_keyboard_portal_returns_false_without_keyboard_bit(self):
        with patch.object(platform_utils.sys, "platform", "linux"):
            with patch("platform_utils._get_remote_desktop_available_device_types", return_value=2):
                self.assertFalse(platform_utils.has_remote_desktop_keyboard_portal())

    def test_remote_desktop_keyboard_portal_returns_false_on_probe_error(self):
        with patch.object(platform_utils.sys, "platform", "linux"):
            with patch(
                "platform_utils._get_remote_desktop_available_device_types",
                side_effect=ImportError("missing"),
            ):
                self.assertFalse(platform_utils.has_remote_desktop_keyboard_portal())

    def test_remote_desktop_device_types_prefers_gdbus(self):
        with patch("platform_utils.shutil.which", return_value="/usr/bin/gdbus"):
            with patch(
                "platform_utils._get_remote_desktop_available_device_types_with_gdbus",
                return_value=7,
            ) as mock_gdbus:
                self.assertEqual(platform_utils._get_remote_desktop_available_device_types(), 7)
        mock_gdbus.assert_called_once_with("/usr/bin/gdbus")

    def test_remote_desktop_device_types_gdbus_parses_uint(self):
        result = MagicMock()
        result.stdout = "(<uint32 7>,)"
        with patch("platform_utils.subprocess.run", return_value=result) as mock_run:
            value = platform_utils._get_remote_desktop_available_device_types_with_gdbus("/usr/bin/gdbus")
        self.assertEqual(value, 7)
        mock_run.assert_called_once()

    def test_remote_desktop_device_types_gdbus_returns_zero_without_number(self):
        result = MagicMock()
        result.stdout = "(<uint32>,)"
        with patch("platform_utils.subprocess.run", return_value=result):
            value = platform_utils._get_remote_desktop_available_device_types_with_gdbus("/usr/bin/gdbus")
        self.assertEqual(value, 0)

    def test_known_hotspot_prefixes_cover_all_platforms(self):
        self.assertEqual(
            platform_utils.get_known_hotspot_prefixes(),
            ("192.168.137.", "192.168.2.", "10.42.0."),
        )

    def test_get_default_server_ip_windows(self):
        with patch.object(platform_utils.sys, "platform", "win32"):
            self.assertEqual(platform_utils.get_default_server_ip(), "192.168.137.1")


if __name__ == "__main__":
    unittest.main()
