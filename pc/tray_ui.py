"""托盘图标 / 菜单 / 图标缓存（Qt UI 线程）。

不变式（仓库 AGENTS.md）：
    * Linux 使用系统原生 ``QMenu``（``setContextMenu`` + 左键手动 popup），
      Windows/macOS 使用自定义 Fluent Popup；不要把 Linux 右键接回自定义菜单。
    * 定时器里不做无条件 ``setIcon()``：``update_icon`` 记录当前图标 key，只有
      状态真正变化才 setIcon（避免 Linux SNI/AppIndicator 宿主反复重建图标闪烁）。

启动性能（2026-11-20）：
    * 图标解码/缩放结果做缓存，``_pil_to_qicon`` 走 QImage 原始字节而不是 PNG 编解码。
    * QR 弹窗的创建与首帧 pixmap 预热从托盘构造热路径移出，托盘就绪后再做；
      首次点开 QR 时通常已预热完成，启动到托盘就绪更快。
"""
from __future__ import annotations

import logging
import os
import sys
from functools import lru_cache
from typing import Callable, Optional

from PyQt5.QtCore import (
    QEasingCurve,
    QParallelAnimationGroup,
    QPoint,
    QPropertyAnimation,
    Qt,
    QTimer,
    pyqtSignal,
)
from PyQt5.QtGui import (
    QColor,
    QCursor,
    QIcon,
    QImage,
    QPainter,
    QPixmap,
)
from PyQt5.QtWidgets import (
    QApplication,
    QGraphicsDropShadowEffect,
    QHBoxLayout,
    QLabel,
    QMenu,
    QSystemTrayIcon,
    QVBoxLayout,
    QWidget,
)
from PIL import Image, ImageDraw

from platform_autostart import is_startup_enabled, set_startup_enabled
from platform_utils import (
    get_log_dir,
    get_native_font_family,
    get_platform,
    open_file_in_default_app,
    open_file_in_text_editor,
)
from qr_dialog import QRCodeDialog
from voicing_state import state
import voicing_tuning as tuning


NATIVE_FONT_FAMILY = get_native_font_family()

# 装配层注入：Qt 主线程切换「同步输入」后，需要把 sync_state 广播投递到 asyncio loop。
# 用模块级回调而不是 import voice_coding，避免 tray_ui -> voice_coding 循环导入。
on_sync_state_changed: Optional[Callable[[], None]] = None


def _notify_sync_state_changed() -> None:
    callback = on_sync_state_changed
    if callback is None:
        logging.warning("同步状态广播跳过：装配层尚未注入广播回调")
        return
    try:
        callback()
    except Exception:  # noqa: BLE001 - UI 线程回调失败不能影响菜单交互
        logging.exception("同步状态广播回调失败")


def ensure_qr_dialog() -> QRCodeDialog:
    """懒加载 QR 弹窗；托盘预热/菜单点击共用。"""
    if state.qr_dialog is None:
        state.qr_dialog = QRCodeDialog()
    return state.qr_dialog


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
        self._animation_group = None

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

        # 显示 QR 码（最顶部）
        self.qr_btn = MenuItemWidget("📱", "显示 QR 码")
        self.qr_btn.clicked.connect(self.show_qr_dialog)
        container_layout.addWidget(self.qr_btn)

        # 同步输入
        self.sync_btn = MenuItemWidget("📡", "同步输入", has_toggle=True, is_checked=True)
        self.sync_btn.clicked.connect(self.toggle_sync)
        container_layout.addWidget(self.sync_btn)

        # 2026-09-25：此处原有「粘贴模式」循环切换项（自动/普通/终端/兼容）。
        # 终端 agent 场景移除后，Wayland 侧固定发送 Ctrl+V，该切换项已无存在意义，
        # 因此整项删除；如需恢复请从 git 历史取回 v2.9.9。
        # 开机自启
        self.startup_btn = MenuItemWidget("🚀", "开机自启", has_toggle=True, is_checked=False)
        self.startup_btn.clicked.connect(self.toggle_startup)
        container_layout.addWidget(self.startup_btn)

        # 打开日志
        log_btn = MenuItemWidget("📋", "打开日志")
        log_btn.clicked.connect(self.open_log)
        container_layout.addWidget(log_btn)

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
        # adjustSize() 对顶层 Popup 窗口给出的宽度偏大（实测比 sizeHint 多约 36px），
        # 导致菜单右边留白、宽度与文字不匹配。强制收紧到内容 sizeHint，使宽度随最长文字自适应。
        self.setFixedWidth(self.sizeHint().width())
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
        self._start_open_animation(x, animation_start_y, target_y)

    def _stop_animation_group(self):
        if self._animation_group is not None:
            self._animation_group.stop()
            self._animation_group.deleteLater()
            self._animation_group = None

    def _start_open_animation(self, x, animation_start_y, target_y):
        """使用 Qt 原生属性动画，避免 Python QTimer 每帧驱动窗口移动。"""
        self.animation_timer.stop()
        self._stop_animation_group()

        pos_anim = QPropertyAnimation(self, b"pos", self)
        pos_anim.setDuration(160)
        pos_anim.setStartValue(QPoint(x, animation_start_y))
        pos_anim.setEndValue(QPoint(x, target_y))
        pos_anim.setEasingCurve(QEasingCurve.OutQuad)

        opacity_anim = QPropertyAnimation(self, b"windowOpacity", self)
        opacity_anim.setDuration(120)
        opacity_anim.setStartValue(0.0)
        opacity_anim.setEndValue(1.0)
        opacity_anim.setEasingCurve(QEasingCurve.OutQuad)

        group = QParallelAnimationGroup(self)
        group.addAnimation(pos_anim)
        group.addAnimation(opacity_anim)
        group.finished.connect(lambda: self._finish_open_animation(target_y))
        self._animation_group = group
        group.start()

    def _finish_open_animation(self, target_y):
        self.move(self.pos().x(), target_y)
        self.setWindowOpacity(1.0)
        self._stop_animation_group()

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
        _notify_sync_state_changed()

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

    def show_qr_dialog(self):
        """显示 QR 码弹窗"""
        anchor = QCursor.pos()
        self.close_with_animation()
        ensure_qr_dialog().show_from(anchor)

    def quit_app(self):
        """退出应用"""
        state.running = False
        state.shutdown_event.set()
        QApplication.quit()

    def close_with_animation(self):
        """关闭动画"""
        self.animation_timer.stop()
        self._stop_animation_group()
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


# ============================================================
# Tray icon / 托盘图标
# ============================================================
class ModernTrayIcon(QSystemTrayIcon):
    """现代托盘图标"""

    def __init__(self, parent=None):
        super().__init__(parent)
        # 预先缓存图标
        self._icon_cache = {}
        # 记录当前生效的图标键，避免状态未变时重复 setIcon
        # （Linux SNI/AppIndicator 宿主每次 setIcon 都可能重建图标导致闪烁）
        self._current_icon_key = None
        self._init_icon_cache()
        # 菜单控件惰性创建：
        #   * Windows/macOS 需要自定义 Popup 菜单，必须启动时创建并预热；
        #   * Linux 只用系统原生 QMenu，自定义菜单控件仅作为回调/状态容器，
        #     不参与渲染。推迟到首次触发热路径（右键弹菜单/点击菜单项）再创建，
        #     实测省下 ~23ms 启动时间，且不改变任何入口行为。
        self.menu_widget = None
        if get_platform() != "linux":
            self.menu_widget = ModernMenuWidget()
            # 预热渲染：强制 Qt 提前编译 stylesheet 和计算布局
            self.menu_widget.move(-10000, -10000)
            self.menu_widget.show()
            QTimer.singleShot(50, self.menu_widget.hide)
        # 2026-11-20：QR 弹窗创建 + 首帧 pixmap 生成（实测 ~45ms）从启动热路径移出，
        # 推迟到事件循环启动后（托盘就绪之后）再预热；首次点开 QR 时通常已完成。
        QTimer.singleShot(tuning.QR_PREWARM_DELAY_MS, self._prewarm_qr_dialog)
        self.setup_icon()
        self.setup_menu()
        # 设置悬停提示
        self.setToolTip("Voicing")

    def _ensure_menu_widget(self) -> ModernMenuWidget:
        """惰性获取自定义菜单控件（Linux 上只作为回调容器）。"""
        if self.menu_widget is None:
            self.menu_widget = ModernMenuWidget()
        return self.menu_widget

    # Linux 原生菜单项的回调入口：真正执行时才需要自定义菜单控件，
    # 这样右键菜单本身不会因为创建控件而变慢。
    def _menu_show_qr_dialog(self):
        self._ensure_menu_widget().show_qr_dialog()

    def _menu_toggle_sync(self):
        # 惰性创建的自定义菜单控件初始为默认勾选态，先把真实 state 同步进去，
        # 否则在「已暂停」状态下点击原生菜单会算错新状态（会变成再次暂停）。
        widget = self._ensure_menu_widget()
        widget.update_state()
        widget.toggle_sync()

    def _menu_toggle_startup(self):
        widget = self._ensure_menu_widget()
        widget.update_state()
        widget.toggle_startup()

    def _menu_open_log(self):
        self._ensure_menu_widget().open_log()

    def _menu_quit_app(self):
        self._ensure_menu_widget().quit_app()


    def _prewarm_qr_dialog(self):
        """预热 QR 弹窗：只在还没有弹窗时做一次，失败不影响托盘。"""
        if state.qr_dialog is not None:
            return
        try:
            dialog = QRCodeDialog()
            dialog._populate_content()
            if get_platform() == "linux":
                # Wayland 禁止客户端自由定位顶层窗口，show() + move(-10000,-10000)
                # 会让窗口短暂可见地闪在屏幕左上角。这里只做样式与布局预热，不 show。
                dialog.ensurePolished()
                if dialog.layout() is not None:
                    dialog.layout().activate()
            else:
                dialog.move(-10000, -10000)
                dialog.show()
                QTimer.singleShot(50, dialog.hide)
            state.qr_dialog = dialog
            logging.debug("QR 弹窗预热完成")
        except Exception:  # noqa: BLE001 - 预热失败时首次点击仍会懒加载
            logging.exception("QR 弹窗预热失败，将在首次打开时同步创建")

    def _init_icon_cache(self):
        """预先生成并缓存所有状态的图标"""
        size = tuning.TRAY_ICON_CACHE_PX

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
        """PIL Image 转 QIcon。

        走 QImage 原始 RGBA 字节（避免 PNG 编码 + 解码往返，实测 3 个图标 ~80ms -> ~10ms）。
        ``.copy()`` 让 QImage 拥有独立缓冲区，避免 Python bytes 被回收后读到悬空内存。
        """
        rgba = pil_image.convert("RGBA")
        width, height = rgba.size
        raw = rgba.tobytes("raw", "RGBA")
        image = QImage(raw, width, height, width * 4, QImage.Format_RGBA8888).copy()
        return QIcon(QPixmap.fromImage(image))

    def setup_icon(self):
        """设置图标 - 复用已缓存的 normal QIcon，避免重复解码/缩放基础图标。"""
        icon = self._icon_cache.get('normal')
        if icon is None:
            icon = self._pil_to_qicon(load_base_icon(32))
        self.setIcon(icon)
        # 记录当前 key：随后 update_tray_icon_pyqt 首次刷新时若仍是 normal，就跳过 setIcon，
        # 减少 Linux 托盘宿主的一次重建（不改变最终显示状态）。
        self._current_icon_key = 'normal'

    def setup_menu(self):
        """设置菜单"""
        # 不使用 QMenu，而是自定义菜单
        self.activated.connect(self.on_tray_activated)
        if get_platform() == "linux":
            self._setup_native_context_menu()

    def _setup_native_context_menu(self):
        """Linux tray hosts may only show menus provided through setContextMenu."""
        self.native_menu = QMenu()
        # 默认 QMenu 给每项预留很大的水平 padding（实测 168px 宽 vs 文本 84px），
        # 右侧留白过多。收紧 item 内边距（左 20 留勾选框位、右 12 收窄），
        # 不改颜色/边框，保留 GTK 原生外观，只让宽度更贴合文字。
        self.native_menu.setStyleSheet(
            "QMenu::item { padding: 6px 12px 6px 20px; }"
        )

        qr_action = self.native_menu.addAction("显示 QR 码")
        qr_action.triggered.connect(self._menu_show_qr_dialog)

        self.native_sync_action = self.native_menu.addAction("同步输入")
        self.native_sync_action.setCheckable(True)
        self.native_sync_action.triggered.connect(self._menu_toggle_sync)

        self.native_startup_action = self.native_menu.addAction("开机自启")
        self.native_startup_action.setCheckable(True)
        self.native_startup_action.triggered.connect(self._menu_toggle_startup)

        log_action = self.native_menu.addAction("打开日志")
        log_action.triggered.connect(self._menu_open_log)

        quit_action = self.native_menu.addAction("退出应用")
        quit_action.triggered.connect(self._menu_quit_app)

        self.native_menu.aboutToShow.connect(self._sync_native_context_menu_state)
        self._sync_native_context_menu_state()
        self.setContextMenu(self.native_menu)

    def _sync_native_context_menu_state(self):
        # 不在这里创建自定义菜单控件：Linux 原生菜单的勾选状态直接读 state，
        # 避免每次右键都检查/构造一个不参与渲染的窗口。
        if self.menu_widget is not None:
            self.menu_widget.update_state()
        if hasattr(self, "native_sync_action"):
            self.native_sync_action.setChecked(state.sync_enabled)
        if hasattr(self, "native_startup_action"):
            self.native_startup_action.setChecked(is_startup_enabled())

    @staticmethod
    def _uses_native_menu():
        """Linux 改用系统原生 QMenu，避免自定义 Popup 在 GNOME/Wayland 下的渲染与定位问题。"""
        return get_platform() == "linux"

    @staticmethod
    def _should_show_custom_menu_for_activation_reason(reason):
        """Windows/macOS：左键 / 双击 / 右键都弹出自定义 Fluent 菜单。"""
        return reason in (
            QSystemTrayIcon.Trigger,
            QSystemTrayIcon.DoubleClick,
            QSystemTrayIcon.Context,
        )

    @staticmethod
    def _should_popup_native_menu_for_activation_reason(reason):
        """Linux：左键 / 双击时手动弹出原生菜单。

        右键（Context）交给 setContextMenu 让宿主处理；若这里也 popup 会与
        宿主的原生右键菜单叠加，造成同时弹两个菜单。
        """
        return reason in (
            QSystemTrayIcon.Trigger,
            QSystemTrayIcon.DoubleClick,
        )

    def on_tray_activated(self, reason):
        """托盘图标激活事件。

        Linux 上由 setContextMenu + 左键 popup 共同提供原生菜单，右键完全交给
        宿主以避免双菜单叠加；其他平台沿用自定义菜单。
        """
        if self._uses_native_menu():
            if self._should_popup_native_menu_for_activation_reason(reason):
                self._popup_native_menu()
        elif self._should_show_custom_menu_for_activation_reason(reason):
            self.show_custom_menu()

    def _popup_native_menu(self):
        """弹出 Linux 原生托盘菜单，并同步开关状态。"""
        self._sync_native_context_menu_state()
        self.native_menu.popup(QCursor.pos())

    def show_custom_menu(self):
        """显示自定义菜单"""
        # 更新状态
        self.menu_widget.update_state()

        # 获取托盘图标位置并显示菜单（带动画）
        pos = QCursor.pos()
        self.menu_widget.show_at_position(pos)

    def update_icon(self, status, dim=False):
        """更新图标状态 - 使用缓存的图标，仅在目标图标真正变化时才 setIcon。

        Linux SNI/AppIndicator 宿主每次 setIcon 都可能重建图标导致托盘闪烁，
        因此记录当前生效的图标键，状态未变时跳过 setIcon。

        Args:
            status: 未使用，保留兼容
            dim: 是否为暗淡状态（用于闪烁效果）
        """
        if not state.sync_enabled:
            # 暂停状态
            icon_key = 'paused'
        elif len(state.connected_clients) == 0 and dim:
            # 等待连接 + 暗淡状态
            icon_key = 'dim'
        else:
            # 正常状态（已连接或等待连接的亮状态）
            icon_key = 'normal'
        if icon_key != self._current_icon_key:
            self._current_icon_key = icon_key
            self.setIcon(self._icon_cache[icon_key])


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
# Icon assets / 图标资源
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


@lru_cache(maxsize=8)
def load_base_icon(size: int = 64) -> Image.Image:
    """加载并缩放基础图标（结果缓存，避免启动时多次解码 1024px 原图）。"""
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
