"""voicing_tuning 参数解析 / 环境变量覆盖 / 启动日志 单测。"""
import importlib
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import voicing_tuning


class TuningOverrideTests(unittest.TestCase):
    def test_defaults_are_used_without_env(self):
        values, overrides = voicing_tuning.load_effective_values({})
        self.assertEqual(overrides, {})
        self.assertEqual(values["AUTO_ENTER_SETTLE_DELAY_SEC"], 0.35)
        self.assertEqual(values["NETWORK_SNAPSHOT_TTL_SEC"], 1.5)
        self.assertEqual(values["REBIND_CONFIRMATIONS"], 2)
        self.assertEqual(values["WS_PING_INTERVAL_SEC"], 20.0)
        self.assertEqual(values["WS_PING_TIMEOUT_SEC"], 10.0)
        self.assertEqual(values["WS_CLOSE_TIMEOUT_SEC"], 5.0)
        self.assertEqual(values["WS_MAX_SIZE_BYTES"], 1024 * 1024)
        self.assertEqual(values["QR_REFRESH_INTERVAL_MS"], 5000)
        self.assertEqual(values["TRAY_ICON_UPDATE_INTERVAL_MS"], 200)
        self.assertIs(values["LOG_INTERFACE_ENUMERATIONS"], True)

    def test_env_overrides_are_parsed_with_expected_types(self):
        values, overrides = voicing_tuning.load_effective_values(
            {
                "VOICING_WS_PING_TIMEOUT_SEC": "3.5",
                "VOICING_REBIND_CONFIRMATIONS": "3",
                "VOICING_QR_REFRESH_INTERVAL_MS": "2500",
                "VOICING_LOG_INTERFACE_ENUMERATIONS": "false",
            }
        )
        self.assertEqual(values["WS_PING_TIMEOUT_SEC"], 3.5)
        self.assertEqual(values["REBIND_CONFIRMATIONS"], 3)
        self.assertEqual(values["QR_REFRESH_INTERVAL_MS"], 2500)
        self.assertIs(values["LOG_INTERFACE_ENUMERATIONS"], False)
        self.assertEqual(
            set(overrides),
            {
                "WS_PING_TIMEOUT_SEC",
                "REBIND_CONFIRMATIONS",
                "QR_REFRESH_INTERVAL_MS",
                "LOG_INTERFACE_ENUMERATIONS",
            },
        )

    def test_invalid_env_falls_back_to_default_with_warning(self):
        with self.assertLogs(voicing_tuning.LOGGER, level="WARNING") as logs:
            values, overrides = voicing_tuning.load_effective_values(
                {
                    "VOICING_NETWORK_SNAPSHOT_TTL_SEC": "not-a-number",
                    "VOICING_REBIND_CONFIRMATIONS": "0",
                    "VOICING_WS_PING_TIMEOUT_SEC": "-1",
                }
            )
        self.assertEqual(values["NETWORK_SNAPSHOT_TTL_SEC"], 1.5)
        self.assertEqual(values["REBIND_CONFIRMATIONS"], 2)
        self.assertEqual(values["WS_PING_TIMEOUT_SEC"], 10.0)
        self.assertEqual(overrides, {})
        joined = "\n".join(logs.output)
        self.assertIn("VOICING_NETWORK_SNAPSHOT_TTL_SEC", joined)
        self.assertIn("使用默认值", joined)

    def test_blank_env_value_keeps_default_without_warning(self):
        values, overrides = voicing_tuning.load_effective_values(
            {"VOICING_NETWORK_SNAPSHOT_TTL_SEC": "   "}
        )
        self.assertEqual(values["NETWORK_SNAPSHOT_TTL_SEC"], 1.5)
        self.assertEqual(overrides, {})

    def test_effective_log_marks_env_source_and_values(self):
        try:
            with patch.dict(
                os.environ,
                {
                    "VOICING_WS_PING_INTERVAL_SEC": "7",
                    "VOICING_NETWORK_SNAPSHOT_TTL_SEC": "2.5",
                },
                clear=False,
            ):
                reloaded = importlib.reload(voicing_tuning)
                self.assertEqual(reloaded.WS_PING_INTERVAL_SEC, 7.0)
                self.assertEqual(reloaded.NETWORK_SNAPSHOT_TTL_SEC, 2.5)
                lines = reloaded.format_effective_tuning()
                joined = "\n".join(lines)
                self.assertIn("WS_PING_INTERVAL_SEC=7.0(env)", joined)
                self.assertIn("NETWORK_SNAPSHOT_TTL_SEC=2.5(env)", joined)
                self.assertIn("环境变量覆盖", joined)
        finally:
            # 恢复默认值，避免污染后续测试/模块常量
            os.environ.pop("VOICING_WS_PING_INTERVAL_SEC", None)
            os.environ.pop("VOICING_NETWORK_SNAPSHOT_TTL_SEC", None)
            importlib.reload(voicing_tuning)

    def test_log_effective_tuning_writes_lines_to_logger(self):
        with self.assertLogs(voicing_tuning.LOGGER, level="INFO") as logs:
            voicing_tuning.log_effective_tuning()
        joined = "\n".join(logs.output)
        self.assertIn("可调参数生效值", joined)
        self.assertIn("NETWORK_SNAPSHOT_TTL_SEC=", joined)
        self.assertIn("WS_PING_TIMEOUT_SEC=", joined)


if __name__ == "__main__":
    unittest.main()
