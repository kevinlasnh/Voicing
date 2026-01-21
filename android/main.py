"""
Voice Coding - Android Application (Kivy)
语音编程 - 安卓端应用

A simple app to send text to PC via WebSocket.
简单的应用，通过WebSocket发送文本到电脑。
"""

from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.uix.textinput import TextInput
from kivy.uix.label import Label
from kivy.uix.popup import Popup
from kivy.clock import Clock
from kivy.core.clipboard import Clipboard
from kivy.utils import platform
from kivy.properties import StringProperty, BooleanProperty

import json
import threading

# WebSocket client
try:
    import websocket
    HAS_WEBSOCKET = True
except ImportError:
    HAS_WEBSOCKET = False


class VoiceCodingApp(App):
    """Main application class / 主应用类"""
    
    connection_status = StringProperty("Disconnected / 未连接")
    is_connected = BooleanProperty(False)
    
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.ws = None
        self.server_ip = ""
        self.server_port = "9527"
        
    def build(self):
        """Build the UI / 构建界面"""
        self.title = "Voice Coding"
        
        # Main layout
        layout = BoxLayout(orientation='vertical', padding=20, spacing=15)
        
        # Title
        title = Label(
            text="Voice Coding\n语音编程",
            font_size='24sp',
            size_hint_y=0.15,
            halign='center'
        )
        layout.add_widget(title)
        
        # Connection section
        conn_layout = BoxLayout(orientation='horizontal', size_hint_y=0.1, spacing=10)
        
        self.ip_input = TextInput(
            hint_text="PC IP (e.g., 192.168.1.100:9527)",
            multiline=False,
            size_hint_x=0.7,
            font_size='16sp'
        )
        conn_layout.add_widget(self.ip_input)
        
        self.connect_btn = Button(
            text="Connect\n连接",
            size_hint_x=0.3,
            on_press=self.toggle_connection
        )
        conn_layout.add_widget(self.connect_btn)
        
        layout.add_widget(conn_layout)
        
        # Status label
        self.status_label = Label(
            text=self.connection_status,
            font_size='14sp',
            size_hint_y=0.05,
            color=(0.5, 0.5, 0.5, 1)
        )
        layout.add_widget(self.status_label)
        
        # Text input area
        self.text_input = TextInput(
            hint_text="Type or voice input here...\n在这里输入或语音输入...",
            multiline=True,
            size_hint_y=0.5,
            font_size='18sp'
        )
        layout.add_widget(self.text_input)
        
        # Buttons row
        btn_layout = BoxLayout(orientation='horizontal', size_hint_y=0.12, spacing=10)
        
        clear_btn = Button(
            text="Clear\n清空",
            on_press=self.clear_text
        )
        btn_layout.add_widget(clear_btn)
        
        paste_btn = Button(
            text="Paste\n粘贴",
            on_press=self.paste_text
        )
        btn_layout.add_widget(paste_btn)
        
        self.send_btn = Button(
            text="Send\n发送",
            on_press=self.send_text,
            background_color=(0.2, 0.7, 0.3, 1)
        )
        btn_layout.add_widget(self.send_btn)
        
        layout.add_widget(btn_layout)
        
        # Quick send checkbox info
        info_label = Label(
            text="Tip: Use your phone's voice keyboard for voice input!\n提示：使用手机自带的语音键盘进行语音输入！",
            font_size='12sp',
            size_hint_y=0.08,
            color=(0.6, 0.6, 0.6, 1)
        )
        layout.add_widget(info_label)
        
        return layout
    
    def toggle_connection(self, instance):
        """Toggle WebSocket connection / 切换WebSocket连接"""
        if self.is_connected:
            self.disconnect()
        else:
            self.connect()
    
    def connect(self):
        """Connect to PC server / 连接到电脑服务器"""
        ip_text = self.ip_input.text.strip()
        
        if not ip_text:
            self.show_message("Error / 错误", "Please enter PC IP address\n请输入电脑IP地址")
            return
        
        # Parse IP and port
        if ":" in ip_text:
            parts = ip_text.split(":")
            self.server_ip = parts[0]
            self.server_port = parts[1]
        else:
            self.server_ip = ip_text
            self.server_port = "9527"
        
        # Connect in background thread
        self.connection_status = "Connecting... / 连接中..."
        self.status_label.text = self.connection_status
        
        threading.Thread(target=self._connect_ws, daemon=True).start()
    
    def _connect_ws(self):
        """WebSocket connection thread / WebSocket连接线程"""
        try:
            ws_url = f"ws://{self.server_ip}:{self.server_port}"
            self.ws = websocket.create_connection(ws_url, timeout=5)
            
            # Wait for welcome message
            response = self.ws.recv()
            data = json.loads(response)
            
            if data.get("type") == "connected":
                Clock.schedule_once(lambda dt: self._on_connected(), 0)
            else:
                Clock.schedule_once(lambda dt: self._on_connect_failed("Unexpected response"), 0)
                
        except Exception as e:
            Clock.schedule_once(lambda dt, err=str(e): self._on_connect_failed(err), 0)
    
    def _on_connected(self):
        """Called when connected / 连接成功时调用"""
        self.is_connected = True
        self.connection_status = f"Connected to {self.server_ip} ✓\n已连接到 {self.server_ip} ✓"
        self.status_label.text = self.connection_status
        self.status_label.color = (0.2, 0.7, 0.3, 1)
        self.connect_btn.text = "Disconnect\n断开"
    
    def _on_connect_failed(self, error):
        """Called when connection failed / 连接失败时调用"""
        self.is_connected = False
        self.connection_status = f"Failed: {error}\n连接失败"
        self.status_label.text = self.connection_status
        self.status_label.color = (0.8, 0.2, 0.2, 1)
        self.ws = None
    
    def disconnect(self):
        """Disconnect from server / 断开连接"""
        if self.ws:
            try:
                self.ws.close()
            except:
                pass
            self.ws = None
        
        self.is_connected = False
        self.connection_status = "Disconnected / 未连接"
        self.status_label.text = self.connection_status
        self.status_label.color = (0.5, 0.5, 0.5, 1)
        self.connect_btn.text = "Connect\n连接"
    
    def send_text(self, instance):
        """Send text to PC / 发送文本到电脑"""
        if not self.is_connected or not self.ws:
            self.show_message("Error / 错误", "Not connected to PC\n未连接到电脑")
            return
        
        text = self.text_input.text.strip()
        if not text:
            self.show_message("Error / 错误", "No text to send\n没有要发送的文本")
            return
        
        try:
            # Send as JSON packet
            message = json.dumps({
                "type": "text",
                "content": text
            })
            self.ws.send(message)
            
            # Wait for acknowledgment
            response = self.ws.recv()
            data = json.loads(response)
            
            if data.get("type") == "ack":
                # Clear input after successful send
                self.text_input.text = ""
                self.show_toast("Sent! / 已发送!")
            else:
                self.show_message("Error / 错误", "Failed to send\n发送失败")
                
        except Exception as e:
            self.show_message("Error / 错误", f"Send failed: {e}\n发送失败")
            self.disconnect()
    
    def clear_text(self, instance):
        """Clear text input / 清空文本输入"""
        self.text_input.text = ""
    
    def paste_text(self, instance):
        """Paste from clipboard / 从剪贴板粘贴"""
        try:
            text = Clipboard.paste()
            if text:
                self.text_input.text = text
        except:
            pass
    
    def show_message(self, title, message):
        """Show popup message / 显示弹窗消息"""
        content = BoxLayout(orientation='vertical', padding=10)
        content.add_widget(Label(text=message))
        btn = Button(text="OK", size_hint_y=0.3)
        content.add_widget(btn)
        
        popup = Popup(title=title, content=content, size_hint=(0.8, 0.4))
        btn.bind(on_press=popup.dismiss)
        popup.open()
    
    def show_toast(self, message):
        """Show brief toast message / 显示短暂提示"""
        # Simple implementation - change status briefly
        old_status = self.status_label.text
        old_color = self.status_label.color
        
        self.status_label.text = message
        self.status_label.color = (0.2, 0.7, 0.3, 1)
        
        def restore(dt):
            self.status_label.text = old_status
            self.status_label.color = old_color
        
        Clock.schedule_once(restore, 1.5)
    
    def on_stop(self):
        """Called when app stops / 应用停止时调用"""
        self.disconnect()


if __name__ == '__main__':
    VoiceCodingApp().run()
