"""Voicing - PC Application 入口与装配层。

语音编程 - 电脑端应用：接收手机发送的文本并在当前光标处输入。

本文件只做「入口 + 装配 + 兼容导出」：
    * 模块拆分（2026-11-20）：
        - ``network_interfaces``：物理网卡发现/过滤/排序、Tailscale、地址快照缓存
        - ``voicing_server``：WebSocket server 生命周期、连接注册表、handle_client
        - ``qr_dialog``：QR 弹窗与扫码成功态遮罩
        - ``tray_ui``：托盘图标、Linux 原生菜单、非 Linux 自定义菜单
        - ``voicing_tuning``：所有可调参数（支持 ``VOICING_*`` 环境变量覆盖）
        - ``voicing_state``：跨线程共享状态与 Qt 信号桥
    * 兼容：既有测试/脚本仍然 ``from voice_coding import X``，因此这里保留全部旧
      导出。旧测试还会 ``patch("voice_coding.type_text")`` / ``patch("voice_coding
      ._get_tailscale_ipv4")`` 等，因此本层提供「转发函数」：每次调用时才从本模块
      命名空间取被 patch 的对象，保证 patch 目标仍是实际被调用的对象。
    * PyInstaller onefile 入口仍是本文件：所有新模块都在这里（或经这里的模块）
      以 import 形式出现，静态分析会自动收集，无需改 ``Voicing.spec``。
"""
from __future__ import annotations

import asyncio
import logging
import subprocess
import sys
import threading
import time
from datetime import datetime

try:  # 兼容旧测试替换 voice_coding.psutil 的用法
    import psutil
except Exception:  # pragma: no cover - 依赖缺失时 network_interfaces 内部走命令兜底
    psutil = None

from PyQt5.QtCore import Qt, QTimer
from PyQt5.QtWidgets import QApplication, QMessageBox, QSystemTrayIcon

from device_identity import get_or_create_device_identity
from platform_instance import check_single_instance, show_already_running_message
from platform_keyboard import press_enter, type_text_at_cursor
# platform_utils 的常用符号保留在本模块命名空间，兼容旧代码/旧测试的属性访问。
from platform_utils import (
    WINDOWS_HOTSPOT_PREFIXES,
    ensure_runtime_supported,
    get_default_server_ip,
    get_known_hotspot_prefixes,
    get_log_dir,
    get_native_font_family,
    get_platform,
    get_preferred_hotspot_prefixes,
    open_file_in_default_app,
    open_file_in_text_editor,
    system_subprocess_env,
)
from voicing_protocol import WEBSOCKET_PORT

import network_interfaces
import qr_dialog
import tray_ui
import voicing_server
import voicing_tuning as tuning
from voicing_state import AppState, UiSignals, state


# ============================================================
# Configuration / 配置
# ============================================================
APP_NAME = "Voicing"
APP_VERSION = "2.10.1"
WS_PORT = WEBSOCKET_PORT      # WebSocket port
AUTO_ENTER_SETTLE_DELAY_SEC = tuning.AUTO_ENTER_SETTLE_DELAY_SEC
NATIVE_FONT_FAMILY = get_native_font_family()
# 兼容旧命名：监听循环轮询周期（真实枚举由 TTL 快照控制，见 voicing_tuning）
NETWORK_INTERFACE_REFRESH_SEC = tuning.NETWORK_SNAPSHOT_POLL_SEC
DEFAULT_SERVER_IP = network_interfaces.DEFAULT_SERVER_IP


# ============================================================
# UiSignals / UI bridge (兼容导出，定义在 voicing_state)
# ============================================================
def notify_qr_scan_succeeded(reason="unknown"):
    logging.info(f"QR 扫码连通成功信号: {reason}")
    signals = state.ui_signals
    if signals is not None:
        signals.qr_scan_succeeded.emit(reason)
    else:
        logging.warning("QR 扫码连通成功信号未送达：UI signal bridge 尚未初始化")


def show_qr_scan_success(reason="unknown"):
    logging.info(f"准备播放 QR 成功态动画: {reason}")
    if state.qr_dialog is not None:
        state.qr_dialog.show_scan_success()


# ============================================================
# Logging Setup / 日志配置
# ============================================================
def setup_logging():
    """设置日志系统"""
    # 日志文件保存在用户数据目录
    log_dir = get_log_dir()
    log_dir.mkdir(parents=True, exist_ok=True)

    # 使用日期作为文件名
    log_file = log_dir / f"voice_coding_{datetime.now().strftime('%Y%m%d')}.log"
    state.log_file = log_file

    # 配置 logging
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
# Text Input / 文本输入
# ============================================================
def type_text(text: str, auto_enter: bool = False) -> bool:
    """
    Type text at current cursor position.
    在当前光标位置输入文本。

    Uses clipboard paste for cross-platform Unicode input.

    Args:
        text: Text to type
        auto_enter: If True, press Enter after typing
    """
    if not text or not state.sync_enabled:
        return False

    started = time.perf_counter()
    try:
        type_text_at_cursor(
            text,
            auto_enter=auto_enter,
            enter_delay_sec=AUTO_ENTER_SETTLE_DELAY_SEC,
            restore_delay_sec=tuning.TEXT_INPUT_RESTORE_DELAY_SEC,
        )
        logging.info(
            "文本注入成功: chars=%d auto_enter=%s 耗时=%.1fms",
            len(text),
            auto_enter,
            (time.perf_counter() - started) * 1000,
        )
        return True

    except Exception as e:
        logging.error(
            "文本注入失败: chars=%d auto_enter=%s 耗时=%.1fms error=%s",
            len(text),
            auto_enter,
            (time.perf_counter() - started) * 1000,
            e,
        )
        return False


def press_enter_after_settle(delay_sec: float = AUTO_ENTER_SETTLE_DELAY_SEC) -> bool:
    """Press Enter after giving the target app time to consume a paste event."""
    try:
        threading.Event().wait(delay_sec)
        press_enter()
        return True
    except Exception as e:
        logging.error(f"Error pressing Enter: {e}")
        return False


# ============================================================
# Network compatibility facade / 网络兼容层
# ============================================================
# 旧测试会 patch 这些模块级名字并期待刷新路径真的使用替换值，
# 因此转发函数在「调用时」才从本模块命名空间解析，而不是绑定到 network_interfaces。
NetworkInterfaceCandidate = network_interfaces.NetworkInterfaceCandidate
InterfaceSnapshot = network_interfaces.InterfaceSnapshot
get_hotspot_ip = network_interfaces.get_hotspot_ip
get_all_local_ips = network_interfaces.get_all_local_ips
get_all_local_interfaces = network_interfaces.get_all_local_interfaces
get_all_network_candidates = network_interfaces.get_all_network_candidates
get_command_network_candidates = network_interfaces.get_command_network_candidates
extract_command_ips = network_interfaces.extract_command_ips
extract_command_interfaces = network_interfaces.extract_command_interfaces
extract_command_interface_candidates = network_interfaces.extract_command_interface_candidates
calculate_broadcast_addresses = network_interfaces.calculate_broadcast_addresses
get_bound_server_ips = network_interfaces.get_bound_server_ips
set_bound_server_ips = network_interfaces.set_bound_server_ips
get_interface_snapshot = network_interfaces.get_interface_snapshot
get_advertised_server_ips_for_snapshot = network_interfaces.get_advertised_server_ips_for_snapshot
SERVER_INTERFACES = network_interfaces.SERVER_INTERFACES
SERVER_INTERFACES_LOCK = network_interfaces.SERVER_INTERFACES_LOCK
# 兼容旧测试读写：真实初始化状态由 network_interfaces 快照持有
SERVER_INTERFACES_INITIALIZED = False
_get_tailscale_ipv4 = network_interfaces._get_tailscale_ipv4
_is_tailscale_cgnat_ip = network_interfaces._is_tailscale_cgnat_ip


def get_psutil_network_candidates(platform_name: str):
    """兼容层：旧测试替换 ``voice_coding.psutil`` 时必须让替换值参与枚举。"""
    return network_interfaces.get_psutil_network_candidates(
        platform_name,
        psutil_module=psutil,
    )


def refresh_server_interfaces(*, log_changes: bool = True):
    return network_interfaces.refresh_server_interfaces(
        log_changes=log_changes,
        discover=get_all_network_candidates,
        tailscale_ipv4=_get_tailscale_ipv4,
    )


def get_server_interfaces(*, refresh: bool = False):
    return network_interfaces.get_server_interfaces(
        refresh=refresh,
        discover=get_all_network_candidates,
        tailscale_ipv4=_get_tailscale_ipv4,
    )


def get_primary_server_ip(*, refresh: bool = False):
    return network_interfaces.get_primary_server_ip(
        refresh=refresh,
        discover=get_all_network_candidates,
        tailscale_ipv4=_get_tailscale_ipv4,
    )


def get_advertised_server_ips(*, refresh: bool = False):
    return network_interfaces.get_advertised_server_ips(
        refresh=refresh,
        discover=get_all_network_candidates,
        tailscale_ipv4=_get_tailscale_ipv4,
    )


def get_qr_advertised_server_ips(*, refresh: bool = False):
    return network_interfaces.get_qr_advertised_server_ips(
        refresh=refresh,
        discover=get_all_network_candidates,
        tailscale_ipv4=_get_tailscale_ipv4,
    )


# ============================================================
# WebSocket compatibility facade / WebSocket 兼容层
# ============================================================
server_registry = voicing_server.ClientRegistry()


def _build_client_services() -> voicing_server.ClientServices:
    """连接建立时解析依赖。

    每次连接现取本模块全局符号，保证旧测试 ``patch("voice_coding.type_text")``、
    ``patch("voice_coding.get_or_create_device_identity")`` 等仍然作用于真实调用对象。
    """
    return voicing_server.ClientServices(
        type_text=type_text,
        press_enter_after_settle=press_enter_after_settle,
        get_identity=get_or_create_device_identity,
        notify_qr_probe=notify_qr_scan_succeeded,
    )


async def handle_client(websocket):
    """兼容导出：真实实现在 ``voicing_server.handle_client``。"""
    await voicing_server.handle_client(
        websocket,
        services_factory=_build_client_services,
        registry=server_registry,
    )


async def broadcast_sync_state():
    """兼容导出：真实实现在 ``voicing_server.broadcast_sync_state``。"""
    await voicing_server.broadcast_sync_state(server_registry)


def schedule_sync_state_broadcast():
    """Schedule sync state broadcast on the WebSocket server loop."""
    loop = state.server_loop
    if loop is None or loop.is_closed():
        logging.warning("同步状态广播跳过：WebSocket event loop 尚未可用")
        return

    future = asyncio.run_coroutine_threadsafe(broadcast_sync_state(), loop)

    def log_broadcast_error(completed_future):
        try:
            completed_future.result()
        except Exception as exc:
            logging.warning(f"同步状态广播失败: {exc}")

    future.add_done_callback(log_broadcast_error)


def run_server():
    """Run the server in a separate thread / 在单独线程中运行服务器。"""
    # WebSocket server 在独立线程跑自己的 event loop；Qt 主线程只通过
    # run_coroutine_threadsafe 投递广播，两边不共享 event loop。
    voicing_server.run_server(
        services_factory=_build_client_services,
        registry=server_registry,
    )


# ============================================================
# Tray / QR UI compatibility re-exports / 托盘与 QR 兼容导出
# ============================================================
MenuItemWidget = tray_ui.MenuItemWidget
ModernMenuWidget = tray_ui.ModernMenuWidget
ModernTrayIcon = tray_ui.ModernTrayIcon
QRSuccessOverlay = qr_dialog.QRSuccessOverlay
QRCodeDialog = qr_dialog.QRCodeDialog
ensure_qr_dialog = tray_ui.ensure_qr_dialog
get_base_icon_path = tray_ui.get_base_icon_path
load_base_icon = tray_ui.load_base_icon
update_tray_icon_pyqt = tray_ui.update_tray_icon_pyqt

# 装配注入：托盘菜单切换同步开关后，把广播投递到 WebSocket server loop。
# 放在函数定义之后赋值，tray_ui 在调用时才解析该回调，避免循环导入。
tray_ui.on_sync_state_changed = schedule_sync_state_broadcast


def run_tray():
    """Run the system tray application with PyQt5 / 使用 PyQt5 运行系统托盘应用。"""
    # 创建 QApplication（如果不存在）
    if QApplication.instance() is None:
        app = QApplication(sys.argv)
    else:
        app = QApplication.instance()

    app.setQuitOnLastWindowClosed(False)
    if not QSystemTrayIcon.isSystemTrayAvailable():
        raise RuntimeError("当前桌面环境不提供系统托盘，Voicing 无法继续运行。")

    if state.ui_signals is None:
        state.ui_signals = UiSignals()
    state.ui_signals.qr_scan_succeeded.connect(
        show_qr_scan_success,
        type=Qt.QueuedConnection,
    )

    # 创建现代托盘图标
    tray_icon = ModernTrayIcon()
    tray_icon.show()

    # 更新初始状态
    update_tray_icon_pyqt(tray_icon)

    # 保存到状态
    state.tray_icon = tray_icon

    # 定时更新图标状态（闪烁）
    update_timer = QTimer()
    update_timer.timeout.connect(lambda: update_tray_icon_pyqt(tray_icon))
    update_timer.start(tuning.TRAY_ICON_UPDATE_INTERVAL_MS)
    logging.info("托盘就绪: 图标定时器 %dms 已启动", tuning.TRAY_ICON_UPDATE_INTERVAL_MS)

    # 运行应用
    app.exec()


# ============================================================
# Main Entry / 主入口
# ============================================================
def main():
    """Main entry point / 主入口"""
    # 初始化日志系统
    setup_logging()
    tuning.log_effective_tuning()
    try:
        ensure_runtime_supported()
    except RuntimeError as exc:
        logging.error(str(exc))
        show_fatal_message("Voicing 无法启动", str(exc))
        return

    # Detect QR-advertisable interfaces at startup; the server thread refreshes
    # this snapshot at runtime for network changes.
    refresh_server_interfaces(log_changes=True)
    logging.info(f"当前首选服务地址: {get_primary_server_ip()}")

    # Start WebSocket server in background thread
    ws_thread = threading.Thread(target=run_server, daemon=True)
    ws_thread.start()

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
