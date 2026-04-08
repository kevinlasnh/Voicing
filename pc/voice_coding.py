"""
Voicing - PC Application
语音编程 - 电脑端应用

A system tray application that receives text from phone and types it at cursor position.
系统托盘应用，接收手机发送的文本并在光标处输入。
"""

import asyncio
import socket
import sys
import os
import threading
import winreg
import json
import ctypes
import logging
import subprocess
import time
from datetime import datetime
from typing import Optional
from pathlib import Path

# PyQt5 for modern tray menu
from PyQt5.QtWidgets import (
    QApplication, QSystemTrayIcon, QMenu, QAction,
    QWidget, QVBoxLayout, QHBoxLayout, QLabel,
    QPushButton, QStyle, QGraphicsDropShadowEffect
)
from PyQt5.QtCore import Qt, QTimer, QPoint, pyqtSignal
from PyQt5.QtGui import QIcon, QPixmap, QPainter, QColor, QFont, QCursor, QPen, QBrush

# Third-party imports
import websockets
from websockets.server import serve
import pyautogui
from PIL import Image, ImageDraw
import pyperclip

# ============================================================
# Single Instance Check / 单实例检查
# ============================================================
MUTEX_NAME = "Voicing_SingleInstance_Mutex"

def check_single_instance() -> bool:
    """
    Check if another instance is already running / 检查是否已有实例在运行
    Returns True if this is the only instance, False if another is running.
    """
    # Try to create a named mutex
    kernel32 = ctypes.windll.kernel32
    mutex = kernel32.CreateMutexW(None, False, MUTEX_NAME)
    last_error = kernel32.GetLastError()
    
    # ERROR_ALREADY_EXISTS = 183
    if last_error == 183:
        # Another instance is already running
        kernel32.CloseHandle(mutex)
        return False
    
    # Store mutex handle globally to keep it alive
    global _mutex_handle
    _mutex_handle = mutex
    return True


def show_already_running_message():
    """Show message that app is already running / 显示程序已运行的提示"""
    ctypes.windll.user32.MessageBoxW(
        0,
        "Voicing 已经在运行中！\n\n请查看系统托盘图标。\n\nVoicing is already running!\nPlease check the system tray.",
        "Voicing",
        0x40  # MB_ICONINFORMATION
    )


# ============================================================
# Configuration / 配置
# ============================================================
APP_NAME = "Voicing"
APP_VERSION = "1.9.0"
WS_PORT = 9527      # WebSocket port
STARTUP_REGISTRY_KEY = r"Software\Microsoft\Windows\CurrentVersion\Run"

# Disable pyautogui failsafe (moving to corner won't stop it)
pyautogui.FAILSAFE = False
# Small pause between keystrokes for stability
pyautogui.PAUSE = 0.01


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
    log_dir = Path(os.environ.get('APPDATA', Path.home())) / 'Voicing' / 'logs'
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
# Windows Mobile Hotspot default IP / Windows 移动热点默认 IP
DEFAULT_HOTSPOT_IP = "192.168.137.1"
# UDP broadcast configuration / UDP 广播配置
UDP_BROADCAST_PORT = 9530  # UDP 广播端口
UDP_BROADCAST_INTERVAL = 2  # 广播间隔（秒）


def get_hotspot_ip() -> str:
    """
    Get the actual hotspot IP address / 获取热点的实际 IP 地址
    
    Windows Mobile Hotspot typically uses 192.168.137.1, but this function
    will try to detect the actual IP by looking for the hotspot adapter.
    """
    try:
        import socket
        
        # Method 1: Try to find hotspot adapter by checking common hotspot IP ranges
        for adapter_ip in get_all_local_ips():
            # Windows Mobile Hotspot typically uses 192.168.137.x
            if adapter_ip.startswith("192.168.137."):
                return adapter_ip
        
        # Method 2: Fallback to default
        return DEFAULT_HOTSPOT_IP
        
    except Exception as e:
        print(f"Error detecting hotspot IP: {e}")
        return DEFAULT_HOTSPOT_IP


def get_all_local_ips() -> list:
    """Get all local IP addresses / 获取所有本地 IP 地址"""
    ips = []
    try:
        import socket
        hostname = socket.gethostname()
        # Get all addresses associated with hostname
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except Exception:
        pass
    
    # Also try to get IPs from network interfaces directly
    try:
        import subprocess
        result = subprocess.run(
            ['powershell', '-Command', 
             "Get-NetIPAddress -AddressFamily IPv4 | Select-Object -ExpandProperty IPAddress"],
            capture_output=True, text=True, creationflags=subprocess.CREATE_NO_WINDOW
        )
        for line in result.stdout.strip().split('\n'):
            ip = line.strip()
            if ip and not ip.startswith("127.") and ip not in ips:
                ips.append(ip)
    except Exception:
        pass
    
    return ips


# ============================================================
# UDP Broadcast for Auto-Discovery / UDP 广播自动发现
# ============================================================
def start_udp_broadcast():
    """
    Start UDP broadcast to let mobile clients discover this server.
    启动 UDP 广播让移动客户端自动发现此服务器。
    """
    broadcast_socket = None
    try:
        broadcast_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        broadcast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        broadcast_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        # Broadcast message format / 广播消息格式
        broadcast_data = json.dumps({
            "type": "voice_coding_server",
            "ip": HOTSPOT_IP,
            "port": state.ws_port,
            "name": socket.gethostname()
        }).encode('utf-8')

        logging.info(f"UDP 广播服务已启动，端口: {UDP_BROADCAST_PORT}")

        while state.running:
            try:
                broadcast_socket.sendto(
                    broadcast_data,
                    ('<broadcast>', UDP_BROADCAST_PORT)
                )
                logging.debug(f"发送 UDP 广播: {HOTSPOT_IP}:{state.ws_port}")
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
HOTSPOT_IP = DEFAULT_HOTSPOT_IP


# ============================================================
# Startup Management / 开机启动管理
# ============================================================
def get_exe_path() -> str:
    """Get the path of the running executable / 获取当前运行程序路径"""
    if getattr(sys, 'frozen', False):
        return sys.executable
    return os.path.abspath(__file__)


def is_startup_enabled() -> bool:
    """Check if app is set to start with Windows / 检查是否已设置开机启动"""
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, STARTUP_REGISTRY_KEY, 0, winreg.KEY_READ) as key:
            winreg.QueryValueEx(key, APP_NAME)
            return True
    except FileNotFoundError:
        return False
    except Exception:
        return False


def set_startup_enabled(enabled: bool) -> bool:
    """Enable or disable startup with Windows / 启用或禁用开机启动"""
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, STARTUP_REGISTRY_KEY, 0, winreg.KEY_SET_VALUE) as key:
            if enabled:
                exe_path = get_exe_path()
                winreg.SetValueEx(key, APP_NAME, 0, winreg.REG_SZ, f'"{exe_path}"')
            else:
                try:
                    winreg.DeleteValue(key, APP_NAME)
                except FileNotFoundError:
                    pass
        return True
    except Exception as e:
        print(f"Failed to modify startup setting: {e}")
        return False


# ============================================================
# Text Input / 文本输入
# ============================================================
def type_text(text: str):
    """
    Type text at current cursor position.
    在当前光标位置输入文本。
    
    Uses pyautogui.write for ASCII and pyperclip+paste for Unicode.
    """
    if not text or not state.sync_enabled:
        return
    
    try:
        # For Unicode support, use clipboard paste method
        import pyperclip
        
        # Save current clipboard
        try:
            old_clipboard = pyperclip.paste()
        except Exception:
            old_clipboard = ""
        
        # Copy new text and paste
        pyperclip.copy(text)
        pyautogui.hotkey('ctrl', 'v')
        
        # Small delay then restore clipboard
        import time
        time.sleep(0.1)
        try:
            pyperclip.copy(old_clipboard)
        except Exception:
            pass
            
    except Exception as e:
        print(f"Error typing text: {e}")


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
        await websocket.send(json.dumps({
            "type": "connected",
            "message": "Connected to Voicing server",
            "sync_enabled": state.sync_enabled,
            "computer_name": computer_name
        }))

        async for message in websocket:
            try:
                data = json.loads(message)
                msg_type = data.get("type", "")

                if msg_type == "text":
                    # Check if sync is enabled
                    if not state.sync_enabled:
                        await websocket.send(json.dumps({
                            "type": "sync_disabled",
                            "message": "Sync is disabled on PC"
                        }))
                        continue

                    text = data.get("content", "")
                    if text:
                        # Type the received text (run in thread to avoid blocking event loop)
                        await asyncio.to_thread(type_text, text)
                        # Send acknowledgment
                        await websocket.send(json.dumps({
                            "type": "ack",
                            "message": "Text received and typed"
                        }))

                elif msg_type == "ping":
                    # Respond with pong and current sync state
                    await websocket.send(json.dumps({
                        "type": "pong",
                        "sync_enabled": state.sync_enabled
                    }))

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
    
    message = json.dumps({
        "type": "sync_state",
        "sync_enabled": state.sync_enabled
    })
    
    for client in state.connected_clients.copy():  # copy() 避免迭代时修改
        try:
            await client.send(message)
        except Exception:
            pass


async def start_server():
    """Start the WebSocket server / 启动WebSocket服务器"""
    try:
        async with serve(handle_client, "0.0.0.0", state.ws_port):
            print(f"WebSocket server started at ws://{HOTSPOT_IP}:{state.ws_port}")
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
                font-family: 'Segoe UI', 'Microsoft YaHei UI', sans-serif;
                font-size: 13px;
                font-weight: 400;
                background: transparent;
            }
        """)
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
                    font-family: 'Segoe UI', 'Microsoft YaHei UI', sans-serif;
                    font-size: 14px;
                    font-weight: bold;
                    background: transparent;
                }
            """)
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
        """在指定位置显示菜单（菜单左下角对齐鼠标点击位置）"""
        # 获取菜单尺寸
        self.adjustSize()
        menu_height = self.height()

        # 菜单左下角对齐鼠标点击位置
        x = tray_pos.x() - 8  # 向左偏移一点，让菜单边缘靠近鼠标
        y = tray_pos.y() - menu_height  # 菜单底部对齐鼠标位置

        self.target_y = y
        self.move(x, y)

        # 从下往上滑出的动画
        self.animation_step = 0
        self.move(x, y + 16)  # 从下方开始
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

            # 从下往上滑
            current_y = self.target_y + 16 * (1 - eased)
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
            # 用默认文本编辑器打开日志文件
            subprocess.Popen(['notepad.exe', str(state.log_file)])
        else:
            # 打开日志目录
            log_dir = Path(os.environ.get('APPDATA', Path.home())) / 'Voicing' / 'logs'
            log_dir.mkdir(parents=True, exist_ok=True)
            os.startfile(str(log_dir))

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


class ModernTrayIcon(QSystemTrayIcon):
    """现代托盘图标"""

    def __init__(self, parent=None):
        super().__init__(parent)
        # 预先缓存图标
        self._icon_cache = {}
        self._init_icon_cache()
        # 预先创建菜单（避免首次打开慢）
        self.menu_widget = ModernMenuWidget()
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
        """托盘图标激活事件"""
        if reason == QSystemTrayIcon.Context:
            # 只有右键点击才显示菜单
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
    global HOTSPOT_IP

    # 初始化日志系统
    setup_logging()

    # Detect hotspot IP at startup
    HOTSPOT_IP = get_hotspot_ip()
    logging.info(f"检测到热点 IP: {HOTSPOT_IP}")

    # Start WebSocket server in background thread
    ws_thread = threading.Thread(target=run_server, daemon=True)
    ws_thread.start()

    # Start UDP broadcast for auto-discovery
    udp_thread = threading.Thread(target=start_udp_broadcast, daemon=True)
    udp_thread.start()

    # Run tray icon with PyQt5 in main thread
    run_tray()


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
