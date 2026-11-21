"""QR 码弹窗与扫码成功态遮罩（Qt UI）。

性能要点（2026-11-20 优化）：
    * 只有弹窗可见时才刷新 payload（隐藏状态不跑定时器、不做重复生成）。
    * payload 优先取共享接口快照（TTL 缓存），不再每次强制 psutil + tailscale 子进程枚举。
    * payload 不变时直接复用已生成的 QPixmap，避免每 5s 重新 qrcode 编码（实测 ~24ms）。
    * qrcode 采用函数内延迟 import：启动阶段少付 ~33ms，第一次需要生成二维码时再导入。
"""
from __future__ import annotations

import io
import json
import logging
import time

from PyQt5.QtCore import (
    QEasingCurve,
    QParallelAnimationGroup,
    QPointF,
    QPropertyAnimation,
    QRect,
    Qt,
    QTimer,
    pyqtProperty,
)
from PyQt5.QtGui import QColor, QFont, QPainter, QPen, QPixmap
from PyQt5.QtWidgets import (
    QApplication,
    QHBoxLayout,
    QLabel,
    QVBoxLayout,
    QWidget,
)
from PIL import Image

from device_identity import get_or_create_device_identity
from network_interfaces import get_primary_server_ip, get_qr_advertised_server_ips
from platform_utils import get_native_font_family
from voicing_protocol import build_qr_payload
from voicing_state import state
import voicing_tuning as tuning


class QRSuccessOverlay(QWidget):
    """QR 白底范围上的成功态遮罩与对勾动画。"""

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setAttribute(Qt.WA_TransparentForMouseEvents)
        self._shade_progress = 0.0
        self._check_progress = 0.0
        self._animation_group = None
        self.hide()

    def get_shade_progress(self):
        return self._shade_progress

    def set_shade_progress(self, value):
        self._shade_progress = max(0.0, min(1.0, float(value)))
        self.update()

    shadeProgress = pyqtProperty(
        float,
        fget=get_shade_progress,
        fset=set_shade_progress,
    )

    def get_check_progress(self):
        return self._check_progress

    def set_check_progress(self, value):
        self._check_progress = float(value)
        self.update()

    checkProgress = pyqtProperty(
        float,
        fget=get_check_progress,
        fset=set_check_progress,
    )

    def reset(self):
        self._stop_animation()
        self._shade_progress = 0.0
        self._check_progress = 0.0
        self.hide()
        self.update()

    def play(self):
        self._stop_animation()
        self._shade_progress = 0.0
        self._check_progress = 0.0
        self.show()
        self.raise_()

        shade_anim = QPropertyAnimation(self, b"shadeProgress", self)
        shade_anim.setDuration(180)
        shade_anim.setStartValue(0.0)
        shade_anim.setEndValue(1.0)
        shade_anim.setEasingCurve(QEasingCurve.OutCubic)

        check_anim = QPropertyAnimation(self, b"checkProgress", self)
        check_anim.setDuration(520)
        check_anim.setStartValue(0.0)
        check_anim.setEndValue(1.0)
        check_anim.setEasingCurve(QEasingCurve.OutBack)

        group = QParallelAnimationGroup(self)
        group.addAnimation(shade_anim)
        group.addAnimation(check_anim)
        self._animation_group = group
        group.start()

    def _stop_animation(self):
        if self._animation_group is not None:
            self._animation_group.stop()
            self._animation_group.deleteLater()
            self._animation_group = None

    def paintEvent(self, event):
        super().paintEvent(event)
        painter = QPainter(self)
        painter.setRenderHint(QPainter.Antialiasing, True)

        rect = self.rect().adjusted(-1, -1, 1, 1)
        shade_alpha = int(176 * self._shade_progress)
        painter.setPen(Qt.NoPen)
        painter.setBrush(QColor(0, 0, 0, shade_alpha))
        painter.drawRoundedRect(rect, 6, 6)

        raw_progress = self._check_progress
        progress = max(0.0, min(1.0, raw_progress))
        if progress <= 0:
            return

        center = QPointF(self.width() / 2, self.height() / 2)
        scale = 0.72 + 0.28 * progress + max(0.0, raw_progress - 1.0) * 0.34
        painter.save()
        painter.translate(center)
        painter.scale(scale, scale)

        ring_progress = min(1.0, progress / 0.82)
        ring_alpha = int(125 * (1.0 - ring_progress) * progress)
        if ring_alpha > 0:
            ring_pen = QPen(QColor(54, 222, 116, ring_alpha), 3)
            ring_pen.setCapStyle(Qt.RoundCap)
            painter.setPen(ring_pen)
            painter.setBrush(Qt.NoBrush)
            ring_radius = 25 + 32 * ring_progress
            painter.drawEllipse(QPointF(0, 0), ring_radius, ring_radius)

        check_alpha = int(255 * min(1.0, progress * 1.4))
        check_pen = QPen(QColor(54, 222, 116, check_alpha), 10)
        check_pen.setCapStyle(Qt.RoundCap)
        check_pen.setJoinStyle(Qt.RoundJoin)
        painter.setPen(check_pen)
        painter.setBrush(Qt.NoBrush)

        a = QPointF(-34, -2)
        b = QPointF(-11, 22)
        c = QPointF(36, -25)
        if progress < 0.46:
            t = progress / 0.46
            end = QPointF(a.x() + (b.x() - a.x()) * t, a.y() + (b.y() - a.y()) * t)
            painter.drawLine(a, end)
        else:
            painter.drawLine(a, b)
            t = (progress - 0.46) / 0.54
            end = QPointF(b.x() + (c.x() - b.x()) * t, b.y() + (c.y() - b.y()) * t)
            painter.drawLine(b, end)

        painter.restore()


class QRCodeDialog(QWidget):
    """QR 码弹窗 - 与托盘菜单同色同风格，直接在屏幕中心显示。"""

    DIALOG_WIDTH = 282
    DIALOG_HEIGHT = 308
    QR_SIZE = 230

    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowFlags(
            Qt.FramelessWindowHint
            | Qt.Tool
            | Qt.WindowStaysOnTopHint
            | Qt.NoDropShadowWindowHint
        )
        self.setAttribute(Qt.WA_TranslucentBackground)

        self._ignore_focus_loss = False
        self._anim_end_rect = None

        # Keep QR payload aligned with runtime IP changes（只在可见时运行）。
        self._refresh_timer = QTimer(self)
        self._refresh_timer.setInterval(tuning.QR_REFRESH_INTERVAL_MS)
        self._refresh_timer.timeout.connect(self._refresh_qr)

        self._cached_qr_payload = None
        self._cached_qr_pixmap = None
        self._applied_qr_payload = None
        self._scan_success_shown = False
        self._closing_after_success = False
        self._success_generation = 0

        self.setup_ui()

    def setup_ui(self):
        layout = QVBoxLayout(self)
        layout.setContentsMargins(8, 8, 8, 8)  # 阴影边距
        layout.setSpacing(0)

        self.container = QWidget()
        self.container.setObjectName("qrContainer")
        self.container.setStyleSheet("""
            QWidget#qrContainer {
                background-color: rgba(32, 32, 32, 245);
                border: 1px solid rgba(255, 255, 255, 0.08);
                border-radius: 8px;
            }
        """)
        cl = QVBoxLayout(self.container)
        # 左右下三边 10px，上方 padding 6（header 18 + spacing 6 额外占用）
        cl.setContentsMargins(10, 6, 10, 10)
        cl.setSpacing(6)

        # 顶栏：标题 + 关闭按钮（高度 24，容纳 14px 字号）
        header = QWidget()
        header.setFixedHeight(24)
        header_layout = QHBoxLayout(header)
        header_layout.setContentsMargins(0, 0, 0, 0)
        header_layout.setSpacing(0)

        title = QLabel("用 Voicing 手机端扫描")
        title_font = QFont(get_native_font_family())
        title_font.setPixelSize(14)
        title_font.setWeight(QFont.Bold)
        title.setFont(title_font)
        title.setStyleSheet("color: #FFFFFF; background: transparent;")
        # 水平 + 垂直 全部居中，避免 QLabel 默认上对齐造成文字偏上
        title.setAlignment(Qt.AlignHCenter | Qt.AlignVCenter)

        header_layout.addSpacing(24)
        header_layout.addStretch(1)
        header_layout.addWidget(title, 0, Qt.AlignVCenter)
        header_layout.addStretch(1)

        self.close_btn = QLabel("✕")
        close_font = QFont(get_native_font_family())
        close_font.setPixelSize(15)
        close_font.setWeight(QFont.Black)
        self.close_btn.setFont(close_font)
        self.close_btn.setFixedSize(24, 24)
        self.close_btn.setAlignment(Qt.AlignCenter)
        self.close_btn.setStyleSheet("""
            QLabel {
                color: #A0A0A0;
                background: transparent;
                border-radius: 12px;
            }
            QLabel:hover {
                color: #FFFFFF;
                background-color: rgba(255, 255, 255, 25);
            }
        """)
        self.close_btn.setCursor(Qt.PointingHandCursor)
        # 用事件过滤器处理点击（QLabel 没有 clicked 信号）
        self.close_btn.mousePressEvent = lambda e: self.close_with_animation()
        header_layout.addWidget(self.close_btn, 0, Qt.AlignVCenter)

        cl.addWidget(header)

        # QR 图像
        self.qr_label = QLabel()
        self.qr_label.setAlignment(Qt.AlignCenter)
        self.qr_label.setFixedSize(self.QR_SIZE + 16, self.QR_SIZE + 16)
        self.qr_label.setStyleSheet(
            "background-color: #FFFFFF;"
            "border-radius: 6px;"
            "padding: 8px;"
        )
        self.success_overlay = QRSuccessOverlay(self.qr_label)
        self.success_overlay.setGeometry(self.qr_label.rect())
        cl.addWidget(self.qr_label, alignment=Qt.AlignCenter)

        layout.addWidget(self.container)

        # 精确尺寸：窗口始终保持最终尺寸，避免 Wayland 上 resize/remap 闪烁。
        self.setFixedSize(self.DIALOG_WIDTH, self.DIALOG_HEIGHT)

    def _generate_qr_pixmap(self, payload: str) -> QPixmap:
        """生成 QR pixmap（黑底白点，反相成符合暗色 UI）。

        qrcode 延迟 import：启动阶段不需要二维码，import 成本（~33ms）放到首次生成时。
        PyInstaller 静态分析会扫描函数内 import，因此 onefile 仍会自动收集该依赖。
        """
        import qrcode

        qr = qrcode.QRCode(
            version=None,
            error_correction=qrcode.constants.ERROR_CORRECT_M,
            box_size=8,
            border=2,
        )
        qr.add_data(payload)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white").convert("RGBA")
        # 缩放到目标尺寸
        img = img.resize((self.QR_SIZE, self.QR_SIZE), Image.NEAREST)
        buf = io.BytesIO()
        img.save(buf, format="PNG")
        pix = QPixmap()
        pix.loadFromData(buf.getvalue())
        return pix

    def _refresh_qr(self):
        """Refresh QR payload from the current interface snapshot（仅可见时）。"""
        if not self.isVisible():
            logging.debug("QR 弹窗不可见，跳过定时刷新")
            return
        if self._populate_content():
            logging.info("QR payload 变化，已重建二维码")

    def _build_qr_payload(self):
        """构建 QR payload：优先用共享快照缓存，不触发强制枚举。"""
        device_identity = get_or_create_device_identity()
        advertised_ips = get_qr_advertised_server_ips()
        primary_ip = advertised_ips[0] if advertised_ips else get_primary_server_ip()
        payload = build_qr_payload(
            device_id=device_identity.device_id,
            ip=primary_ip,
            port=state.ws_port,
            name=device_identity.name,
            os_name=device_identity.os,
            ips=advertised_ips,
        )
        return json.dumps(payload, separators=(",", ":"))

    def _populate_content(self) -> bool:
        """填充 QR，返回是否重建了 pixmap（payload 不变时复用缓存）。"""
        payload = self._build_qr_payload()
        rebuilt = False
        if payload != self._cached_qr_payload or self._cached_qr_pixmap is None:
            started = time.perf_counter()
            self._cached_qr_pixmap = self._generate_qr_pixmap(payload)
            self._cached_qr_payload = payload
            self._applied_qr_payload = None
            rebuilt = True
            logging.debug(
                "QR pixmap 重建: payload=%d bytes, %.2f ms",
                len(payload),
                (time.perf_counter() - started) * 1000,
            )
        if self._applied_qr_payload != payload:
            self.qr_label.setPixmap(self._cached_qr_pixmap)
            self._applied_qr_payload = payload
        return rebuilt

    def show_from(self, anchor_global_pos):
        """在屏幕中心显示 QR 弹窗，不做跨窗口飞入动画。"""
        self._populate_content()
        self.success_overlay.reset()
        self._scan_success_shown = False
        self._closing_after_success = False
        self._success_generation += 1
        generation = self._success_generation

        end_rect = self._build_end_rect(anchor_global_pos)

        self._anim_end_rect = end_rect
        self._refresh_timer.stop()
        # 短暂忽略 focus-out，避免 Wayland show/activate 过程中的焦点事件把弹窗立即关闭。
        self._ignore_focus_loss = True
        self.setUpdatesEnabled(False)
        self.setGeometry(end_rect)
        self.setWindowOpacity(1.0)
        self.container.show()
        self.setUpdatesEnabled(True)
        self.show()
        self.raise_()
        self.activateWindow()
        self.setFocus(Qt.ActiveWindowFocusReason)
        self.repaint()
        QTimer.singleShot(120, lambda: self._finish_direct_open(generation))

    def _finish_direct_open(self, generation):
        if generation != self._success_generation or not self.isVisible():
            return
        self._ignore_focus_loss = False
        self._refresh_timer.start()

    def _build_end_rect(self, anchor_global_pos):
        screen = None
        if hasattr(QApplication, "screenAt"):
            screen = QApplication.screenAt(anchor_global_pos)
        if screen is None:
            screen = QApplication.primaryScreen()

        screen_geo = screen.availableGeometry() if screen else None
        if screen_geo is None:
            cx = anchor_global_pos.x()
            cy = anchor_global_pos.y()
        else:
            cx = screen_geo.center().x()
            cy = screen_geo.center().y()

        return QRect(
            cx - self.DIALOG_WIDTH // 2,
            cy - self.DIALOG_HEIGHT // 2,
            self.DIALOG_WIDTH,
            self.DIALOG_HEIGHT,
        )

    def show_scan_success(self):
        if not self.isVisible():
            logging.info("QR 成功态跳过：QR 弹窗当前不可见")
            return
        if self._scan_success_shown:
            logging.info("QR 成功态跳过：已播放")
            return
        self._scan_success_shown = True
        self._closing_after_success = False
        self._success_generation += 1
        generation = self._success_generation
        self.success_overlay.setGeometry(self.qr_label.rect())
        self.success_overlay.play()
        QTimer.singleShot(1150, lambda: self._close_after_success(generation))

    def _close_after_success(self, generation):
        if (
            generation == self._success_generation
            and self._scan_success_shown
            and self.isVisible()
        ):
            self._closing_after_success = True
            self.close_with_animation()

    def _finish_close(self):
        self._refresh_timer.stop()
        self.setUpdatesEnabled(False)
        self._ignore_focus_loss = False
        self.container.show()
        if self._anim_end_rect is not None:
            self.setFixedSize(self.DIALOG_WIDTH, self.DIALOG_HEIGHT)
            self.setGeometry(self._anim_end_rect)
        self.setUpdatesEnabled(True)
        self.hide()
        self.success_overlay.reset()
        self._scan_success_shown = False
        self._closing_after_success = False

    def close_with_animation(self):
        if not self.isVisible():
            return
        self._refresh_timer.stop()
        self._finish_close()

    def keyPressEvent(self, event):
        if event.key() == Qt.Key_Escape:
            self.close_with_animation()
        else:
            super().keyPressEvent(event)

    def focusOutEvent(self, event):
        """点击外部自动关闭"""
        # 延迟一帧检查，避免动画刚弹出就被自己 raise 触发关闭
        QTimer.singleShot(50, self._maybe_close_on_focus_loss)
        super().focusOutEvent(event)

    def _maybe_close_on_focus_loss(self):
        if self._ignore_focus_loss:
            return
        if self._scan_success_shown or self._closing_after_success:
            logging.info("QR 成功态期间忽略 focus-out 关闭")
            return
        if not self.isActiveWindow() and self.isVisible():
            self.close_with_animation()

    def mousePressEvent(self, event):
        """点弹窗内空白处不关闭，但点关闭按钮等已在子控件处理"""
        super().mousePressEvent(event)
