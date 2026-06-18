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


class TrayNativeMenuTests(unittest.TestCase):
    def test_native_menu_pops_on_left_and_double_click(self):
        # Linux 原生菜单在左键 / 双击时手动 popup
        self.assertTrue(
            ModernTrayIcon._should_popup_native_menu_for_activation_reason(QSystemTrayIcon.Trigger)
        )
        self.assertTrue(
            ModernTrayIcon._should_popup_native_menu_for_activation_reason(QSystemTrayIcon.DoubleClick)
        )

    def test_native_menu_skips_context_to_avoid_double_menu(self):
        # 右键交给 setContextMenu / 宿主；这里再 popup 会同时弹两个菜单
        self.assertFalse(
            ModernTrayIcon._should_popup_native_menu_for_activation_reason(QSystemTrayIcon.Context)
        )

    def test_native_menu_skips_middle_click(self):
        self.assertFalse(
            ModernTrayIcon._should_popup_native_menu_for_activation_reason(QSystemTrayIcon.MiddleClick)
        )

    def test_custom_menu_filter_still_independent_of_platform(self):
        # 自定义菜单过滤器保持不变，供 Windows/macOS 使用
        self.assertTrue(
            ModernTrayIcon._should_show_custom_menu_for_activation_reason(QSystemTrayIcon.Context)
        )


if __name__ == "__main__":
    unittest.main()
