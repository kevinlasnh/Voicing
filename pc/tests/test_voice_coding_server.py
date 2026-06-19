import asyncio
import json
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import voice_coding
from voicing_protocol import TYPE_TEXT, TEXT_SEND_MODE_SUBMIT


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


if __name__ == "__main__":
    unittest.main()
