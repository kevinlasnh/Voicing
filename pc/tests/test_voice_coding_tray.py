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


class CustomMenuLayoutTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        from PyQt5.QtWidgets import QApplication
        cls.app = QApplication.instance() or QApplication([])

    def test_custom_menu_has_no_separator_items(self):
        # 自定义 Fluent 菜单（Windows/macOS）不再在项之间插入分隔横条。
        # container 内应恰好 5 个功能项：QR / 同步输入 / 开机自启 / 打开日志 / 退出应用。
        from voice_coding import ModernMenuWidget
        menu = ModernMenuWidget()
        self.assertEqual(menu.container.layout().count(), 5)

    def test_custom_menu_width_tightens_to_content(self):
        # 菜单内容尺寸应等于 sizeHint；setFixedWidth(sizeHint) 收紧掉 adjustSize 的多余宽度。
        from voice_coding import ModernMenuWidget
        menu = ModernMenuWidget()
        menu.adjustSize()
        menu.setFixedWidth(menu.sizeHint().width())
        self.assertEqual(menu.width(), menu.sizeHint().width())
        # 宽度应在最长项内容附近，不应是 adjustSize 默认的偏大值（约 200）。
        self.assertLess(menu.width(), 190)


if __name__ == "__main__":
    unittest.main()
