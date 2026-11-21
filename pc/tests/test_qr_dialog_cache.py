"""QR 弹窗 payload / pixmap 缓存与「仅可见时刷新」单测（offscreen）。"""
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from PyQt5.QtWidgets import QApplication

from device_identity import DeviceIdentity
import qr_dialog
import voicing_tuning as tuning


class QRCodeDialogCacheTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self):
        self.identity = DeviceIdentity("a" * 32, "Test PC", "linux")
        identity_patcher = patch.object(
            qr_dialog,
            "get_or_create_device_identity",
            return_value=self.identity,
        )
        identity_patcher.start()
        self.addCleanup(identity_patcher.stop)
        self.dialog = qr_dialog.QRCodeDialog()

    def tearDown(self):
        self.dialog.hide()
        self.dialog.deleteLater()

    def _snapshot_patcher(self, ips, primary=None):
        return (
            patch.object(qr_dialog, "get_qr_advertised_server_ips", return_value=list(ips)),
            patch.object(qr_dialog, "get_primary_server_ip", return_value=primary or (ips[0] if ips else "")),
        )

    def test_payload_uses_cached_snapshot_without_forced_refresh(self):
        ips_patcher, primary_patcher = self._snapshot_patcher(["192.168.50.113"])
        with ips_patcher as ips_mock, primary_patcher:
            payload = self.dialog._build_qr_payload()

        ips_mock.assert_called_once_with()
        self.assertIn('"ip":"192.168.50.113"', payload)
        self.assertIn('"device_id":"' + "a" * 32 + '"', payload)
        self.assertIn(f'"port":{qr_dialog.state.ws_port}', payload)

    def test_pixmap_is_reused_until_payload_changes(self):
        generate = MagicMock(wraps=self.dialog._generate_qr_pixmap)
        ips_patcher, primary_patcher = self._snapshot_patcher(["192.168.50.113"])
        with ips_patcher, primary_patcher, patch.object(
            self.dialog, "_generate_qr_pixmap", generate
        ):
            self.assertTrue(self.dialog._populate_content())
            self.assertFalse(self.dialog._populate_content())
            self.assertEqual(generate.call_count, 1, "payload 不变时必须复用 pixmap")

            # 接口地址变化 -> 重新生成一次
            with self._snapshot_patcher(["10.16.177.83"])[0]:
                self.assertTrue(self.dialog._populate_content())
            self.assertEqual(generate.call_count, 2)

    def test_cached_pixmap_object_is_identical_on_repeat(self):
        ips_patcher, primary_patcher = self._snapshot_patcher(["192.168.50.113"])
        with ips_patcher, primary_patcher:
            self.dialog._populate_content()
            first_pixmap = self.dialog._cached_qr_pixmap
            self.dialog._populate_content()
        self.assertIs(self.dialog._cached_qr_pixmap, first_pixmap)

    def test_hidden_dialog_skips_timer_refresh(self):
        with patch.object(self.dialog, "_populate_content", return_value=True) as populate:
            with patch.object(self.dialog, "isVisible", return_value=False):
                self.dialog._refresh_qr()
            populate.assert_not_called()

    def test_visible_dialog_refreshes_payload(self):
        with patch.object(self.dialog, "_populate_content", return_value=False) as populate:
            with patch.object(self.dialog, "isVisible", return_value=True):
                self.dialog._refresh_qr()
            populate.assert_called_once_with()

    def test_refresh_timer_uses_tuning_interval(self):
        self.assertEqual(
            self.dialog._refresh_timer.interval(),
            tuning.QR_REFRESH_INTERVAL_MS,
        )
        self.assertFalse(self.dialog._refresh_timer.isActive(), "隐藏弹窗不应启动刷新定时器")


if __name__ == "__main__":
    unittest.main()
