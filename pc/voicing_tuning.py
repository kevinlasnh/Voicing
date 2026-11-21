"""PC 端可调参数集中定义（超时 / 周期 / 缓存 TTL / 心跳 / 自适应阈值）。

为什么不用外部 YAML / all.config：
    PC 端最终以 PyInstaller onefile 形式发布，冻结后脚本解压到运行时临时目录，
    ``sys._MEIPASS`` 每次启动都不同，且用户机器上没有稳定可写的外部配置路径。
    如果在运行时读取外部 YAML，就会出现「开发环境能改、发布版改不到 / 被安全
    软件隔离」的割裂，因此这里把默认值随代码一起打包，用 ``VOICING_*`` 环境
    变量作为唯一覆盖通道；启动日志会逐项打印生效值，便于现场排障。

约定：
    * 键名与 ``VOICING_<KEY>`` 一一对应，单位体现在键名后缀（_SEC/_MS/_BYTES）。
    * 默认值只住在 ``_DEFAULTS``，算法代码不写魔法数字。
    * 环境变量解析失败时保留默认值并打 WARNING，绝不静默改动行为。
"""
from __future__ import annotations

import logging
import os
from typing import Any, Mapping

ENV_PREFIX = "VOICING_"
LOGGER = logging.getLogger(__name__)

# 默认值：键名 = 环境变量去掉 VOICING_ 前缀；类型由默认值本身决定。
_DEFAULTS: dict[str, Any] = {
    # 文本注入
    "AUTO_ENTER_SETTLE_DELAY_SEC": 0.35,   # Enter 前等待目标应用消费 paste 的静默期
    "TEXT_INPUT_RESTORE_DELAY_SEC": 0.1,   # 恢复原剪贴板前的等待
    # 网络接口快照：TTL 内所有调用方（Qt 定时器 + server 监听循环 + QR）共享一次枚举
    "NETWORK_SNAPSHOT_TTL_SEC": 1.5,
    "NETWORK_SNAPSHOT_POLL_SEC": 0.5,      # server 监听循环单次轮询间隔
    "REBIND_CONFIRMATIONS": 2,             # 同一新地址快照需连续确认的「新枚举次数」才重绑
    "TAILSCALE_PROBE_TTL_SEC": 5.0,        # tailscale CLI 结果缓存（子进程 ~8ms，单独缩短频率）
    "TAILSCALE_PROBE_TIMEOUT_SEC": 3.0,
    "SERVER_RETRY_DELAY_SEC": 2.0,         # 无可用监听地址时的重试间隔
    # WebSocket：协议层心跳只用于尽快发现死连接，App 层 ping/pong 契约不变
    "WS_PING_INTERVAL_SEC": 20.0,
    "WS_PING_TIMEOUT_SEC": 10.0,
    "WS_CLOSE_TIMEOUT_SEC": 5.0,
    "WS_MAX_SIZE_BYTES": 1024 * 1024,
    # QR 弹窗
    "QR_REFRESH_INTERVAL_MS": 5000,        # 弹窗可见时的 payload 刷新周期
    "QR_PREWARM_DELAY_MS": 250,            # 托盘就绪后再预热 QR（不阻塞启动）
    # 托盘
    "TRAY_ICON_UPDATE_INTERVAL_MS": 200,   # 闪烁定时器周期
    "TRAY_ICON_CACHE_PX": 256,             # 预生成图标尺寸
    # 日志
    "LOG_INTERFACE_ENUMERATIONS": True,    # 每次真实枚举打 DEBUG 耗时日志
}

_BOOL_TRUE = {"1", "true", "yes", "on"}
_BOOL_FALSE = {"0", "false", "no", "off"}


def _coerce(name: str, raw: str, default: Any) -> Any:
    """按默认值类型解析环境变量，非法值抛 ValueError 交给调用方回退。"""
    if isinstance(default, bool):
        lowered = raw.lower()
        if lowered in _BOOL_TRUE:
            return True
        if lowered in _BOOL_FALSE:
            return False
        raise ValueError("不是布尔值")
    if isinstance(default, int):
        value = int(raw)
        if value <= 0:
            raise ValueError("必须为正整数")
        return value
    if isinstance(default, float):
        value = float(raw)
        if value < 0:
            raise ValueError("不能为负数")
        return value
    return raw


def load_effective_values(
    environ: Mapping[str, str] | None = None,
) -> tuple[dict[str, Any], dict[str, str]]:
    """解析生效参数，返回 ``(values, overrides)``；纯函数，便于单测。"""
    source = os.environ if environ is None else environ
    values: dict[str, Any] = {}
    overrides: dict[str, str] = {}
    for name, default in _DEFAULTS.items():
        env_name = ENV_PREFIX + name
        raw = source.get(env_name)
        if raw is None or not str(raw).strip():
            values[name] = default
            continue
        raw = str(raw).strip()
        try:
            values[name] = _coerce(name, raw, default)
        except (TypeError, ValueError) as exc:
            LOGGER.warning(
                "环境变量 %s=%r 无效（%s），使用默认值 %r",
                env_name,
                raw,
                exc,
                default,
            )
            values[name] = default
            continue
        overrides[name] = raw
    return values, overrides


_VALUES, _OVERRIDES = load_effective_values()

# 模块级生效常量：其它模块直接 ``import voicing_tuning as tuning`` 后按名取值。
AUTO_ENTER_SETTLE_DELAY_SEC = _VALUES["AUTO_ENTER_SETTLE_DELAY_SEC"]
TEXT_INPUT_RESTORE_DELAY_SEC = _VALUES["TEXT_INPUT_RESTORE_DELAY_SEC"]
NETWORK_SNAPSHOT_TTL_SEC = _VALUES["NETWORK_SNAPSHOT_TTL_SEC"]
NETWORK_SNAPSHOT_POLL_SEC = _VALUES["NETWORK_SNAPSHOT_POLL_SEC"]
REBIND_CONFIRMATIONS = _VALUES["REBIND_CONFIRMATIONS"]
TAILSCALE_PROBE_TTL_SEC = _VALUES["TAILSCALE_PROBE_TTL_SEC"]
TAILSCALE_PROBE_TIMEOUT_SEC = _VALUES["TAILSCALE_PROBE_TIMEOUT_SEC"]
SERVER_RETRY_DELAY_SEC = _VALUES["SERVER_RETRY_DELAY_SEC"]
WS_PING_INTERVAL_SEC = _VALUES["WS_PING_INTERVAL_SEC"]
WS_PING_TIMEOUT_SEC = _VALUES["WS_PING_TIMEOUT_SEC"]
WS_CLOSE_TIMEOUT_SEC = _VALUES["WS_CLOSE_TIMEOUT_SEC"]
WS_MAX_SIZE_BYTES = _VALUES["WS_MAX_SIZE_BYTES"]
QR_REFRESH_INTERVAL_MS = _VALUES["QR_REFRESH_INTERVAL_MS"]
QR_PREWARM_DELAY_MS = _VALUES["QR_PREWARM_DELAY_MS"]
TRAY_ICON_UPDATE_INTERVAL_MS = _VALUES["TRAY_ICON_UPDATE_INTERVAL_MS"]
TRAY_ICON_CACHE_PX = _VALUES["TRAY_ICON_CACHE_PX"]
LOG_INTERFACE_ENUMERATIONS = _VALUES["LOG_INTERFACE_ENUMERATIONS"]


def _groups() -> list[tuple[str, tuple[str, ...]]]:
    return [
        (
            "文本注入",
            ("AUTO_ENTER_SETTLE_DELAY_SEC", "TEXT_INPUT_RESTORE_DELAY_SEC"),
        ),
        (
            "网络/自适应",
            (
                "NETWORK_SNAPSHOT_TTL_SEC",
                "NETWORK_SNAPSHOT_POLL_SEC",
                "REBIND_CONFIRMATIONS",
                "TAILSCALE_PROBE_TTL_SEC",
                "TAILSCALE_PROBE_TIMEOUT_SEC",
                "SERVER_RETRY_DELAY_SEC",
            ),
        ),
        (
            "WebSocket",
            (
                "WS_PING_INTERVAL_SEC",
                "WS_PING_TIMEOUT_SEC",
                "WS_CLOSE_TIMEOUT_SEC",
                "WS_MAX_SIZE_BYTES",
            ),
        ),
        (
            "UI",
            (
                "QR_REFRESH_INTERVAL_MS",
                "QR_PREWARM_DELAY_MS",
                "TRAY_ICON_UPDATE_INTERVAL_MS",
                "TRAY_ICON_CACHE_PX",
            ),
        ),
        ("日志", ("LOG_INTERFACE_ENUMERATIONS",)),
    ]


def format_effective_tuning() -> list[str]:
    """返回每行一个分组的生效参数文本；覆盖项标记 ``env`` 来源。"""
    lines = []
    for group, names in _groups():
        rendered = []
        for name in names:
            source = "env" if name in _OVERRIDES else "默认"
            rendered.append(f"{name}={_VALUES[name]!r}({source})")
        lines.append(f"{ENV_PREFIX}* 可调参数[{group}]: " + " ".join(rendered))
    if _OVERRIDES:
        lines.append(
            "环境变量覆盖: "
            + ", ".join(f"{ENV_PREFIX}{name}={value}" for name, value in _OVERRIDES.items())
        )
    return lines


def log_effective_tuning(logger: logging.Logger | None = None) -> None:
    """启动时把生效参数写入日志，便于现场确认实际使用的阈值。"""
    target = logger or LOGGER
    target.info("可调参数生效值（可用 VOICING_* 环境变量覆盖）:")
    for line in format_effective_tuning():
        target.info("  %s", line)
