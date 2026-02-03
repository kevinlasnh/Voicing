"""
Voice Coding - PC Application
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
import ssl
import shutil
import ipaddress
import logging
import subprocess
from datetime import datetime
from typing import Optional
from pathlib import Path
from http.server import HTTPServer, SimpleHTTPRequestHandler
import mimetypes

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
import pystray
from pystray import MenuItem as item
from PIL import Image, ImageDraw

# Ngrok for HTTPS tunnel (PWA install support)
try:
    from pyngrok import ngrok
    NGROK_AVAILABLE = True
except ImportError:
    NGROK_AVAILABLE = False
    print("Warning: pyngrok not installed. ngrok feature will be disabled.")
    print("Install with: pip install pyngrok")

# ============================================================
# Single Instance Check / 单实例检查
# ============================================================
MUTEX_NAME = "VoiceCoding_SingleInstance_Mutex"

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
        "Voice Coding 已经在运行中！\n\n请查看系统托盘图标。\n\nVoice Coding is already running!\nPlease check the system tray.",
        "Voice Coding",
        0x40  # MB_ICONINFORMATION
    )


# ============================================================
# Configuration / 配置
# ============================================================
APP_NAME = "VoiceCoding"
APP_VERSION = "1.0.0"
WS_PORT = 9527      # WebSocket port
HTTP_PORT = 9528    # HTTP port for web UI
HTTPS_PORT = 9529   # HTTPS port for web UI (PWA install requires HTTPS)
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
        self.http_port = HTTP_PORT
        self.https_port = HTTPS_PORT
        self.https_enabled = True  # Enable HTTPS by default for PWA install support
        self.connected_clients = set()
        self.blink_state = False  # For icon blinking / 图标闪烁状态
        self.blink_timer: Optional[threading.Timer] = None
        self.https_server = None  # HTTPS server instance for shutdown
        # Ngrok tunnel state / Ngrok 隧道状态
        self.ngrok_enabled = False
        self.ngrok_tunnel = None
        self.ngrok_url = ""
        self.use_ngrok = False  # Whether to use ngrok URL for display
        self.log_file = None  # 日志文件路径

state = AppState()


# ============================================================
# Logging Setup / 日志配置
# ============================================================
def setup_logging():
    """设置日志系统"""
    # 日志文件保存在用户数据目录
    log_dir = Path(os.environ.get('APPDATA', Path.home())) / 'VoiceCoding' / 'logs'
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
    logging.info(f"=== Voice Coding 启动 ===")
    logging.info(f"日志文件: {log_file}")


# ============================================================
# Network Configuration / 网络配置
# ============================================================
# Windows Mobile Hotspot default IP / Windows 移动热点默认 IP
DEFAULT_HOTSPOT_IP = "192.168.137.1"


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
    except:
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
    except:
        pass
    
    return ips


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
        except:
            old_clipboard = ""
        
        # Copy new text and paste
        pyperclip.copy(text)
        pyautogui.hotkey('ctrl', 'v')
        
        # Small delay then restore clipboard
        import time
        time.sleep(0.1)
        try:
            pyperclip.copy(old_clipboard)
        except:
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
    state.connected_clients.add(websocket)
    print(f"Client connected: {client_addr}")

    # Update tray icon when client connects
    if state.tray_icon:
        try:
            update_tray_icon(state.tray_icon)
        except Exception as e:
            print(f"Error updating tray icon: {e}")

    try:
        # Get computer name for identification
        computer_name = socket.gethostname()

        # Send welcome message with current sync state and computer name
        await websocket.send(json.dumps({
            "type": "connected",
            "message": "Connected to Voice Coding server",
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
                        # Type the received text
                        type_text(text)
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
                    type_text(message)
                    
    except websockets.exceptions.ConnectionClosed:
        pass
    finally:
        state.connected_clients.discard(websocket)
        print(f"Client disconnected: {client_addr}")
        
        # Update tray icon when client disconnects
        if state.tray_icon:
            update_tray_icon(state.tray_icon)


async def broadcast_sync_state():
    """Broadcast sync state to all connected clients / 广播同步状态给所有客户端"""
    if not state.connected_clients:
        return
    
    message = json.dumps({
        "type": "sync_state",
        "sync_enabled": state.sync_enabled
    })
    
    for client in state.connected_clients.copy():
        try:
            await client.send(message)
        except:
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
# HTTPS Certificate Management / HTTPS 证书管理
# ============================================================
def get_cert_dir() -> Path:
    """Get the certificate directory / 获取证书目录路径"""
    if getattr(sys, 'frozen', False):
        # Running as compiled exe - use AppData/Local
        app_data = Path(os.environ.get('LOCALAPPDATA', Path.home() / '.local'))
        cert_dir = app_data / 'VoiceCoding'
    else:
        # Running as script - use script directory
        cert_dir = Path(__file__).parent / 'certs'

    cert_dir.mkdir(parents=True, exist_ok=True)
    return cert_dir


def generate_self_signed_cert():
    """
    Generate a self-signed certificate for HTTPS.
    生成自签名证书用于 HTTPS。
    """
    cert_dir = get_cert_dir()
    cert_file = cert_dir / 'server.pem'
    key_file = cert_dir / 'server.key'
    combined_cert = cert_dir / 'server_combined.pem'

    # Check if any certificate file already exists
    if combined_cert.exists():
        return str(combined_cert), None
    if cert_file.exists() and key_file.exists():
        return str(cert_file), str(key_file)

    print("Generating self-signed certificate...")

    try:
        # Try using cryptography module
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        from cryptography.hazmat.primitives import hashes
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives import serialization
        import datetime

        # Generate private key
        key = rsa.generate_private_key(
            public_exponent=65537,
            key_size=2048,
        )

        # Generate certificate
        subject = issuer = x509.Name([
            x509.NameAttribute(NameOID.COUNTRY_NAME, "CN"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "Beijing"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "Beijing"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "VoiceCoding"),
            x509.NameAttribute(NameOID.COMMON_NAME, "localhost"),
        ])

        cert = x509.CertificateBuilder().subject_name(
            subject
        ).issuer_name(
            issuer
        ).public_key(
            key.public_key()
        ).serial_number(
            x509.random_serial_number()
        ).not_valid_before(
            datetime.datetime.utcnow()
        ).not_valid_after(
            datetime.datetime.utcnow() + datetime.timedelta(days=3650)  # 10 years
        ).add_extension(
            x509.SubjectAlternativeName([
                x509.DNSName("localhost"),
                x509.IPAddress(ipaddress.IPv4Address("127.0.0.1")),
                x509.IPAddress(ipaddress.IPv4Address("192.168.137.1")),
                x509.IPAddress(ipaddress.IPv4Address("192.168.0.1")),
                x509.IPAddress(ipaddress.IPv4Address("192.168.1.1")),
                x509.IPAddress(ipaddress.IPv4Address("10.0.0.1")),
            ]),
            critical=False,
        ).sign(key, hashes.SHA256())

        # Write certificate
        with open(cert_file, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))

        # Write key
        with open(key_file, "wb") as f:
            f.write(key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption()
            ))

        # Create combined file for easier use
        with open(combined_cert, "wb") as f:
            f.write(cert.public_bytes(serialization.Encoding.PEM))
            f.write(key.private_bytes(
                encoding=serialization.Encoding.PEM,
                format=serialization.PrivateFormat.TraditionalOpenSSL,
                encryption_algorithm=serialization.NoEncryption()
            ))

        print(f"Certificate generated: {combined_cert}")
        return str(combined_cert), None

    except ImportError:
        # Fallback: use OpenSSL command if available
        print("cryptography module not found, trying OpenSSL...")
        try:
            import subprocess

            # OpenSSL command to generate self-signed certificate (directly to combined file)
            cmd = [
                'openssl', 'req', '-x509', '-newkey', 'rsa:2048',
                '-keyout', str(key_file), '-out', str(cert_file),
                '-days', '3650', '-nodes',
                '-subj', '/C=CN/ST=Beijing/L=Beijing/O=VoiceCoding/CN=localhost'
            ]

            result = subprocess.run(cmd, capture_output=True, text=True,
                                    creationflags=subprocess.CREATE_NO_WINDOW)

            if result.returncode == 0:
                # Combine cert and key for Python ssl module
                with open(combined_cert, 'wb') as combined:
                    with open(cert_file, 'rb') as f:
                        combined.write(f.read())
                    with open(key_file, 'rb') as f:
                        combined.write(f.read())

                print(f"Certificate generated using OpenSSL: {combined_cert}")
                return str(combined_cert), None
            else:
                print(f"OpenSSL failed: {result.stderr}")
                return None, None

        except FileNotFoundError:
            print("OpenSSL not found. Please install cryptography package:")
            print("  pip install cryptography")
            return None, None

    except Exception as e:
        print(f"Error generating certificate: {e}")
        import traceback
        traceback.print_exc()
        return None, None


def run_https_server():
    """Run HTTPS server for web UI / 运行HTTPS服务器提供网页界面"""
    try:
        cert_file, key_file = generate_self_signed_cert()

        if cert_file is None:
            print("Failed to generate certificate. HTTPS server not started.")
            print("PWA installation requires HTTPS. Install: pip install cryptography")
            return

        httpd = HTTPServer(('0.0.0.0', state.https_port), WebHandler)

        # Create SSL context
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.check_hostname = False
        context.verify_mode = ssl.CERT_NONE

        # Load certificate - handle both separate files and combined file
        if key_file:
            # Separate cert and key files
            context.load_cert_chain(certfile=cert_file, keyfile=key_file)
        else:
            # Combined PEM file - load same file for both (works because it contains both)
            # Actually, for combined file we just need certfile parameter
            context.load_cert_chain(certfile=cert_file)

        # Wrap the socket with SSL
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

        state.https_server = httpd

        print(f"HTTPS server started at https://{HOTSPOT_IP}:{state.https_port}")
        print(f"  Certificate: {cert_file}")
        print(f"  Note: You'll need to accept the security warning in your browser")

        # Use serve_forever for more stable operation
        httpd.serve_forever()

    except Exception as e:
        print(f"HTTPS server error: {e}")
        import traceback
        traceback.print_exc()


# ============================================================
# Ngrok Tunnel / Ngrok 隧道
# ============================================================
def start_ngrok_tunnel():
    """Start ngrok tunnel for HTTPS access / 启动 ngrok 隧道用于 HTTPS 访问"""
    if not NGROK_AVAILABLE:
        return None

    try:
        # Save and clear proxy environment variables (ngrok free tier doesn't support proxy)
        # 保存并清除代理环境变量（ngrok 免费版不支持代理）
        old_http_proxy = os.environ.pop('http_proxy', None)
        old_https_proxy = os.environ.pop('https_proxy', None)
        old_HTTP_PROXY = os.environ.pop('HTTP_PROXY', None)
        old_HTTPS_PROXY = os.environ.pop('HTTPS_PROXY', None)

        try:
            # Connect to ngrok and create tunnel to HTTP server
            tunnel = ngrok.connect(state.http_port, bind_tls=True)
            public_url = tunnel.public_url
            print(f"Ngrok tunnel established: {public_url}")
            return tunnel, public_url
        finally:
            # Restore proxy environment variables
            # 恢复代理环境变量
            if old_http_proxy:
                os.environ['http_proxy'] = old_http_proxy
            if old_https_proxy:
                os.environ['https_proxy'] = old_https_proxy
            if old_HTTP_PROXY:
                os.environ['HTTP_PROXY'] = old_HTTP_PROXY
            if old_HTTPS_PROXY:
                os.environ['HTTPS_PROXY'] = old_HTTPS_PROXY

    except Exception as e:
        print(f"Failed to start ngrok tunnel: {e}")
        import traceback
        traceback.print_exc()
        return None, None


def stop_ngrok_tunnel():
    """Stop ngrok tunnel / 停止 ngrok 隧道"""
    if not NGROK_AVAILABLE:
        return

    try:
        ngrok.kill()
        print("Ngrok tunnel stopped")
    except Exception as e:
        print(f"Error stopping ngrok: {e}")


def get_display_url():
    """Get the URL to display to user / 获取显示给用户的 URL"""
    if state.use_ngrok and state.ngrok_url:
        return state.ngrok_url
    elif state.https_enabled:
        return f"https://{HOTSPOT_IP}:{state.https_port}"
    else:
        return f"http://{HOTSPOT_IP}:{state.http_port}"


# ============================================================
# HTTP Server for Web UI / HTTP服务器提供网页界面
# ============================================================
def get_web_dir() -> Path:
    """Get the web directory path / 获取网页目录路径"""
    if getattr(sys, 'frozen', False):
        # Running as compiled exe
        return Path(sys._MEIPASS) / 'web'
    else:
        # Running as script
        return Path(__file__).parent / 'web'


class WebHandler(SimpleHTTPRequestHandler):
    """Custom HTTP handler for serving web files / 自定义HTTP处理器"""
    
    def __init__(self, *args, **kwargs):
        self.directory = str(get_web_dir())
        super().__init__(*args, directory=self.directory, **kwargs)
    
    def log_message(self, format, *args):
        # Suppress HTTP logs
        pass
    
    def end_headers(self):
        # Add CORS headers for WebSocket
        self.send_header('Access-Control-Allow-Origin', '*')
        super().end_headers()


def run_http_server():
    """Run HTTP server for web UI / 运行HTTP服务器提供网页界面"""
    try:
        server = HTTPServer(('0.0.0.0', state.http_port), WebHandler)
        print(f"HTTP server started at http://{HOTSPOT_IP}:{state.http_port}")
        while state.running:
            server.handle_request()
    except Exception as e:
        print(f"HTTP server error: {e}")


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

        if self._hovered:
            # 悬停状态 - 使用更亮的高亮色
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
        """鼠标点击事件"""
        self.clicked.emit()
        super().mousePressEvent(event)


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
        container_layout.setSpacing(2)  # 项间距

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
            log_dir = Path(os.environ.get('APPDATA', Path.home())) / 'VoiceCoding' / 'logs'
            log_dir.mkdir(parents=True, exist_ok=True)
            os.startfile(str(log_dir))

    def quit_app(self):
        """退出应用"""
        state.running = False
        if state.ngrok_tunnel:
            stop_ngrok_tunnel()
        QApplication.quit()

    def close_with_animation(self):
        """关闭动画"""
        self.animation_timer.stop()
        self.close()


class ModernTrayIcon(QSystemTrayIcon):
    """现代托盘图标"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.menu_widget = None
        self.setup_icon()
        self.setup_menu()

    def setup_icon(self):
        """设置图标"""
        # 使用 PIL 创建图标并转换为 QPixmap
        from PIL import Image, ImageDraw
        import io

        size = 32
        image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)

        # 蓝色背景圆
        draw.ellipse([2, 2, size-2, size-2], fill='#2196F3')

        # 白色 "V"
        draw.polygon([
            (8, 10), (16, 22), (24, 10),
            (21, 10), (16, 18), (11, 10)
        ], fill='white')

        # 转换为 QPixmap
        byte_data = io.BytesIO()
        image.save(byte_data, format='PNG')
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
        if reason == QSystemTrayIcon.Trigger or reason == QSystemTrayIcon.Context:
            # 左键或右键点击显示自定义菜单
            self.show_custom_menu()

    def show_custom_menu(self):
        """显示自定义菜单"""
        if self.menu_widget is None:
            self.menu_widget = ModernMenuWidget()

        # 更新状态
        self.menu_widget.update_state()

        # 获取托盘图标位置并显示菜单（带动画）
        pos = QCursor.pos()
        self.menu_widget.show_at_position(pos)

    def update_icon(self, status):
        """更新图标状态"""
        from PIL import Image, ImageDraw
        import io

        size = 32
        image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        draw = ImageDraw.Draw(image)

        if not state.sync_enabled:
            # 灰色 - 暂停
            bg_color = '#9E9E9E'
        elif len(state.connected_clients) > 0:
            # 绿色 - 已连接
            bg_color = '#4CAF50'
        else:
            # 蓝色 - 等待连接
            bg_color = '#2196F3'

        # 背景圆
        draw.ellipse([2, 2, size-2, size-2], fill=bg_color)

        # 白色 "V"
        draw.polygon([
            (8, 10), (16, 22), (24, 10),
            (21, 10), (16, 18), (11, 10)
        ], fill='white')

        # 转换为 QPixmap
        byte_data = io.BytesIO()
        image.save(byte_data, format='PNG')
        byte_data.seek(0)
        qpix = QPixmap()
        qpix.loadFromData(byte_data.getvalue())

        self.setIcon(QIcon(qpix))


# ============================================================
# System Tray / 系统托盘 (保留兼容函数)
# ============================================================
def create_icon_connected() -> Image.Image:
    """Create connected state tray icon (green) / 创建已连接状态托盘图标（绿色）"""
    size = 64
    image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    
    # Green background circle - connected
    draw.ellipse([4, 4, size-4, size-4], fill='#4CAF50')
    
    # White "V" shape for Voice
    draw.polygon([
        (16, 20), (32, 44), (48, 20),
        (42, 20), (32, 36), (22, 20)
    ], fill='white')
    
    return image


def create_icon_waiting() -> Image.Image:
    """Create waiting state tray icon (blue) / 创建等待连接状态托盘图标（蓝色）"""
    size = 64
    image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    
    # Blue background circle - waiting for connection
    draw.ellipse([4, 4, size-4, size-4], fill='#2196F3')
    
    # White "V" shape for Voice
    draw.polygon([
        (16, 20), (32, 44), (48, 20),
        (42, 20), (32, 36), (22, 20)
    ], fill='white')
    
    return image


def create_icon_waiting_dim() -> Image.Image:
    """Create dim waiting state tray icon (dark blue) / 创建暗淡等待状态托盘图标（深蓝色）"""
    size = 64
    image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    
    # Darker blue background circle - for blinking effect
    draw.ellipse([4, 4, size-4, size-4], fill='#1565C0')
    
    # Dimmer white "V" shape
    draw.polygon([
        (16, 20), (32, 44), (48, 20),
        (42, 20), (32, 36), (22, 20)
    ], fill='#B3E5FC')
    
    return image


def create_icon_paused() -> Image.Image:
    """Create paused state tray icon / 创建暂停状态托盘图标"""
    size = 64
    image = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    
    # Gray background circle
    draw.ellipse([4, 4, size-4, size-4], fill='#9E9E9E')
    
    # White pause bars
    draw.rectangle([20, 18, 28, 46], fill='white')
    draw.rectangle([36, 18, 44, 46], fill='white')
    
    return image


def toggle_sync(icon, menu_item):
    """Toggle sync on/off / 切换同步开关"""
    state.sync_enabled = not state.sync_enabled
    update_tray_icon(icon)
    
    # Broadcast sync state to all connected clients
    def send_sync_state():
        loop = asyncio.new_event_loop()
        asyncio.set_event_loop(loop)
        loop.run_until_complete(broadcast_sync_state())
        loop.close()
    
    threading.Thread(target=send_sync_state, daemon=True).start()


def toggle_startup(icon, menu_item):
    """Toggle startup with Windows / 切换开机启动"""
    current = is_startup_enabled()
    set_startup_enabled(not current)


def toggle_https(icon, menu_item):
    """Toggle HTTPS on/off / 切换HTTPS开关"""
    state.https_enabled = not state.https_enabled

    if state.https_enabled:
        # Start HTTPS server
        https_thread = threading.Thread(target=run_https_server, daemon=True)
        https_thread.start()
    else:
        # Shutdown HTTPS server
        if state.https_server:
            try:
                state.https_server.shutdown()
                state.https_server = None
            except:
                pass

    # Update notification with new URL
    show_ip_address(icon, menu_item)


def toggle_ngrok(icon, menu_item):
    """Toggle ngrok tunnel on/off / 切换ngrok隧道开关"""
    if not NGROK_AVAILABLE:
        icon.notify("ngrok 不可用！请安装: pip install pyngrok", "Voice Coding")
        return

    state.ngrok_enabled = not state.ngrok_enabled

    if state.ngrok_enabled:
        # Start ngrok tunnel
        tunnel, url = start_ngrok_tunnel()
        if tunnel and url:
            state.ngrok_tunnel = tunnel
            state.ngrok_url = url
            state.use_ngrok = True
            icon.notify(f"ngrok 隧道已启动\n{url}\n(已复制到剪贴板)", "Voice Coding")
            # Copy to clipboard
            try:
                import pyperclip
                pyperclip.copy(url)
            except:
                pass
        else:
            state.ngrok_enabled = False
            icon.notify("ngrok 启动失败！请检查网络连接", "Voice Coding")
    else:
        # Stop ngrok tunnel
        stop_ngrok_tunnel()
        state.ngrok_tunnel = None
        state.ngrok_url = ""
        state.use_ngrok = False
        icon.notify("ngrok 隧道已关闭", "Voice Coding")


def show_ip_address(icon, menu_item):
    """Show IP address notification and copy to clipboard / 显示IP地址并复制"""
    web_url = get_display_url()

    if state.use_ngrok:
        message = f"🌐 ngrok 隧道模式:\n{web_url}\n\n✅ 可直接安装 PWA！\n(已复制到剪贴板)"
    elif state.https_enabled:
        http_url = f"http://{HOTSPOT_IP}:{state.http_port}"
        message = f"📱 手机连接电脑热点后访问:\n{web_url}\n(HTTP: {http_url})\n\n⚠️ 自签名证书: 需接受警告\n且可能无法安装 PWA\n(已复制到剪贴板)"
    else:
        message = f"📱 手机连接电脑热点后访问:\n{web_url}\n(已复制到剪贴板)"

    # Copy to clipboard
    try:
        import pyperclip
        pyperclip.copy(web_url)
    except:
        pass

    icon.notify(message, "Voice Coding")


def quit_app(icon, menu_item):
    """Quit the application / 退出应用"""
    state.running = False

    # Stop ngrok tunnel if enabled
    if state.ngrok_tunnel:
        stop_ngrok_tunnel()

    stop_blink_timer()
    icon.stop()


def stop_blink_timer():
    """Stop the blink timer / 停止闪烁定时器"""
    if state.blink_timer:
        state.blink_timer.cancel()
        state.blink_timer = None


def start_blink_timer(icon):
    """Start the icon blink timer / 启动图标闪烁定时器"""
    stop_blink_timer()
    
    def blink():
        if not state.running:
            return
        if len(state.connected_clients) == 0 and state.sync_enabled:
            # Toggle blink state
            state.blink_state = not state.blink_state
            if state.blink_state:
                icon.icon = create_icon_waiting()
            else:
                icon.icon = create_icon_waiting_dim()
            # Schedule next blink
            state.blink_timer = threading.Timer(0.5, blink)
            state.blink_timer.daemon = True
            state.blink_timer.start()
    
    blink()


def update_tray_icon(icon):
    """Update tray icon based on state / 根据状态更新托盘图标"""
    stop_blink_timer()
    
    if not state.sync_enabled:
        # Sync disabled - gray icon
        icon.icon = create_icon_paused()
        icon.title = f"Voice Coding - Paused\nhttp://{HOTSPOT_IP}:{state.http_port}"
    elif len(state.connected_clients) > 0:
        # Has connected clients - green icon
        icon.icon = create_icon_connected()
        client_count = len(state.connected_clients)
        icon.title = f"Voice Coding - {client_count} Connected\nhttp://{HOTSPOT_IP}:{state.http_port}"
    else:
        # Waiting for connection - blue blinking icon
        icon.title = f"Voice Coding - Waiting\nhttp://{HOTSPOT_IP}:{state.http_port}"
        start_blink_timer(icon)


def create_menu():
    """Create the tray menu / 创建托盘菜单"""
    return pystray.Menu(
        item(
            '📋 显示IP',
            show_ip_address
        ),
        pystray.Menu.SEPARATOR,
        item(
            '🔄 同步',
            toggle_sync,
            checked=lambda item: state.sync_enabled
        ),
        item(
            '🚀 开机启动',
            toggle_startup,
            checked=lambda item: is_startup_enabled()
        ),
        pystray.Menu.SEPARATOR,
        item(
            '❌ 退出',
            quit_app
        )
    )


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
    update_timer.start(1000)  # 每秒更新

    # 运行应用
    app.exec()


def update_tray_icon_pyqt(tray_icon):
    """更新 PyQt5 托盘图标状态"""
    # 更新图标
    tray_icon.update_icon(None)


# 保留兼容的 update_tray_icon 函数
def update_tray_icon(icon=None):
    """Update tray icon based on state / 根据状态更新托盘图标（兼容函数）"""
    if icon is None:
        # 如果没有传入 icon，跳过（PyQt5 模式）
        return
    # 原 pystray 逻辑保留
    stop_blink_timer()

    if not state.sync_enabled:
        icon.icon = create_icon_paused()
        icon.title = f"Voice Coding - Paused\nws://{HOTSPOT_IP}:{state.ws_port}"
    elif len(state.connected_clients) > 0:
        icon.icon = create_icon_connected()
        client_count = len(state.connected_clients)
        icon.title = f"Voice Coding - {client_count} Connected\nws://{HOTSPOT_IP}:{state.ws_port}"
    else:
        icon.title = f"Voice Coding - Waiting\nws://{HOTSPOT_IP}:{state.ws_port}"
        start_blink_timer(icon)


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

    # Start HTTP server in background thread
    http_thread = threading.Thread(target=run_http_server, daemon=True)
    http_thread.start()

    # Start HTTPS server in background thread (for PWA install support)
    if state.https_enabled:
        https_thread = threading.Thread(target=run_https_server, daemon=True)
        https_thread.start()

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
