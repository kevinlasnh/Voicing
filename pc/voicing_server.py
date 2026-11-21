"""WebSocket server 生命周期 / 客户端连接处理 / 同步状态广播。

线程模型：
    * ``run_server`` 在独立线程里跑自己的 asyncio event loop，Qt 主线程通过
      ``run_coroutine_threadsafe`` 把广播投递过来（见装配层 ``voice_coding``）。
    * 阻塞的文本注入一律 ``asyncio.to_thread``，绝不阻塞 event loop。

可观测性（2026-11-20 现场需求）：
    frozen windowed 应用看不到 stdout，因此连接建立/断开/注入结果同时写 logging
    文件日志。``ClientRegistry`` 记录 remote addr / user-agent / 连接时间 / 最近活动
    / 消息计数 / 断开原因，用于排查手机跨网络重连抖动。
"""
from __future__ import annotations

import asyncio
import functools
import json
import logging
import threading
import time
from dataclasses import dataclass
from typing import Callable, Optional

import websockets
from websockets.exceptions import ConnectionClosed
from websockets.server import serve

import network_interfaces
import voicing_tuning as tuning
from voicing_protocol import (
    QR_SCAN_PING_SOURCE,
    TEXT_SEND_MODE_COMMIT,
    TEXT_SEND_MODE_SUBMIT,
    TYPE_PING,
    TYPE_TEXT,
    build_ack_message,
    build_connected_message,
    build_pong_message,
    build_sync_disabled_message,
    build_sync_state_message,
)
from voicing_state import state


LOGGER = logging.getLogger(__name__)


# ============================================================
# 连接注册表 / Client registry
# ============================================================
def _format_remote_address(websocket) -> str:
    remote = getattr(websocket, "remote_address", None)
    if isinstance(remote, (tuple, list)) and len(remote) >= 2:
        return f"{remote[0]}:{remote[1]}"
    return str(remote or "unknown")


def _extract_user_agent(websocket) -> str:
    headers = getattr(websocket, "request_headers", None)
    if headers is None:
        return ""
    try:
        return str(headers.get("User-Agent", ""))[:120]
    except Exception:
        return ""


@dataclass
class ClientConnectionRecord:
    """单个 WebSocket 客户端的诊断信息。"""

    remote_address: str
    user_agent: str
    connected_at: float        # time.monotonic，用于算精确时长
    connected_at_local: str    # 墙钟时间，便于和日志/手机端对照
    last_activity: float
    messages_received: int = 0
    last_message_type: str = ""

    def connected_duration_sec(self, now: float) -> float:
        return max(0.0, now - self.connected_at)

    def idle_sec(self, now: float) -> float:
        return max(0.0, now - self.last_activity)


class ClientRegistry:
    """线程安全的连接注册表；server loop 内使用，诊断日志可随时读取快照。"""

    def __init__(self, clock: Optional[Callable[[], float]] = None) -> None:
        self._clock = clock or time.monotonic
        self._lock = threading.Lock()
        self._clients: dict[object, ClientConnectionRecord] = {}

    def register(self, websocket) -> ClientConnectionRecord:
        now = self._clock()
        record = ClientConnectionRecord(
            remote_address=_format_remote_address(websocket),
            user_agent=_extract_user_agent(websocket),
            connected_at=now,
            connected_at_local=time.strftime("%Y-%m-%d %H:%M:%S"),
            last_activity=now,
        )
        with self._lock:
            self._clients[websocket] = record
        return record

    def touch(
        self,
        websocket,
        *,
        message_type: str = "",
        message_size: int = 0,
    ) -> None:
        del message_size  # 目前只留最近活动，大小进 DEBUG 日志可后续扩展
        now = self._clock()
        with self._lock:
            record = self._clients.get(websocket)
            if record is None:
                return
            record.last_activity = now
            record.messages_received += 1
            if message_type:
                record.last_message_type = message_type

    def unregister(self, websocket) -> Optional[ClientConnectionRecord]:
        with self._lock:
            return self._clients.pop(websocket, None)

    def get(self, websocket) -> Optional[ClientConnectionRecord]:
        with self._lock:
            return self._clients.get(websocket)

    def snapshot(self) -> list[dict]:
        now = self._clock()
        with self._lock:
            records = list(self._clients.values())
        return [
            {
                "remote_address": record.remote_address,
                "user_agent": record.user_agent,
                "connected_at": record.connected_at_local,
                "connected_duration_sec": round(record.connected_duration_sec(now), 1),
                "idle_sec": round(record.idle_sec(now), 1),
                "messages_received": record.messages_received,
                "last_message_type": record.last_message_type,
            }
            for record in records
        ]

    def __len__(self) -> int:
        with self._lock:
            return len(self._clients)

    def __contains__(self, websocket) -> bool:
        with self._lock:
            return websocket in self._clients


@dataclass(frozen=True)
class ClientServices:
    """装配层注入的依赖，便于旧测试继续 patch ``voice_coding.X`` 生效。"""

    type_text: Callable[[str, bool], bool]
    press_enter_after_settle: Callable[..., bool]
    get_identity: Callable[[], object]
    notify_qr_probe: Callable[[str], None]


# ============================================================
# Client handling / 客户端处理
# ============================================================
async def handle_client(
    websocket,
    *,
    services_factory: Callable[[], ClientServices],
    registry: ClientRegistry,
) -> None:
    """Handle incoming WebSocket connections / 处理传入的 WebSocket 连接。"""
    services = services_factory()
    record = registry.register(websocket)
    with state.lock:
        state.connected_clients.add(websocket)
    LOGGER.info(
        "WebSocket 客户端已连接: remote=%s ua=%r 在线=%d",
        record.remote_address,
        record.user_agent,
        len(registry),
    )
    print(f"Client connected: {getattr(websocket, 'remote_address', record.remote_address)}")

    disconnect_reason = "normal"
    try:
        # Get computer name for identification
        device_identity = services.get_identity()

        # Send welcome message with current sync state and computer name
        await websocket.send(json.dumps(build_connected_message(
            sync_enabled=state.sync_enabled,
            computer_name=device_identity.name,
            device_id=device_identity.device_id,
            os_name=device_identity.os,
        )))

        async for message in websocket:
            try:
                data = json.loads(message)
                msg_type = data.get("type", "")
                registry.touch(websocket, message_type=msg_type, message_size=len(message))

                if msg_type == TYPE_TEXT:
                    # Check if sync is enabled
                    if not state.sync_enabled:
                        await websocket.send(json.dumps(build_sync_disabled_message()))
                        LOGGER.info(
                            "收到文本但同步已暂停: remote=%s mode=%s",
                            record.remote_address,
                            data.get("send_mode", TEXT_SEND_MODE_SUBMIT),
                        )
                        continue

                    text = data.get("content", "")
                    send_mode = data.get("send_mode", TEXT_SEND_MODE_SUBMIT)
                    auto_enter = data.get("auto_enter", False) and send_mode == TEXT_SEND_MODE_SUBMIT
                    started = time.perf_counter()
                    if send_mode == TEXT_SEND_MODE_COMMIT:
                        entered = False
                        if data.get("auto_enter", False):
                            entered = await asyncio.to_thread(services.press_enter_after_settle)
                        await websocket.send(json.dumps(build_ack_message(
                            clear_input=entered,
                        )))
                        LOGGER.info(
                            "commit Enter 处理: remote=%s auto_enter=%s clear_input=%s 耗时=%.1fms",
                            record.remote_address,
                            data.get("auto_enter", False),
                            entered,
                            (time.perf_counter() - started) * 1000,
                        )
                    elif text:
                        # Type the received text (run in thread to avoid blocking event loop)
                        typed = await asyncio.to_thread(services.type_text, text, auto_enter)
                        # Send acknowledgment
                        await websocket.send(json.dumps(build_ack_message(
                            clear_input=typed and send_mode == TEXT_SEND_MODE_SUBMIT,
                        )))
                        LOGGER.info(
                            "文本注入处理: remote=%s mode=%s chars=%d auto_enter=%s "
                            "clear_input=%s 耗时=%.1fms",
                            record.remote_address,
                            send_mode,
                            len(text),
                            auto_enter,
                            typed and send_mode == TEXT_SEND_MODE_SUBMIT,
                            (time.perf_counter() - started) * 1000,
                        )
                    else:
                        LOGGER.debug(
                            "收到空文本消息，按原行为忽略: remote=%s mode=%s",
                            record.remote_address,
                            send_mode,
                        )

                elif msg_type == TYPE_PING:
                    if data.get("source") == QR_SCAN_PING_SOURCE:
                        services.notify_qr_probe("qr_scan_probe")
                    # Respond with pong and current sync state
                    await websocket.send(json.dumps(build_pong_message(
                        sync_enabled=state.sync_enabled,
                    )))

            except json.JSONDecodeError:
                # If not JSON, treat as plain text
                registry.touch(websocket, message_type="text(raw)", message_size=len(message))
                if message.strip() and state.sync_enabled:
                    started = time.perf_counter()
                    typed = await asyncio.to_thread(services.type_text, message)
                    LOGGER.info(
                        "裸文本注入: remote=%s chars=%d result=%s 耗时=%.1fms",
                        record.remote_address,
                        len(message),
                        typed,
                        (time.perf_counter() - started) * 1000,
                    )

    except ConnectionClosed as exc:
        disconnect_reason = f"closed code={exc.code} reason={exc.reason!r}"
    except Exception as exc:  # noqa: BLE001 - 单连接异常不能拖垮 server
        disconnect_reason = f"error {type(exc).__name__}: {exc}"
        LOGGER.error(
            "WebSocket 客户端处理异常: remote=%s %s",
            record.remote_address,
            disconnect_reason,
        )
    finally:
        with state.lock:
            state.connected_clients.discard(websocket)
        removed = registry.unregister(websocket)
        duration = time.monotonic() - record.connected_at
        LOGGER.info(
            "WebSocket 客户端断开: remote=%s 原因=%s 连接时长=%.1fs 消息数=%d 在线=%d",
            record.remote_address,
            disconnect_reason,
            duration,
            record.messages_received if removed is None else removed.messages_received,
            len(registry),
        )
        if removed is not None and removed.messages_received:
            LOGGER.debug(
                "断开客户端细节: ua=%r connected_at=%s last_message_type=%s 最近活动=%.1fs前",
                removed.user_agent,
                removed.connected_at_local,
                removed.last_message_type,
                removed.idle_sec(time.monotonic()),
            )
        print(f"Client disconnected: {getattr(websocket, 'remote_address', record.remote_address)}")


# ============================================================
# Sync broadcast / 同步状态广播
# ============================================================
async def broadcast_sync_state(registry: Optional[ClientRegistry] = None) -> tuple[int, int]:
    """Broadcast sync state to all connected clients / 广播同步状态给所有客户端。

    单连接 send 失败只记录日志，继续广播给其它客户端；返回 (成功数, 失败数)。
    """
    clients = list(state.connected_clients)
    if not clients:
        return (0, 0)

    message = json.dumps(build_sync_state_message(sync_enabled=state.sync_enabled))
    sent = 0
    failed = 0
    for client in clients:  # 已复制，避免迭代时集合被并发修改
        try:
            await client.send(message)
            sent += 1
        except Exception as exc:  # noqa: BLE001 - 广播失败不扩散
            failed += 1
            remote = "unknown"
            if registry is not None:
                record = registry.get(client)
                if record is not None:
                    remote = record.remote_address
            LOGGER.warning(
                "sync_state 广播失败（继续广播其它连接）: remote=%s err=%s",
                remote,
                exc,
            )
    LOGGER.debug(
        "sync_state 广播完成: sync_enabled=%s online=%d sent=%d failed=%d",
        state.sync_enabled,
        len(clients),
        sent,
        failed,
    )
    return (sent, failed)


# ============================================================
# Listener lifecycle / 监听生命周期
# ============================================================
class ListenerRebindDecider:
    """监听重绑防抖：同一「新快照」需要连续 N 次真实枚举确认才重绑。

    背景（2026-11-20 现场日志）：wifi 地址短暂消失/出现会让接口快照抖动，旧实现
    每 1s 强制枚举一次、发现集合变化立刻 close/rebind，出现连续两次断开。这里改成：
        * 只有新的「真实枚举」（refresh_generation 前进）才算一次采样；
        * 同一个候选 host 集合连续 ``required_confirmations`` 次采样一致才触发重绑；
        * 快照回到当前监听集合则清零，抖动期间不会误重绑；
        * 不变量不变：接口变化最终一定会重绑（确认次数有限）。
    """

    def __init__(
        self,
        bound_hosts: list[str],
        *,
        required_confirmations: Optional[int] = None,
    ) -> None:
        required = (
            tuning.REBIND_CONFIRMATIONS
            if required_confirmations is None
            else int(required_confirmations)
        )
        self._bound_hosts = tuple(dict.fromkeys(bound_hosts))
        self._required_confirmations = max(1, required)
        self._candidate: Optional[tuple[str, ...]] = None
        self._confirmations = 0
        self._last_generation: Optional[int] = None

    @property
    def required_confirmations(self) -> int:
        return self._required_confirmations

    @property
    def confirmations(self) -> int:
        return self._confirmations

    @property
    def candidate(self) -> Optional[tuple[str, ...]]:
        return self._candidate

    def observe(self, hosts: list[str], *, refresh_generation: int) -> bool:
        """喂入一次快照读数；返回 True 表示到达确认次数、可以重绑。"""
        if (
            self._last_generation is not None
            and refresh_generation <= self._last_generation
        ):
            # 同一份快照的重复读取（TTL 命中）不累计确认，避免缓存读数冒充多次采样。
            return False
        self._last_generation = refresh_generation

        candidate = tuple(hosts)
        if set(candidate) == set(self._bound_hosts):
            if self._candidate is not None:
                LOGGER.info(
                    "网络快照回到当前监听集合，取消重绑候选: %s",
                    ", ".join(candidate) or "none",
                )
            self._candidate = None
            self._confirmations = 0
            return False

        if candidate == self._candidate:
            self._confirmations += 1
        else:
            self._candidate = candidate
            self._confirmations = 1
            LOGGER.info(
                "检测到新的监听地址候选集合（需 %d 次新快照确认，当前 1 次）: %s -> %s",
                self._required_confirmations,
                ", ".join(self._bound_hosts) or "none",
                ", ".join(candidate) or "none",
            )
        LOGGER.debug(
            "监听重绑防抖采样: generation=%d candidate=%s confirmations=%d/%d",
            refresh_generation,
            ", ".join(candidate) or "none",
            self._confirmations,
            self._required_confirmations,
        )
        return self._confirmations >= self._required_confirmations


def build_serve_kwargs() -> dict:
    """WebSocket 协议层参数。

    只影响「死连接发现速度」，不改变 App 层 ping/pong 契约：Android 仍按自己的
    节奏发 ``{"type": "ping"}`` 并期待 ``pong``；协议层 ping 由 websockets 库自动
    应答，手机端 WebSocket 实现无需改动。
    """
    return {
        "ping_interval": tuning.WS_PING_INTERVAL_SEC,
        "ping_timeout": tuning.WS_PING_TIMEOUT_SEC,
        "close_timeout": tuning.WS_CLOSE_TIMEOUT_SEC,
        "max_size": tuning.WS_MAX_SIZE_BYTES,
    }


async def _wait_for_stable_network_change(bound_hosts: list[str]) -> Optional[list[str]]:
    """监听期间轮询共享快照，确认接口稳定变化后返回新的地址集合。"""
    decider = ListenerRebindDecider(bound_hosts)
    last_logged_version: Optional[int] = None
    while state.running:
        await asyncio.sleep(tuning.NETWORK_SNAPSHOT_POLL_SEC)
        snapshot = network_interfaces.get_interface_snapshot()
        latest_hosts = network_interfaces.get_advertised_server_ips_for_snapshot(snapshot)
        if snapshot.version != last_logged_version:
            LOGGER.info(
                "网络接口快照变化: version=%d hosts=%s",
                snapshot.version,
                ", ".join(latest_hosts) or "none",
            )
            last_logged_version = snapshot.version
        if decider.observe(latest_hosts, refresh_generation=snapshot.refresh_generation):
            LOGGER.info(
                "WebSocket 监听接口稳定变化（连续 %d 次新采样一致）: %s -> %s",
                decider.confirmations,
                ", ".join(bound_hosts) or "none",
                ", ".join(latest_hosts) or "none",
            )
            return latest_hosts
    return None


async def start_server(
    *,
    services_factory: Callable[[], ClientServices],
    registry: ClientRegistry,
) -> None:
    """Start the WebSocket server / 启动 WebSocket 服务器。"""
    state.server_loop = asyncio.get_running_loop()
    serve_kwargs = build_serve_kwargs()
    LOGGER.info(
        "WebSocket server 参数: ping_interval=%ss ping_timeout=%ss close_timeout=%ss max_size=%sB",
        serve_kwargs["ping_interval"],
        serve_kwargs["ping_timeout"],
        serve_kwargs["close_timeout"],
        serve_kwargs["max_size"],
    )
    handler = functools.partial(
        handle_client,
        services_factory=services_factory,
        registry=registry,
    )
    while state.running:
        bind_hosts = network_interfaces.get_advertised_server_ips(refresh=True)
        servers = []
        bound_hosts = []
        try:
            for bind_host in bind_hosts:
                try:
                    server = await serve(handler, bind_host, state.ws_port, **serve_kwargs)
                except OSError as e:
                    LOGGER.error(f"WebSocket 绑定 {bind_host}:{state.ws_port} 失败: {e}")
                    continue
                servers.append(server)
                bound_hosts.append(bind_host)
                print(f"WebSocket server started at ws://{bind_host}:{state.ws_port}")

            if not servers:
                network_interfaces.set_bound_server_ips([])
                LOGGER.error(
                    "没有可监听的物理网络接口，WebSocket server 暂停重试。"
                )
                await asyncio.sleep(tuning.SERVER_RETRY_DELAY_SEC)
                continue

            network_interfaces.set_bound_server_ips(bound_hosts)
            LOGGER.info(
                "WebSocket server listening on physical interfaces: "
                f"{', '.join(f'{host}:{state.ws_port}' for host in bound_hosts)}"
            )
            await _wait_for_stable_network_change(bound_hosts)
        except Exception as e:
            print(f"Server error: {e}")
            LOGGER.error(f"WebSocket server error: {e}")
            await asyncio.sleep(tuning.SERVER_RETRY_DELAY_SEC)
        finally:
            for server in servers:
                server.close()
            if servers:
                LOGGER.info(
                    "WebSocket server closing listeners: "
                    f"{', '.join(f'{host}:{state.ws_port}' for host in bound_hosts)}"
                )
                await asyncio.gather(
                    *(server.wait_closed() for server in servers),
                    return_exceptions=True,
                )
            network_interfaces.set_bound_server_ips([])


def run_server(
    *,
    services_factory: Callable[[], ClientServices],
    registry: ClientRegistry,
) -> None:
    """Run the server in a separate thread / 在单独线程中运行服务器。"""
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.run_until_complete(
        start_server(services_factory=services_factory, registry=registry)
    )
