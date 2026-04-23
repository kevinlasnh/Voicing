"""
Voicing - PC Application
语音编程 - 电脑端应用

A system tray application that receives text from phone and types it at cursor position.
系统托盘应用，接收手机发送的文本并在光标处输入。
"""

import asyncio
import ipaddress
import json
import logging
import os
import re
import socket
import subprocess
import sys
import threading
from datetime import datetime
from pathlib import Path
from typing import Optional

# PyQt5 for modern tray menu
from PyQt5.QtWidgets import (
    QApplication, QSystemTrayIcon, QMessageBox,
    QWidget, QVBoxLayout, QHBoxLayout, QLabel,
    QGraphicsDropShadowEffect,
)
from PyQt5.QtCore import Qt, QTimer, pyqtSignal
from PyQt5.QtGui import QIcon, QPixmap, QPainter, QColor, QCursor

# Third-party imports
import websockets
from websockets.server import serve
from PIL import Image, ImageDraw
import pyperclip

from network_recovery import build_udp_broadcast_payload, refresh_server_interfaces
from platform_autostart import is_startup_enabled, set_startup_enabled
from platform_instance import check_single_instance, show_already_running_message
from platform_keyboard import paste_from_clipboard, press_enter
from platform_utils import (
    ensure_runtime_supported,
    get_default_server_ip,
    get_known_hotspot_prefixes,
    get_log_dir,
    get_native_font_family,
    get_platform,
    get_preferred_hotspot_prefixes,
    open_file_in_default_app,
    open_file_in_text_editor,
)
from voicing_protocol import (
    TYPE_PING,
    TYPE_TEXT,
    WEBSOCKET_PORT,
    TEXT_SEND_MODE_COMMIT,
    TEXT_SEND_MODE_SUBMIT,
    UDP_BROADCAST_PORT,
    build_ack_message,
    build_connected_message,
    build_pong_message,
    build_sync_disabled_message,
    build_sync_state_message,
)

# ============================================================
# Configuration / 配置
# ============================================================
APP_NAME = "Voicing"
APP_VERSION = "2.7.1"
WS_PORT = WEBSOCKET_PORT      # WebSocket port
AUTO_ENTER_SETTLE_DELAY_SEC = 0.15
NATIVE_FONT_FAMILY = get_native_font_family()


# ============================================================
# Global State / 全局状态
# ============================================================
class AppState:
    """Application state management / 应用状态管理"""
    def __init__(self):
        self.sync_enabled = True
        self.running = True
        self.server = None
        self.tray_icon = None
        self.ws_port = WS_PORT
        self.connected_clients = set()
        self.blink_state = False  # For icon blinking / 图标闪烁状态
        self.blink_timer: Optional[threading.Timer] = None
        self.log_file = None  # 日志文件路径
        self.lock = threading.Lock()  # 保护共享状态
        self.shutdown_event = threading.Event()  # 用于优雅退出

state = AppState()


# ============================================================
# Logging Setup / 日志配置
# ============================================================
def setup_logging():
    """设置日志系统"""
    # 日志文件保存在用户数据目录
    log_dir = get_log_dir()
    log_dir.mkdir(parents=True, exist_ok=True)
    
    # 使用日期作为文件名
    from datetime import datetime
    log_file = log_dir / f"voice_coding_{datetime.now().strftime('%Y%m%d')}.log"
    state.log_file = log_file
    
    # 配置 logging
    import logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s [%(levelname)s] %(message)s',
        datefmt='%H:%M:%S',
        handlers=[
            logging.FileHandler(log_file, encoding='utf-8'),
            logging.StreamHandler(sys.stdout)  # 同时输出到控制台
        ]
    )
    logging.info(f"=== Voicing 启动 ===")
    logging.info(f"日志文件: {log_file}")


# ============================================================
# Network Configuration / 网络配置
# ============================================================
# Platform discovery default IP / 平台默认发现 IP
DEFAULT_SERVER_IP = get_default_server_ip()
# UDP broadcast configuration / UDP 广播配置
UDP_BROADCAST_INTERVAL = 2  # 广播间隔（秒）


def get_hotspot_ip() -> str:
    """
    Get the actual hotspot IP address / 获取热点的实际 IP 地址
    
    Windows Mobile Hotspot typically uses 192.168.137.1, but this function
    will try to detect the actual IP by looking for the hotspot adapter.
    """
    try:
        all_local_ips = get_all_local_ips()
        for prefixes in (get_preferred_hotspot_prefixes(), get_known_hotspot_prefixes()):
            for adapter_ip in all_local_ips:
                if any(adapter_ip.startswith(prefix) for prefix in prefixes):
                    return adapter_ip

        if all_local_ips:
            return all_local_ips[0]

        return DEFAULT_SERVER_IP

    except Exception as e:
        logging.warning(f"Error detecting hotspot IP: {e}")
        return DEFAULT_SERVER_IP


def get_all_local_ips() -> list:
    """Get all local IP addresses / 获取所有本地 IP 地址"""
    discovered_ips = [ip for ip, _ in get_all_local_interfaces()]
    if discovered_ips:
        return discovered_ips

    fallback_ips = []
    seen = set()

    def add_fallback_ip(ip: str) -> None:
        if _is_discoverable_private_ip(ip, require_private=True) and ip not in seen:
            seen.add(ip)
            fallback_ips.append(ip)

    try:
        hostname = socket.gethostname()
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET):
            add_fallback_ip(info[4][0])
    except Exception:
        pass

    return _sort_ip_addresses(fallback_ips)


def extract_command_ips(platform_name: str, command_output: str) -> list[str]:
    if platform_name == "windows":
        return [
            line.strip()
            for line in command_output.splitlines()
            if re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}", line.strip())
        ]

    if platform_name == "darwin":
        return [
            match.group(1)
            for match in re.finditer(r"\binet\s+(\d{1,3}(?:\.\d{1,3}){3})\b", command_output)
        ]

    if platform_name == "linux":
        return [
            match.group(1)
            for match in re.finditer(r"\binet\s+(\d{1,3}(?:\.\d{1,3}){3})/\d+\b", command_output)
        ]

    return []


def get_all_local_interfaces() -> list[tuple[str, int]]:
    """Return broadcast-capable private IPv4 interfaces as (ip, prefix_length)."""
    platform_name = get_platform()
    interface_discovery_commands = {
        "windows": [
            "powershell",
            "-NoProfile",
            "-Command",
            (
                "Get-NetIPAddress -AddressFamily IPv4 | "
                "Select-Object IPAddress, PrefixLength, InterfaceAlias, AddressState, SkipAsSource | "
                "ConvertTo-Json -Compress"
            ),
        ],
        "darwin": ["ifconfig"],
        "linux": ["ip", "-j", "-4", "addr", "show", "up", "scope", "global"],
    }
    command = interface_discovery_commands.get(platform_name)
    if not command:
        return []

    creationflags = 0
    if platform_name == "windows":
        creationflags = getattr(subprocess, "CREATE_NO_WINDOW", 0)

    try:
        result = subprocess.run(
            command,
            capture_output=True,
            text=True,
            creationflags=creationflags,
            check=False,
        )
    except Exception as exc:
        logging.debug(f"网络接口探测命令执行失败: {exc}")
        return []

    if result.returncode != 0 and not result.stdout.strip():
        logging.debug(f"网络接口探测命令返回非零退出码: {result.returncode}")
        return []

    return _sort_interfaces(extract_command_interfaces(platform_name, result.stdout))


def extract_command_interfaces(platform_name: str, command_output: str) -> list[tuple[str, int]]:
    command_output = command_output.strip()
    if not command_output:
        return []

    interfaces: list[tuple[str, int]] = []
    seen: set[tuple[str, int]] = set()

    def add_interface(ip: str, prefix_length: int) -> None:
        try:
            normalized_prefix = int(prefix_length)
        except (TypeError, ValueError):
            return
        candidate = (ip, normalized_prefix)
        if candidate in seen:
            return
        if not _is_discoverable_private_ip(ip, normalized_prefix):
            return
        seen.add(candidate)
        interfaces.append(candidate)

    if platform_name == "windows":
        try:
            records = json.loads(command_output)
            if isinstance(records, dict):
                records = [records]
            if isinstance(records, list):
                for record in records:
                    if not isinstance(record, dict):
                        continue
                    address_state = record.get("AddressState")
                    if address_state not in (None, "Preferred", 4):
                        continue
                    if record.get("SkipAsSource") is True:
                        continue
                    add_interface(record.get("IPAddress", ""), record.get("PrefixLength"))
                return interfaces
        except json.JSONDecodeError:
            pass

        for ip, prefix_length in re.findall(
            r"(\d{1,3}(?:\.\d{1,3}){3})\s+(\d{1,2})",
            command_output,
        ):
            add_interface(ip, int(prefix_length))
        return interfaces

    if platform_name == "linux":
        try:
            records = json.loads(command_output)
            if not isinstance(records, list):
                return []
            for record in records:
                if not isinstance(record, dict):
                    continue
                for addr_info in record.get("addr_info", []):
                    if not isinstance(addr_info, dict):
                        continue
                    if addr_info.get("family") != "inet":
                        continue
                    if addr_info.get("scope") != "global":
                        continue
                    if "broadcast" not in addr_info:
                        continue
                    add_interface(addr_info.get("local", ""), addr_info.get("prefixlen"))
        except json.JSONDecodeError:
            pass
        return interfaces

    if platform_name == "darwin":
        supports_broadcast = False
        for raw_line in command_output.splitlines():
            line = raw_line.rstrip()
            header_match = re.match(r"^([^\s:]+):\s+flags=\d+<([^>]*)>", line)
            if header_match:
                flags = {flag.strip().upper() for flag in header_match.group(2).split(",")}
                supports_broadcast = "UP" in flags and "BROADCAST" in flags and "POINTOPOINT" not in flags
                continue

            if not supports_broadcast:
                continue

            match = re.search(
                r"\binet\s+(\d{1,3}(?:\.\d{1,3}){3})\s+netmask\s+(0x[0-9a-fA-F]+)\b",
                line,
            )
            if not match:
                continue
            prefix_length = bin(int(match.group(2), 16)).count("1")
            add_interface(match.group(1), prefix_length)
        return interfaces

    return []


def calculate_broadcast_addresses(
    interfaces: list[tuple[str, int]],
) -> list[tuple[str, str]]:
    """Convert interface prefixes to directed broadcast targets."""
    result = []
    seen = set()
    for ip, prefix_length in interfaces:
        try:
            network = ipaddress.IPv4Network(f"{ip}/{prefix_length}", strict=False)
        except ValueError:
            continue
        candidate = (ip, str(network.broadcast_address))
        if candidate in seen:
            continue
        seen.add(candidate)
        result.append(candidate)
    return result


def _is_discoverable_private_ip(
    ip: str,
    prefix_length: Optional[int] = None,
    *,
    require_private: bool = True,
) -> bool:
    try:
        address = ipaddress.IPv4Address(ip)
    except ipaddress.AddressValueError:
        return False

    if (
        address.is_loopback
        or address.is_link_local
        or address.is_multicast
        or address.is_unspecified
    ):
        return False

    if require_private and not address.is_private:
        return False

    if prefix_length is None:
        return True

    return 1 <= prefix_length <= 30


def _sort_ip_addresses(ips: list[str]) -> list[str]:
    return sorted(ips, key=_ip_sort_key)


def _sort_interfaces(interfaces: list[tuple[str, int]]) -> list[tuple[str, int]]:
    return sorted(interfaces, key=lambda item: (_ip_sort_key(item[0]), item[1]))


def _ip_sort_key(ip: str) -> tuple[int, str]:
    if any(ip.startswith(prefix) for prefix in get_preferred_hotspot_prefixes()):
        return (0, ip)
    if any(ip.startswith(prefix) for prefix in get_known_hotspot_prefixes()):
        return (1, ip)
    return (2, ip)


def get_primary_server_ip() -> str:
    if SERVER_INTERFACES:
        return SERVER_INTERFACES[0][0]
    return get_hotspot_ip()


def log_detected_network_interfaces(interfaces: list[tuple[str, int]]) -> None:
    if not interfaces:
        logging.warning("未检测到可用于定向广播的私有 IPv4 接口，将回退到 <broadcast> 全局广播。")
        logging.info(f"回退广播 IP: {get_hotspot_ip()}")
        return

    logging.info(f"检测到 {len(interfaces)} 个可广播网络接口:")
    for ip, prefix_length in interfaces:
        label = "热点" if any(ip.startswith(prefix) for prefix in get_known_hotspot_prefixes()) else "局域网"
        logging.info(f"  - {ip}/{prefix_length} ({label})")


# ============================================================
# UDP Broadcast for Auto-Discovery / UDP 广播自动发现
# ============================================================
def start_udp_broadcast():
    """
    Start UDP broadcast to let mobile clients discover this server.
    启动 UDP 广播让移动客户端自动发现此服务器。
    """
    global SERVER_INTERFACES

    broadcast_socket = None
    try:
        broadcast_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        broadcast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        broadcast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        logging.info(
            f"UDP 广播服务已启动，端口: {UDP_BROADCAST_PORT}，活跃接口: {len(SERVER_INTERFACES)} 个"
        )

        while state.running:
            try:
                current_interfaces = calculate_broadcast_addresses(get_all_local_interfaces())
                current_interfaces, interfaces_changed = refresh_server_interfaces(
                    SERVER_INTERFACES,
                    current_interfaces,
                )
                if interfaces_changed:
                    old_interfaces = ", ".join(f"{ip}->{broadcast}" for ip, broadcast in SERVER_INTERFACES) or "none"
                    new_interfaces = ", ".join(f"{ip}->{broadcast}" for ip, broadcast in current_interfaces) or "none"
                    logging.info(f"网络接口更新: {old_interfaces} -> {new_interfaces}")
                SERVER_INTERFACES = current_interfaces

                if current_interfaces:
                    for server_ip, broadcast_addr in current_interfaces:
                        broadcast_data = build_udp_broadcast_payload(
                            server_ip,
                            state.ws_port,
                            socket.gethostname(),
                        )
                        broadcast_socket.sendto(
                            broadcast_data,
                            (broadcast_addr, UDP_BROADCAST_PORT),
                        )
                        logging.debug(f"发送 UDP 广播: {server_ip} -> {broadcast_addr}:{UDP_BROADCAST_PORT}")
                else:
                    fallback_ip = get_hotspot_ip()
                    broadcast_data = build_udp_broadcast_payload(
                        fallback_ip,
                        state.ws_port,
                        socket.gethostname(),
                    )
                    broadcast_socket.sendto(
                        broadcast_data,
                        ("<broadcast>", UDP_BROADCAST_PORT),
                    )
                    logging.debug(f"发送 UDP 广播回退: {fallback_ip} -> <broadcast>:{UDP_BROADCAST_PORT}")
            except Exception as e:
                logging.debug(f"UDP 广播发送失败: {e}")

            # Wait before next broadcast / 等待下次广播
            if state.shutdown_event.wait(UDP_BROADCAST_INTERVAL):
                break  # shutdown_event 被 set，退出循环

    except Exception as e:
        logging.error(f"UDP 广播服务错误: {e}")
    finally:
        if broadcast_socket:
            broadcast_socket.close()


# Will be set at runtime / 运行时设置
SERVER_INTERFACES: list[tuple[str, str]] = []


# ============================================================
# Text Input / 文本输入
# ============================================================
def type_text(text: str, auto_enter: bool = False):
    """
    Type text at current cursor position.
    在当前光标位置输入文本。

    Uses clipboard paste for cross-platform Unicode input.

    Args:
        text: Text to type
        auto_enter: If True, press Enter after typing
    """
    if not text or not state.sync_enabled:
        return

    try:
        ensure_runtime_supported()

        # Save current clipboard
        try:
            old_clipboard = pyperclip.paste()
        except Exception:
            old_clipboard = ""

        # Copy new text and paste
        pyperclip.copy(text)
        paste_from_clipboard()

        # Auto press Enter if enabled
        if auto_enter:
            # Give the target app time to process Ctrl+V before sending Enter.
            # Some chat inputs mis-handle an immediate Enter as Ctrl+Enter/newline.
            threading.Event().wait(AUTO_ENTER_SETTLE_DELAY_SEC)
            press_enter()

        # Small delay then restore clipboard
        threading.Event().wait(0.1)
        try:
            pyperclip.copy(old_clipboard)
        except Exception:
            pass

    except Exception as e:
        logging.error(f"Error typing text: {e}")


# ============================================================
# Reserved for future features / 保留给未来功能
# ============================================================


# ============================================================
# WebSocket Server / WebSocket 服务器
# ============================================================
async def handle_client(websocket):
    """Handle incoming WebSocket connections / 处理传入的WebSocket连接"""
    client_addr = websocket.remote_address
    with state.lock:
        state.connected_clients.add(websocket)
    print(f"Client connected: {client_addr}")

    try:
        # Get computer name for identification
        computer_name = socket.gethostname()

        # Send welcome message with current sync state and computer name
        await websocket.send(json.dumps(build_connected_message(
            sync_enabled=state.sync_enabled,
            computer_name=computer_name,
        )))

        async for message in websocket:
            try:
                data = json.loads(message)
                msg_type = data.get("type", "")

                if msg_type == TYPE_TEXT:
                    # Check if sync is enabled
                    if not state.sync_enabled:
                        await websocket.send(json.dumps(build_sync_disabled_message()))
                        continue

                    text = data.get("content", "")
                    send_mode = data.get("send_mode", TEXT_SEND_MODE_SUBMIT)
                    auto_enter = data.get("auto_enter", False) and send_mode == TEXT_SEND_MODE_SUBMIT
                    if send_mode == TEXT_SEND_MODE_COMMIT:
                        if data.get("auto_enter", False):
                            await asyncio.to_thread(press_enter)
                        await websocket.send(json.dumps(build_ack_message(
                            clear_input=False,
                        )))
                    elif text:
                        # Type the received text (run in thread to avoid blocking event loop)
                        await asyncio.to_thread(type_text, text, auto_enter)
                        # Send acknowledgment
                        await websocket.send(json.dumps(build_ack_message(
                            clear_input=send_mode == TEXT_SEND_MODE_SUBMIT,
                        )))

                elif msg_type == TYPE_PING:
                    # Respond with pong and current sync state
                    await websocket.send(json.dumps(build_pong_message(
                        sync_enabled=state.sync_enabled,
                    )))

            except json.JSONDecodeError:
                # If not JSON, treat as plain text
                if message.strip() and state.sync_enabled:
                    await asyncio.to_thread(type_text, message)
                    
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        with state.lock:
            state.connected_clients.discard(websocket)
        print(f"Client disconnected: {client_addr}")


async def broadcast_sync_state():
    """Broadcast sync state to all connected clients / 广播同步状态给所有客户端"""
    if not state.connected_clients:
        return
    
    message = json.dumps(build_sync_state_message(sync_enabled=state.sync_enabled))
    
    for client in state.connected_clients.copy():  # copy() 避免迭代时修改
        try:
            await client.send(message)
        except Exception:
            pass


async def start_server():
    """Start the WebSocket server / 启动WebSocket服务器"""
    try:
        async with serve(handle_client, "0.0.0.0", state.ws_port):
            print(f"WebSocket server started at ws://{get_primary_server_ip()}:{state.ws_port}")
            # Keep server running
            while state.running:
                await asyncio.sleep(1)
    except Exception as e:
        print(f"Server error: {e}")


def run_server():
    """Run the server in a separate thread / 在单独线程中运行服务器"""
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    loop.run_until_complete(start_server())


# ============================================================
# PyQt5 Modern Tray Menu / PyQt5 现代托盘菜单
# ============================================================

class MenuItemWidget(QWidget):
    """单个菜单项 - Windows 11 Fluent Design 风格"""

    clicked = pyqtSignal()

    def __init__(self, icon_text, text, has_toggle=False, is_checked=False, parent=None):
        super().__init__(parent)
        self.has_toggle = has_toggle
        self.is_checked = is_checked
        self._hovered = False
        self._pressed = False
        self.setFixedHeight(36)  # Windows 11 标准高度
        self.setMouseTracking(True)
        self.setCursor(Qt.PointingHandCursor)

        self.setup_ui(icon_text, text, has_toggle, is_checked)

    def setup_ui(self, icon_text, text, has_toggle, is_checked):
        """设置 UI"""
        layout = QHBoxLayout(self)
        layout.setContentsMargins(12, 0, 12, 0)  # 更宽的水平内边距
        layout.setSpacing(10)

        # 图标 - 使用白色
        self.icon_label = QLabel(icon_text)
        self.icon_label.setFixedWidth(20)
        self.icon_label.setStyleSheet("font-size: 14px; background: transparent; color: #FFFFFF;")
        self.icon_label.setAttribute(Qt.WA_TransparentForMouseEvents)

        # 文字 - 使用 Segoe UI 字体（Windows 11 默认字体）
        self.text_label = QLabel(text)
        self.text_label.setStyleSheet("""
            QLabel {
                color: #FFFFFF;
                font-family: %s;
                font-size: 13px;
                font-weight: 400;
                background: transparent;
            }
        """ % NATIVE_FONT_FAMILY)
        self.text_label.setAlignment(Qt.AlignLeft | Qt.AlignVCenter)
        self.text_label.setAttribute(Qt.WA_TransparentForMouseEvents)

        layout.addWidget(self.icon_label)
        layout.addWidget(self.text_label)
        layout.addStretch()

        # 开关项 - 显示简洁的状态
        if has_toggle:
            self.status_label = QLabel()
            self.status_label.setFixedWidth(24)
            self.status_label.setAttribute(Qt.WA_TransparentForMouseEvents)
            self.update_toggle_status(is_checked)
            layout.addWidget(self.status_label)

    def paintEvent(self, event):
        """自定义绘制背景 - Windows 11 风格"""
        from PyQt5.QtGui import QPainter, QColor
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing)

        # 绘制圆角矩形背景
        rect = self.rect().adjusted(4, 2, -4, -2)  # 内缩，留出边距

        if self._pressed:
            # 按下状态 - 更亮的背景
            painter.setBrush(QColor(255, 255, 255, 25))  # 白色 10% 透明度
        elif self._hovered:
            # 悬停状态
            painter.setBrush(QColor(255, 255, 255, 15))  # 白色 6% 透明度
        else:
            painter.setBrush(Qt.transparent)

        painter.setPen(Qt.NoPen)
        painter.drawRoundedRect(rect, 4, 4)  # 4px 圆角

    def enterEvent(self, event):
        """鼠标进入 - 显示高亮"""
        self._hovered = True
        self.update()
        super().enterEvent(event)

    def leaveEvent(self, event):
        """鼠标离开 - 恢复正常"""
        self._hovered = False
        self.update()
        super().leaveEvent(event)

    def update_toggle_status(self, checked):
        """更新开关状态 - 使用现代化的开关指示器"""
        self.is_checked = checked
        if checked:
            self.status_label.setText("✓")
            self.status_label.setStyleSheet("""
                QLabel {
                    color: #60CDFF;
                    font-family: %s;
                    font-size: 14px;
                    font-weight: bold;
                    background: transparent;
                }
            """ % NATIVE_FONT_FAMILY)
        else:
            self.status_label.setText("")
            self.status_label.setStyleSheet("background: transparent;")

    def mousePressEvent(self, event):
        """鼠标按下 - 显示按压反馈"""
        self._pressed = True
        self.update()
        super().mousePressEvent(event)

    def mouseReleaseEvent(self, event):
        """鼠标释放 - 恢复状态并触发点击"""
        self._pressed = False
        self.update()
        if self.rect().contains(event.pos()):
            self.clicked.emit()
        super().mouseReleaseEvent(event)


class ModernMenuWidget(QWidget):
    """Windows 11 Fluent Design 风格的自定义菜单窗口"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.Popup | Qt.NoDropShadowWindowHint)
        self.setAttribute(Qt.WA_TranslucentBackground)

        # 动画相关
        self.animation_step = 0
        self.animation_max_steps = 10  # 约 160ms - 更快更流畅
        self.animation_timer = QTimer()
        self.animation_timer.timeout.connect(self.update_animation)

        self.setup_ui()

    def setup_ui(self):
        """设置 UI - Windows 11 Fluent Design"""
        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 8, 8, 8)  # 阴影边距
        layout.setSpacing(0)

        # 主容器 - 使用深色半透明背景
        self.container = QWidget()
        self.container.setObjectName("menuContainer")
        self.container.setStyleSheet("""
            #menuContainer {
                background-color: rgba(32, 32, 32, 245);
                border: 1px solid rgba(255, 255, 255, 0.08);
                border-radius: 8px;
            }
        """)
        container_layout = QVBoxLayout(self.container)
        container_layout.setContentsMargins(4, 6, 4, 6)  # 内边距
        container_layout.setSpacing(4)  # 项间距（4px 网格）

        # 同步输入
        self.sync_btn = MenuItemWidget("📡", "同步输入", has_toggle=True, is_checked=True)
        self.sync_btn.clicked.connect(self.toggle_sync)
        container_layout.addWidget(self.sync_btn)

        # 开机自启
        self.startup_btn = MenuItemWidget("🚀", "开机自启", has_toggle=True, is_checked=False)
        self.startup_btn.clicked.connect(self.toggle_startup)
        container_layout.addWidget(self.startup_btn)

        # 分隔线
        separator1 = QWidget()
        separator1.setFixedHeight(1)
        separator1.setStyleSheet("background-color: rgba(255, 255, 255, 0.08); margin: 4px 8px;")
        container_layout.addWidget(separator1)

        # 打开日志
        log_btn = MenuItemWidget("📋", "打开日志")
        log_btn.clicked.connect(self.open_log)
        container_layout.addWidget(log_btn)

        # 分隔线
        separator2 = QWidget()
        separator2.setFixedHeight(1)
        separator2.setStyleSheet("background-color: rgba(255, 255, 255, 0.08); margin: 4px 8px;")
        container_layout.addWidget(separator2)

        # 退出应用
        quit_btn = MenuItemWidget("🚪", "退出应用")
        quit_btn.clicked.connect(self.quit_app)
        container_layout.addWidget(quit_btn)

        layout.addWidget(self.container)

        # 设置阴影
        self.set_shadow_effect()

        # 更新初始状态
        QTimer.singleShot(0, self.update_state)

    def set_shadow_effect(self):
        """设置阴影效果 - Windows 11 风格的柔和阴影"""
        shadow = QGraphicsDropShadowEffect()
        shadow.setBlurRadius(24)
        shadow.setColor(QColor(0, 0, 0, 100))
        shadow.setOffset(0, 4)
        self.container.setGraphicsEffect(shadow)

    def show_at_position(self, tray_pos):
        """在指定位置显示菜单，视觉左下角对齐鼠标点击位置"""
        self.adjustSize()
        menu_width = self.width()
        menu_height = self.height()
        screen = QApplication.primaryScreen()
        available_geometry = screen.availableGeometry() if screen else None

        shadow = self.layout().contentsMargins()
        x = tray_pos.x() - shadow.left()
        if get_platform() == "windows":
            target_y = tray_pos.y() - menu_height + shadow.bottom()
            animation_start_y = target_y + 16
        else:
            target_y = tray_pos.y() - shadow.top()
            animation_start_y = target_y - 16

        if available_geometry:
            screen_geometry = screen.geometry() if screen else available_geometry
            min_x = screen_geometry.left() + 8
            max_x = screen_geometry.right() - menu_width - 8
            x = max(min_x, min(x, max_x))
            if get_platform() == "windows":
                min_y = screen_geometry.top() + 8
                max_y = screen_geometry.bottom() - menu_height - 8
            else:
                min_y = available_geometry.top() + 8
                max_y = available_geometry.bottom() - menu_height - 8
            target_y = max(min_y, min(target_y, max_y))
            animation_start_y = max(min_y, min(animation_start_y, max_y))

        self.target_y = target_y
        self.animation_start_y = animation_start_y
        self.move(x, target_y)

        self.animation_step = 0
        self.move(x, animation_start_y)
        self.setWindowOpacity(0.0)
        self.show()
        self.animation_timer.start(16)  # 60fps

    def update_animation(self):
        """更新滑入动画"""
        self.animation_step += 1

        if self.animation_step >= self.animation_max_steps:
            # 动画结束
            self.animation_timer.stop()
            self.move(self.pos().x(), self.target_y)
            self.setWindowOpacity(1.0)
        else:
            # 缓动
            progress = self.animation_step / self.animation_max_steps
            eased = 1 - pow(1 - progress, 2)  # easeOutQuad

            current_y = self.animation_start_y + (self.target_y - self.animation_start_y) * eased
            self.move(self.pos().x(), int(current_y))

            # 淡入
            self.setWindowOpacity(min(1.0, eased * 1.5))

    def update_state(self):
        """更新菜单状态"""
        self.sync_btn.update_toggle_status(state.sync_enabled)
        self.startup_btn.update_toggle_status(is_startup_enabled())

    def toggle_sync(self):
        """切换同步状态"""
        new_state = not self.sync_btn.is_checked
        state.sync_enabled = new_state
        self.sync_btn.update_toggle_status(new_state)
        # 更新托盘图标
        if state.tray_icon:
            update_tray_icon_pyqt(state.tray_icon)
        self.close_with_animation()
        # 广播同步状态
        def send_sync_state():
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            loop.run_until_complete(broadcast_sync_state())
            loop.close()
        threading.Thread(target=send_sync_state, daemon=True).start()

    def toggle_startup(self):
        """切换开机自启"""
        new_state = not self.startup_btn.is_checked
        set_startup_enabled(new_state)
        self.startup_btn.update_toggle_status(new_state)
        self.close_with_animation()

    def open_log(self):
        """打开日志文件"""
        self.close_with_animation()
        if state.log_file and state.log_file.exists():
            open_file_in_text_editor(state.log_file)
        else:
            log_dir = get_log_dir()
            log_dir.mkdir(parents=True, exist_ok=True)
            open_file_in_default_app(log_dir)

    def quit_app(self):
        """退出应用"""
        state.running = False
        state.shutdown_event.set()
        QApplication.quit()

    def close_with_animation(self):
        """关闭动画"""
        self.animation_timer.stop()
        self.close()

    def keyPressEvent(self, event):
        """键盘事件 - Escape 关闭菜单"""
        if event.key() == Qt.Key_Escape:
            self.close_with_animation()
        else:
            super().keyPressEvent(event)

    def mousePressEvent(self, event):
        """Popup 模式下，点击菜单外部的事件会发到这里。
        若点击落在托盘图标矩形内 → 关闭自身并在新位置立刻重开（修复"连续右键第二次不弹"）。
        """
        # Qt.Popup 行为：点击外部时坐标是相对于 Popup 窗口的，转全局坐标再判断
        global_pos = event.globalPos() if hasattr(event, 'globalPos') else self.mapToGlobal(event.pos())
        if event.button() == Qt.RightButton and state.tray_icon is not None:
            tray_rect = state.tray_icon.geometry()
            if tray_rect.isValid() and tray_rect.contains(global_pos):
                # 关掉自己，延迟一下在新位置重开
                self.close_with_animation()
                QTimer.singleShot(0, lambda: state.tray_icon.show_custom_menu())
                event.accept()
                return
        super().mousePressEvent(event)


class ModernTrayIcon(QSystemTrayIcon):
    """现代托盘图标"""

    def __init__(self, parent=None):
        super().__init__(parent)
        # 预先缓存图标
        self._icon_cache = {}
        self._init_icon_cache()
        # 预先创建菜单（避免首次打开慢）
        self.menu_widget = ModernMenuWidget()
        # 预热渲染：强制 Qt 提前编译 stylesheet 和计算布局
        self.menu_widget.move(-10000, -10000)
        self.menu_widget.show()
        QTimer.singleShot(50, self.menu_widget.hide)
        self.setup_icon()
        self.setup_menu()
        # 设置悬停提示
        self.setToolTip("Voicing")

    def _init_icon_cache(self):
        """预先生成并缓存所有状态的图标"""
        import io
        size = 256

        # 生成基础圆形图标
        bg_color = (26, 26, 46, 255)  # #1A1A2E
        base = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(base)
        draw.ellipse([0, 0, size-1, size-1], fill=bg_color)
        original = load_base_icon(size)
        base = Image.alpha_composite(base, original)
        mask = Image.new('L', (size, size), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, size-1, size-1], fill=255)
        base.putalpha(mask)

        # 缓存：正常状态
        self._icon_cache['normal'] = self._pil_to_qicon(base)

        # 缓存：暗淡状态（闪烁用）
        dim = base.copy()
        alpha = dim.split()[3]
        alpha = alpha.point(lambda x: int(x * 0.4))
        dim.putalpha(alpha)
        self._icon_cache['dim'] = self._pil_to_qicon(dim)

        # 缓存：灰度状态（暂停用）
        r, g, b, a = base.split()
        gray = base.convert('L')
        paused = Image.merge('RGBA', (gray, gray, gray, a))
        self._icon_cache['paused'] = self._pil_to_qicon(paused)

    def _pil_to_qicon(self, pil_image):
        """PIL Image 转 QIcon"""
        import io
        byte_data = io.BytesIO()
        pil_image.save(byte_data, format='PNG')
        byte_data.seek(0)
        qpix = QPixmap()
        qpix.loadFromData(byte_data.getvalue())
        return QIcon(qpix)

    def setup_icon(self):
        """设置图标 - 使用新的麦克风+声波图标"""
        import io
        
        # 加载基础图标
        icon = load_base_icon(32)
        
        # 转换为 QPixmap
        byte_data = io.BytesIO()
        icon.save(byte_data, format='PNG')
        byte_data.seek(0)
        qpix = QPixmap()
        qpix.loadFromData(byte_data.getvalue())

        self.setIcon(QIcon(qpix))

    def setup_menu(self):
        """设置菜单"""
        # 不使用 QMenu，而是自定义菜单
        self.activated.connect(self.on_tray_activated)

    def on_tray_activated(self, reason):
        """托盘图标激活事件 - 仅响应右键"""
        if reason == QSystemTrayIcon.Context:
            self.show_custom_menu()

    def show_custom_menu(self):
        """显示自定义菜单"""
        # 更新状态
        self.menu_widget.update_state()

        # 获取托盘图标位置并显示菜单（带动画）
        pos = QCursor.pos()
        self.menu_widget.show_at_position(pos)

    def update_icon(self, status, dim=False):
        """更新图标状态 - 使用缓存的图标（快速切换）

        Args:
            status: 未使用，保留兼容
            dim: 是否为暗淡状态（用于闪烁效果）
        """
        if not state.sync_enabled:
            # 暂停状态
            self.setIcon(self._icon_cache['paused'])
        elif len(state.connected_clients) == 0 and dim:
            # 等待连接 + 暗淡状态
            self.setIcon(self._icon_cache['dim'])
        else:
            # 正常状态（已连接或等待连接的亮状态）
            self.setIcon(self._icon_cache['normal'])


# ============================================================
# System Tray / 系统托盘 (保留兼容函数)
# ============================================================

def get_base_icon_path() -> str:
    """获取基础图标路径"""
    if getattr(sys, 'frozen', False):
        # 打包后的路径
        base_path = sys._MEIPASS
    else:
        # 开发环境路径
        base_path = os.path.dirname(os.path.abspath(__file__))
    return os.path.join(base_path, 'assets', 'icon_1024.png')


def load_base_icon(size: int = 64) -> Image.Image:
    """加载并缩放基础图标"""
    icon_path = get_base_icon_path()
    try:
        icon = Image.open(icon_path)
        icon = icon.convert('RGBA')
        icon = icon.resize((size, size), Image.Resampling.LANCZOS)
        return icon
    except Exception as e:
        logging.warning(f"无法加载图标 {icon_path}: {e}，使用备用图标")
        # 备用图标：简单的圆形
        fallback = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(fallback)
        draw.ellipse([4, 4, size-4, size-4], fill='#2196F3')
        return fallback


def run_tray():
    """Run the system tray application with PyQt5 / 使用PyQt5运行系统托盘应用"""
    # 创建 QApplication（如果不存在）
    if QApplication.instance() is None:
        app = QApplication(sys.argv)
    else:
        app = QApplication.instance()

    app.setQuitOnLastWindowClosed(False)
    if not QSystemTrayIcon.isSystemTrayAvailable():
        raise RuntimeError("当前桌面环境不提供系统托盘，Voicing 无法继续运行。")

    # 创建现代托盘图标
    tray_icon = ModernTrayIcon()
    tray_icon.show()

    # 更新初始状态
    update_tray_icon_pyqt(tray_icon)

    # 保存到状态
    state.tray_icon = tray_icon

    # 定时更新图标状态
    update_timer = QTimer()
    update_timer.timeout.connect(lambda: update_tray_icon_pyqt(tray_icon))
    update_timer.start(200)  # 每200ms更新（闪烁）

    # 运行应用
    app.exec()


def update_tray_icon_pyqt(tray_icon):
    """更新 PyQt5 托盘图标状态"""
    # 判断是否需要闪烁（等待连接状态）
    if state.sync_enabled and len(state.connected_clients) == 0:
        # 等待连接 - 切换闪烁状态
        state.blink_state = not state.blink_state
        tray_icon.update_icon(None, dim=state.blink_state)
    else:
        # 其他状态 - 正常更新
        tray_icon.update_icon(None, dim=False)


# ============================================================
# Main Entry / 主入口
# ============================================================
def main():
    """Main entry point / 主入口"""
    global SERVER_INTERFACES

    # 初始化日志系统
    setup_logging()
    try:
        ensure_runtime_supported()
    except RuntimeError as exc:
        logging.error(str(exc))
        show_fatal_message("Voicing 无法启动", str(exc))
        return

    # Detect broadcast-capable interfaces at startup
    discovered_interfaces = get_all_local_interfaces()
    log_detected_network_interfaces(discovered_interfaces)
    SERVER_INTERFACES = calculate_broadcast_addresses(discovered_interfaces)
    logging.info(f"当前首选服务地址: {get_primary_server_ip()}")

    # Start WebSocket server in background thread
    ws_thread = threading.Thread(target=run_server, daemon=True)
    ws_thread.start()

    # Start UDP broadcast for auto-discovery
    udp_thread = threading.Thread(target=start_udp_broadcast, daemon=True)
    udp_thread.start()

    try:
        run_tray()
    except RuntimeError as exc:
        logging.error(str(exc))
        show_fatal_message("Voicing 无法启动", str(exc))


def show_fatal_message(title: str, message: str) -> None:
    owns_app = QApplication.instance() is None
    app = QApplication.instance() if not owns_app else QApplication([])
    QMessageBox.critical(None, title, message)
    if owns_app:
        app.quit()


if __name__ == "__main__":
    # Development mode: run with --dev flag to skip single instance check
    # 开发模式：使用 --dev 参数跳过单实例检查，方便快速迭代
    DEV_MODE = "--dev" in sys.argv

    if not DEV_MODE:
        # Check single instance first (only in production)
        if not check_single_instance():
            show_already_running_message()
            sys.exit(0)
    else:
        print("=== Running in DEV MODE (single instance check disabled) ===")

    main()
