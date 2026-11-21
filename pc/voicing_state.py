"""PC 端跨线程共享的运行时状态（Qt 主线程 + WebSocket asyncio 线程）。

单独成模块是为了让 ``tray_ui`` / ``qr_dialog`` / ``voicing_server`` 都能拿到同一份
状态对象，又不产生循环导入：这些模块只依赖 ``voicing_state``，装配层
``voice_coding`` 再依赖它们。

注意：这里只放数据与 Qt 信号桥；不要在 ``voicing_state`` 里 import 任何本项目
的 UI / 网络模块。
"""
from __future__ import annotations

import threading
from typing import Optional

from PyQt5.QtCore import QObject, pyqtSignal

from voicing_protocol import WEBSOCKET_PORT


class UiSignals(QObject):
    """asyncio 线程 -> Qt 主线程的信号桥。"""

    qr_scan_succeeded = pyqtSignal(str)


class AppState:
    """应用状态管理 / Application state management。"""

    def __init__(self) -> None:
        self.sync_enabled = True
        self.running = True
        self.server = None
        self.tray_icon = None
        self.ws_port = WEBSOCKET_PORT
        self.connected_clients = set()
        self.blink_state = False  # 图标闪烁状态
        self.blink_timer: Optional[threading.Timer] = None
        self.log_file = None  # 日志文件路径
        self.lock = threading.Lock()  # 保护共享状态
        self.shutdown_event = threading.Event()  # 用于优雅退出
        self.qr_dialog = None  # QR 码弹窗（由 tray_ui 懒加载）
        self.ui_signals = None  # Qt UI 线程信号桥
        self.server_loop = None  # WebSocket server 所属 asyncio event loop


state = AppState()
