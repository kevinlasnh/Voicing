import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PyQt5.QtWidgets import QSystemTrayIcon

from voice_coding import ModernTrayIcon


class TrayActivationTests(unittest.TestCase):
    def test_common_tray_activation_reasons_open_custom_menu(self):
        self.assertTrue(
            ModernTrayIcon._should_show_custom_menu_for_activation_reason(QSystemTrayIcon.Context)
        )
        self.assertTrue(
            ModernTrayIcon._should_show_custom_menu_for_activation_reason(QSystemTrayIcon.Trigger)
        )
        self.assertTrue(
            ModernTrayIcon._should_show_custom_menu_for_activation_reason(QSystemTrayIcon.DoubleClick)
        )

    def test_middle_click_does_not_open_custom_menu(self):
        self.assertFalse(
            ModernTrayIcon._should_show_custom_menu_for_activation_reason(QSystemTrayIcon.MiddleClick)
        )


if __name__ == "__main__":
    unittest.main()
