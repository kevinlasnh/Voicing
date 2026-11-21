import asyncio
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import voice_coding
from voicing_protocol import TYPE_TEXT, TEXT_SEND_MODE_COMMIT, TEXT_SEND_MODE_SUBMIT


class FakeWebSocket:
    remote_address = ("127.0.0.1", 12345)

    def __init__(self, messages):
        self._messages = list(messages)
        self.sent = []

    async def send(self, message):
        self.sent.append(json.loads(message))

    def __aiter__(self):
        return self

    async def __anext__(self):
        if not self._messages:
            raise StopAsyncIteration
        return self._messages.pop(0)


class HandleClientTests(unittest.TestCase):
    def test_failed_text_injection_ack_does_not_clear_phone_input(self):
        message = json.dumps(
            {
                "type": TYPE_TEXT,
                "content": "hello",
                "send_mode": TEXT_SEND_MODE_SUBMIT,
                "auto_enter": False,
            }
        )
        websocket = FakeWebSocket([message])
        old_sync_enabled = voice_coding.state.sync_enabled
        old_clients = set(voice_coding.state.connected_clients)
        try:
            voice_coding.state.sync_enabled = True
            voice_coding.state.connected_clients.clear()
            with (
                patch("voice_coding.type_text", return_value=False),
                patch("voice_coding.get_or_create_device_identity") as identity,
            ):
                identity.return_value.name = "PC"
                identity.return_value.device_id = "device"
                identity.return_value.os = "linux"
                asyncio.run(voice_coding.handle_client(websocket))
        finally:
            voice_coding.state.sync_enabled = old_sync_enabled
            voice_coding.state.connected_clients.clear()
            voice_coding.state.connected_clients.update(old_clients)

        self.assertEqual(websocket.sent[-1]["type"], "ack")
        self.assertFalse(websocket.sent[-1]["clear_input"])

    def test_commit_auto_enter_ack_clears_after_enter_succeeds(self):
        message = json.dumps(
            {
                "type": TYPE_TEXT,
                "content": "",
                "send_mode": TEXT_SEND_MODE_COMMIT,
                "auto_enter": True,
            }
        )
        websocket = FakeWebSocket([message])
        old_sync_enabled = voice_coding.state.sync_enabled
        old_clients = set(voice_coding.state.connected_clients)
        try:
            voice_coding.state.sync_enabled = True
            voice_coding.state.connected_clients.clear()
            with (
                patch("voice_coding.press_enter_after_settle", return_value=True) as mock_enter,
                patch("voice_coding.get_or_create_device_identity") as identity,
            ):
                identity.return_value.name = "PC"
                identity.return_value.device_id = "device"
                identity.return_value.os = "linux"
                asyncio.run(voice_coding.handle_client(websocket))
        finally:
            voice_coding.state.sync_enabled = old_sync_enabled
            voice_coding.state.connected_clients.clear()
            voice_coding.state.connected_clients.update(old_clients)

        mock_enter.assert_called_once()
        self.assertEqual(websocket.sent[-1]["type"], "ack")
        self.assertTrue(websocket.sent[-1]["clear_input"])

    def test_commit_auto_enter_ack_keeps_input_after_enter_fails(self):
        message = json.dumps(
            {
                "type": TYPE_TEXT,
                "content": "",
                "send_mode": TEXT_SEND_MODE_COMMIT,
                "auto_enter": True,
            }
        )
        websocket = FakeWebSocket([message])
        old_sync_enabled = voice_coding.state.sync_enabled
        old_clients = set(voice_coding.state.connected_clients)
        try:
            voice_coding.state.sync_enabled = True
            voice_coding.state.connected_clients.clear()
            with (
                patch("voice_coding.press_enter_after_settle", return_value=False) as mock_enter,
                patch("voice_coding.get_or_create_device_identity") as identity,
            ):
                identity.return_value.name = "PC"
                identity.return_value.device_id = "device"
                identity.return_value.os = "linux"
                asyncio.run(voice_coding.handle_client(websocket))
        finally:
            voice_coding.state.sync_enabled = old_sync_enabled
            voice_coding.state.connected_clients.clear()
            voice_coding.state.connected_clients.update(old_clients)

        mock_enter.assert_called_once()
        self.assertEqual(websocket.sent[-1]["type"], "ack")
        self.assertFalse(websocket.sent[-1]["clear_input"])


class TextInputLoggingTests(unittest.TestCase):
    """2026-11-20：文本注入路径补充耗时/失败日志，且仍保留 asyncio.to_thread 调用。"""

    def setUp(self):
        self.old_sync_enabled = voice_coding.state.sync_enabled
        voice_coding.state.sync_enabled = True

    def tearDown(self):
        voice_coding.state.sync_enabled = self.old_sync_enabled

    def test_type_text_success_logs_duration_and_keeps_delays(self):
        with (
            patch("voice_coding.type_text_at_cursor") as inject,
            self.assertLogs(level="INFO") as logs,
        ):
            self.assertTrue(voice_coding.type_text("你好", auto_enter=True))

        inject.assert_called_once()
        kwargs = inject.call_args.kwargs
        self.assertIs(kwargs["auto_enter"], True)
        self.assertIn("enter_delay_sec", kwargs)
        self.assertIn("restore_delay_sec", kwargs)
        self.assertIn("文本注入成功", "\n".join(logs.output))

    def test_type_text_failure_logs_error_and_returns_false(self):
        with (
            patch("voice_coding.type_text_at_cursor", side_effect=RuntimeError("boom")),
            self.assertLogs(level="ERROR") as logs,
        ):
            self.assertFalse(voice_coding.type_text("你好"))

        joined = "\n".join(logs.output)
        self.assertIn("文本注入失败", joined)
        self.assertIn("boom", joined)

    def test_type_text_disabled_sync_skips_injection(self):
        voice_coding.state.sync_enabled = False
        with patch("voice_coding.type_text_at_cursor") as inject:
            self.assertFalse(voice_coding.type_text("你好"))
        inject.assert_not_called()


class HandlerRegistryCompatTests(unittest.TestCase):
    """兼容层 handle_client 必须把连接登记进共享注册表并在断开时清理。"""

    def test_handle_client_uses_shared_registry_and_logs(self):
        websocket = FakeWebSocket([])
        old_clients = set(voice_coding.state.connected_clients)
        voice_coding.state.connected_clients.clear()
        try:
            with (
                patch("voice_coding.get_or_create_device_identity") as identity,
                self.assertLogs("voicing_server", level="INFO") as logs,
            ):
                identity.return_value.name = "PC"
                identity.return_value.device_id = "device"
                identity.return_value.os = "linux"
                asyncio.run(voice_coding.handle_client(websocket))
        finally:
            voice_coding.state.connected_clients.clear()
            voice_coding.state.connected_clients.update(old_clients)

        joined = "\n".join(logs.output)
        self.assertIn("WebSocket 客户端已连接", joined)
        self.assertIn("WebSocket 客户端断开", joined)
        self.assertEqual(len(voice_coding.server_registry), 0)


if __name__ == "__main__":
    unittest.main()
