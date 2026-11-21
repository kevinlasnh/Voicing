"""voicing_server：连接注册表、诊断日志、广播隔离、监听重绑防抖单测。

不启动真实监听；只覆盖纯逻辑与 127.0.0.1 级的 handler 行为。
"""
import asyncio
import json
import socket
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import websockets

import network_interfaces as ni
import voicing_server
import voicing_tuning as tuning
from voicing_protocol import TEXT_SEND_MODE_SUBMIT, TYPE_TEXT
from voicing_state import state


class FakeIdentity:
    name = "Test PC"
    device_id = "a" * 32
    os = "linux"


class FakeWebSocket:
    remote_address = ("127.0.0.1", 54321)
    request_headers = {"User-Agent": "Voicing-Test/1.0"}

    def __init__(self, messages=()):
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


class ExplodingWebSocket(FakeWebSocket):
    def __aiter__(self):
        return self

    async def __anext__(self):
        raise RuntimeError("boom")


class SendFailWebSocket(FakeWebSocket):
    async def send(self, message):
        raise RuntimeError("send failed")


def make_services(*, type_text_result=True, enter_result=True, identity=None):
    identity = identity or FakeIdentity()
    return voicing_server.ClientServices(
        type_text=MagicMock(return_value=type_text_result),
        press_enter_after_settle=MagicMock(return_value=enter_result),
        get_identity=MagicMock(return_value=identity),
        notify_qr_probe=MagicMock(),
    )


class ManualClock:
    def __init__(self, now=1000.0):
        self.now = now

    def __call__(self):
        return self.now


class ClientRegistryTests(unittest.TestCase):
    def test_register_touch_and_unregister(self):
        clock = ManualClock()
        registry = voicing_server.ClientRegistry(clock=clock)
        websocket = FakeWebSocket()

        record = registry.register(websocket)
        self.assertEqual(record.remote_address, "127.0.0.1:54321")
        self.assertEqual(record.user_agent, "Voicing-Test/1.0")
        self.assertEqual(len(registry), 1)

        clock.now += 5.0
        registry.touch(websocket, message_type=TYPE_TEXT, message_size=12)
        snapshot = registry.snapshot()
        self.assertEqual(len(snapshot), 1)
        self.assertEqual(snapshot[0]["messages_received"], 1)
        self.assertEqual(snapshot[0]["last_message_type"], TYPE_TEXT)
        self.assertEqual(snapshot[0]["idle_sec"], 0.0)
        self.assertEqual(snapshot[0]["connected_duration_sec"], 5.0)

        removed = registry.unregister(websocket)
        self.assertIs(removed, record)
        self.assertEqual(len(registry), 0)
        self.assertIsNone(registry.unregister(websocket))

    def test_record_duration_and_idle_helpers(self):
        clock = ManualClock(now=50.0)
        registry = voicing_server.ClientRegistry(clock=clock)
        websocket = FakeWebSocket()
        record = registry.register(websocket)
        self.assertEqual(record.connected_duration_sec(60.0), 10.0)
        self.assertEqual(record.idle_sec(60.0), 10.0)

    def test_unknown_websocket_lookups_are_safe(self):
        registry = voicing_server.ClientRegistry()
        self.assertIsNone(registry.get(object()))
        registry.touch(object(), message_type="ping")
        self.assertEqual(registry.snapshot(), [])


class ListenerRebindDeciderTests(unittest.TestCase):
    def test_same_generation_is_not_counted_twice(self):
        decider = voicing_server.ListenerRebindDecider(
            ["192.168.50.113"],
            required_confirmations=2,
        )
        self.assertFalse(decider.observe(["10.16.177.83"], refresh_generation=1))
        # TTL 缓存命中：同一 refresh_generation 不能冒充第二次采样
        self.assertFalse(decider.observe(["10.16.177.83"], refresh_generation=1))
        self.assertEqual(decider.confirmations, 1)
        self.assertTrue(decider.observe(["10.16.177.83"], refresh_generation=2))
        self.assertEqual(decider.confirmations, 2)

    def test_revert_to_bound_hosts_clears_candidate(self):
        decider = voicing_server.ListenerRebindDecider(
            ["192.168.50.113"],
            required_confirmations=2,
        )
        self.assertFalse(decider.observe(["10.16.177.83"], refresh_generation=1))
        self.assertFalse(decider.observe(["192.168.50.113"], refresh_generation=2))
        self.assertEqual(decider.confirmations, 0)
        self.assertIsNone(decider.candidate)
        # 抖动结束后重新计数，不会拿之前的确认次数直接重绑
        self.assertFalse(decider.observe(["10.16.177.83"], refresh_generation=3))
        self.assertEqual(decider.confirmations, 1)

    def test_single_confirmation_configuration_rebinds_immediately(self):
        decider = voicing_server.ListenerRebindDecider(
            ["192.168.50.113"],
            required_confirmations=1,
        )
        self.assertTrue(decider.observe(["10.16.177.83"], refresh_generation=1))

    def test_bound_host_comparison_is_order_insensitive(self):
        decider = voicing_server.ListenerRebindDecider(
            ["192.168.50.113", "100.102.136.4"],
            required_confirmations=2,
        )
        self.assertFalse(
            decider.observe(
                ["100.102.136.4", "192.168.50.113"],
                refresh_generation=1,
            )
        )

    def test_default_confirmation_count_comes_from_tuning(self):
        decider = voicing_server.ListenerRebindDecider(["192.168.50.113"])
        self.assertEqual(decider.required_confirmations, tuning.REBIND_CONFIRMATIONS)


class ServeKwargsTests(unittest.TestCase):
    def test_serve_kwargs_come_from_tuning(self):
        self.assertEqual(
            voicing_server.build_serve_kwargs(),
            {
                "ping_interval": tuning.WS_PING_INTERVAL_SEC,
                "ping_timeout": tuning.WS_PING_TIMEOUT_SEC,
                "close_timeout": tuning.WS_CLOSE_TIMEOUT_SEC,
                "max_size": tuning.WS_MAX_SIZE_BYTES,
            },
        )

    def test_ping_timeout_is_shorter_than_interval_for_fast_dead_detection(self):
        self.assertLess(tuning.WS_PING_TIMEOUT_SEC, tuning.WS_PING_INTERVAL_SEC)
        self.assertEqual(tuning.WS_MAX_SIZE_BYTES, 1024 * 1024)


class HandleClientDiagnosticsTests(unittest.TestCase):
    def setUp(self):
        self.old_sync_enabled = state.sync_enabled
        self.old_clients = set(state.connected_clients)
        state.sync_enabled = True
        state.connected_clients.clear()

    def tearDown(self):
        state.sync_enabled = self.old_sync_enabled
        state.connected_clients.clear()
        state.connected_clients.update(self.old_clients)

    def test_connect_and_disconnect_are_logged_with_remote_and_duration(self):
        websocket = FakeWebSocket()
        registry = voicing_server.ClientRegistry()
        services = make_services()

        with self.assertLogs("voicing_server", level="INFO") as logs:
            asyncio.run(
                voicing_server.handle_client(
                    websocket,
                    services_factory=lambda: services,
                    registry=registry,
                )
            )

        joined = "\n".join(logs.output)
        self.assertIn("WebSocket 客户端已连接", joined)
        self.assertIn("127.0.0.1:54321", joined)
        self.assertIn("WebSocket 客户端断开", joined)
        self.assertIn("连接时长=", joined)
        self.assertEqual(len(registry), 0)
        self.assertNotIn(websocket, state.connected_clients)
        self.assertEqual(websocket.sent[0]["type"], "connected")

    def test_text_injection_result_and_ack_are_logged(self):
        websocket = FakeWebSocket(
            [
                json.dumps(
                    {
                        "type": TYPE_TEXT,
                        "content": "hello",
                        "send_mode": TEXT_SEND_MODE_SUBMIT,
                        "auto_enter": False,
                    }
                )
            ]
        )
        registry = voicing_server.ClientRegistry()
        services = make_services(type_text_result=False)

        with self.assertLogs("voicing_server", level="INFO") as logs:
            asyncio.run(
                voicing_server.handle_client(
                    websocket,
                    services_factory=lambda: services,
                    registry=registry,
                )
            )

        services.type_text.assert_called_once_with("hello", False)
        self.assertIn("文本注入处理", "\n".join(logs.output))
        self.assertEqual(websocket.sent[-1]["type"], "ack")
        self.assertFalse(websocket.sent[-1]["clear_input"])

    def test_handler_exception_is_logged_and_registry_cleaned(self):
        websocket = ExplodingWebSocket()
        registry = voicing_server.ClientRegistry()
        services = make_services()

        with self.assertLogs("voicing_server", level="INFO") as logs:
            asyncio.run(
                voicing_server.handle_client(
                    websocket,
                    services_factory=lambda: services,
                    registry=registry,
                )
            )

        joined = "\n".join(logs.output)
        self.assertIn("WebSocket 客户端处理异常", joined)
        self.assertIn("RuntimeError", joined)
        self.assertEqual(len(registry), 0)
        self.assertEqual(state.connected_clients, set())

    def test_broadcast_isolates_single_client_failure(self):
        ok_socket = FakeWebSocket()
        bad_socket = SendFailWebSocket()
        registry = voicing_server.ClientRegistry()
        registry.register(ok_socket)
        registry.register(bad_socket)
        state.connected_clients.update({ok_socket, bad_socket})

        with self.assertLogs("voicing_server", level="WARNING") as logs:
            sent, failed = asyncio.run(voicing_server.broadcast_sync_state(registry))

        self.assertEqual((sent, failed), (1, 1))
        self.assertEqual(ok_socket.sent[-1]["type"], "sync_state")
        self.assertIn("失败", "\n".join(logs.output))

    def test_broadcast_without_clients_is_noop(self):
        self.assertEqual(asyncio.run(voicing_server.broadcast_sync_state()), (0, 0))


def _free_tcp_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


class ServerListenerLifecycleTests(unittest.TestCase):
    """只用 127.0.0.1 验证 serve 参数、握手、ping/pong 与优雅关闭（不起对外监听）。"""

    def test_listener_accepts_connection_and_stops_cleanly(self):
        port = _free_tcp_port()
        old_port = state.ws_port
        old_running = state.running
        old_loop = state.server_loop
        state.ws_port = port
        state.running = True

        registry = voicing_server.ClientRegistry()
        services = make_services()
        stable_snapshot = ni.InterfaceSnapshot(
            interfaces=(("127.0.0.1", "127.0.0.255"),),
            version=1,
            refresh_generation=1,
        )

        async def scenario():
            task = asyncio.create_task(
                voicing_server.start_server(
                    services_factory=lambda: services,
                    registry=registry,
                )
            )
            try:
                deadline = asyncio.get_running_loop().time() + 2.0
                connection = None
                while connection is None:
                    try:
                        connection = await websockets.connect(
                            f"ws://127.0.0.1:{port}",
                            open_timeout=0.2,
                        )
                    except (OSError, asyncio.TimeoutError):
                        if asyncio.get_running_loop().time() > deadline:
                            raise AssertionError("127.0.0.1 监听未在超时内就绪")
                        await asyncio.sleep(0.005)

                try:
                    connected = json.loads(await asyncio.wait_for(connection.recv(), timeout=1))
                    await connection.send(json.dumps({"type": "ping", "source": "test"}))
                    pong = json.loads(await asyncio.wait_for(connection.recv(), timeout=1))
                finally:
                    await connection.close()

                state.running = False
                await asyncio.wait_for(task, timeout=2)
                return connected, pong
            finally:
                state.running = old_running

        with (
            patch.object(ni, "get_advertised_server_ips", return_value=["127.0.0.1"]),
            patch.object(ni, "get_interface_snapshot", return_value=stable_snapshot),
            patch.object(tuning, "NETWORK_SNAPSHOT_POLL_SEC", 0.01),
        ):
            try:
                connected, pong = asyncio.run(asyncio.wait_for(scenario(), timeout=5))
            finally:
                state.ws_port = old_port
                state.server_loop = old_loop

        self.assertEqual(connected["type"], "connected")
        self.assertTrue(connected["sync_enabled"])
        self.assertEqual(pong["type"], "pong")
        # 连接断开后注册表必须清空（handle_client finally 保证）
        self.assertEqual(len(registry), 0)


if __name__ == "__main__":
    unittest.main()
