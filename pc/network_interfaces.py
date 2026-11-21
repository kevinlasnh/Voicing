"""网络接口发现 / 候选构建 / 排序 / Tailscale 读取 / QR 与监听地址快照。

职责边界：
    * 只做「网络地址」这一件事，不碰 Qt 与 WebSocket；``qr_dialog`` / ``tray_ui`` /
      ``voicing_server`` 都从这里取地址。
    * 对外只暴露物理私有 IPv4（过滤 loopback / link-local / VPN / 容器网桥 / 虚拟接口）。
    * 快照默认缓存 ``NETWORK_SNAPSHOT_TTL_SEC`` 秒：Qt 定时器、server 监听循环和
      QR 刷新共享同一次 psutil 枚举，避免同一秒内重复全量探测；显式 ``refresh=True``
      始终强制重新枚举。Tailscale 地址来自 ``tailscale ip -4`` 子进程（约 8ms），
      单独用更长的 TTL 缓存，并以 reader 函数对象身份做缓存键（单测替换 reader 时
      自动失效，不会读到上一次的旧值）。
"""
from __future__ import annotations

import ipaddress
import json
import logging
import re
import socket
import subprocess
import threading
import time
from typing import NamedTuple, Optional

try:
    import psutil
except Exception:  # pragma: no cover - 依赖缺失时走命令兜底
    psutil = None

from platform_utils import (
    WINDOWS_HOTSPOT_PREFIXES,
    get_default_server_ip,
    get_known_hotspot_prefixes,
    get_platform,
    get_preferred_hotspot_prefixes,
    system_subprocess_env,
)
import voicing_tuning as tuning


# Platform discovery default IP / 平台默认发现 IP
DEFAULT_SERVER_IP = get_default_server_ip()


class NetworkInterfaceCandidate(NamedTuple):
    ip: str
    prefix_length: int
    name: str
    interface_type: str


class InterfaceSnapshot(NamedTuple):
    """一次接口快照；version 只在内容变化时自增，refresh_generation 每次真实枚举自增。

    ``refresh_generation`` 用于监听重绑防抖：只有「新一次真实枚举」才算一次采样，
    单纯读取 TTL 缓存不会累计确认次数，避免抖动期间缓存重复读数被当成多次确认。
    """

    interfaces: tuple[tuple[str, str], ...]
    version: int
    refresh_generation: int


# ============================================================
# 物理网卡枚举 / Candidate discovery
# ============================================================
def get_hotspot_ip() -> str:
    """Get the actual hotspot IP address / 获取热点的实际 IP 地址。"""
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
    """Get all local IP addresses / 获取所有本地 IP 地址。"""
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


def get_all_network_candidates() -> list[NetworkInterfaceCandidate]:
    """Return physical-ish private IPv4 interfaces sorted by connection priority."""
    platform_name = get_platform()
    candidates = get_psutil_network_candidates(platform_name)
    if candidates:
        return candidates
    return get_command_network_candidates(platform_name)


def get_psutil_network_candidates(
    platform_name: str,
    psutil_module=None,
) -> list[NetworkInterfaceCandidate]:
    """Fast in-process interface discovery used for runtime QR/WS refresh.

    ``psutil_module`` 允许入口兼容层注入（旧测试通过替换 ``voice_coding.psutil``
    来模拟接口表，必须让注入值真正参与枚举）。
    """
    psutil_impl = psutil_module if psutil_module is not None else psutil
    if psutil_impl is None:
        return []

    try:
        adapters = psutil_impl.net_if_addrs()
    except Exception as exc:
        logging.debug(f"psutil 网络接口探测失败: {exc}")
        return []

    interfaces: list[NetworkInterfaceCandidate] = []
    seen: set[tuple[str, int]] = set()
    for interface_name, addresses in adapters.items():
        for address in addresses:
            if address.family != socket.AF_INET:
                continue
            prefix_length = _prefix_length_from_netmask(address.netmask)
            candidate = _build_network_interface_candidate(
                platform_name,
                address.address,
                prefix_length,
                interface_name,
            )
            if candidate is None:
                continue
            key = (candidate.ip, candidate.prefix_length)
            if key in seen:
                continue
            seen.add(key)
            interfaces.append(candidate)

    return _sort_interface_candidates(interfaces, platform_name)


def get_command_network_candidates(
    platform_name: str | None = None,
) -> list[NetworkInterfaceCandidate]:
    """Slower command-based fallback for platforms without psutil."""
    platform_name = platform_name or get_platform()
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

    return extract_command_interface_candidates(platform_name, result.stdout)


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
    return [
        (candidate.ip, candidate.prefix_length)
        for candidate in get_all_network_candidates()
    ]


def extract_command_interfaces(platform_name: str, command_output: str) -> list[tuple[str, int]]:
    return [
        (candidate.ip, candidate.prefix_length)
        for candidate in extract_command_interface_candidates(platform_name, command_output)
    ]


def _prefix_length_from_netmask(netmask: str | None) -> Optional[int]:
    if not netmask:
        return None
    try:
        return ipaddress.IPv4Network(f"0.0.0.0/{netmask}").prefixlen
    except ValueError:
        return None


def _build_network_interface_candidate(
    platform_name: str,
    ip: str,
    prefix_length: Optional[int],
    name: str = "",
) -> Optional[NetworkInterfaceCandidate]:
    try:
        normalized_prefix = int(prefix_length)
    except (TypeError, ValueError):
        return None
    if not _is_discoverable_private_ip(ip, normalized_prefix):
        return None
    normalized_name = str(name or "").strip()
    if _is_vpn_or_virtual_interface(platform_name, normalized_name):
        logging.debug(
            "过滤虚拟/容器/VPN 接口（不进入 QR/WS 候选）: %s ip=%s",
            normalized_name,
            ip,
        )
        return None
    return NetworkInterfaceCandidate(
        ip=ip,
        prefix_length=normalized_prefix,
        name=normalized_name,
        interface_type=_classify_interface_type(platform_name, normalized_name),
    )


def extract_command_interface_candidates(
    platform_name: str,
    command_output: str,
) -> list[NetworkInterfaceCandidate]:
    command_output = command_output.strip()
    if not command_output:
        return []

    interfaces: list[NetworkInterfaceCandidate] = []
    seen: set[tuple[str, int]] = set()

    def add_interface(ip: str, prefix_length: int, name: str = "") -> None:
        interface = _build_network_interface_candidate(
            platform_name,
            ip,
            prefix_length,
            name,
        )
        if interface is None:
            return
        candidate = (interface.ip, interface.prefix_length)
        if candidate in seen:
            return
        seen.add(candidate)
        interfaces.append(interface)

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
                    add_interface(
                        record.get("IPAddress", ""),
                        record.get("PrefixLength"),
                        record.get("InterfaceAlias", ""),
                    )
                return _sort_interface_candidates(interfaces, platform_name)
        except json.JSONDecodeError:
            pass

        for ip, prefix_length in re.findall(
            r"(\d{1,3}(?:\.\d{1,3}){3})\s+(\d{1,2})",
            command_output,
        ):
            add_interface(ip, int(prefix_length))
        return _sort_interface_candidates(interfaces, platform_name)

    if platform_name == "linux":
        try:
            records = json.loads(command_output)
            if not isinstance(records, list):
                return []
            for record in records:
                if not isinstance(record, dict):
                    continue
                interface_name = str(record.get("ifname", ""))
                for addr_info in record.get("addr_info", []):
                    if not isinstance(addr_info, dict):
                        continue
                    if addr_info.get("family") != "inet":
                        continue
                    if addr_info.get("scope") != "global":
                        continue
                    if "broadcast" not in addr_info:
                        continue
                    add_interface(
                        addr_info.get("local", ""),
                        addr_info.get("prefixlen"),
                        interface_name,
                    )
        except json.JSONDecodeError:
            pass
        return _sort_interface_candidates(interfaces, platform_name)

    if platform_name == "darwin":
        supports_broadcast = False
        interface_name = ""
        for raw_line in command_output.splitlines():
            line = raw_line.rstrip()
            header_match = re.match(r"^([^\s:]+):\s+flags=\d+<([^>]*)>", line)
            if header_match:
                interface_name = header_match.group(1)
                flags = {flag.strip().upper() for flag in header_match.group(2).split(",")}
                supports_broadcast = (
                    "UP" in flags
                    and "BROADCAST" in flags
                    and "POINTOPOINT" not in flags
                    and not _is_vpn_or_virtual_interface(platform_name, interface_name)
                )
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
            add_interface(match.group(1), prefix_length, interface_name)
        return _sort_interface_candidates(interfaces, platform_name)

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


# ============================================================
# 过滤与排序 / Filtering & sorting
# ============================================================
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


# 2026-11-20：容器 / 虚拟网桥接口名过滤。
# 现场日志里 172.17.0.1/16（docker0）会混进 QR ips 与监听列表：手机不可达，还会
# 干扰 Android 候选轮询，甚至让服务绑定到仅本机可见的网桥地址。这里按接口名前缀
# 排除常见容器/虚拟桥（Docker、veth pair、libvirt、LXC、Podman、CNI/Calico、
# kube-ipvs、VMware/VirtualBox host-only 等），物理网卡与 Tailscale 逻辑不变。
_CONTAINER_OR_BRIDGE_PREFIXES = (
    "docker",
    "veth",
    "br-",
    "virbr",
    "lxc",
    "podman",
    "cni",
    "flannel",
    "cali",
    "kube",
    "vnet",
    "vmnet",
    "vboxnet",
)


def _is_vpn_or_virtual_interface(platform_name: str, interface_name: str) -> bool:
    normalized = interface_name.lower()
    if not normalized:
        return False

    windows_markers = (
        "tap",
        "wintun",
        "wireguard",
        "pangp",
        "cisco anyconnect",
        "openvpn",
        "hyper-v",
        "vethernet",
        "tailscale",
        "zerotier",
        "docker",
        "veth",
    )
    if platform_name == "windows":
        return any(marker in normalized for marker in windows_markers)

    unix_vpn_prefixes = ("tun", "tap", "utun", "wg", "ppp", "tailscale", "zt")
    if platform_name in {"linux", "darwin"}:
        return normalized.startswith(unix_vpn_prefixes + _CONTAINER_OR_BRIDGE_PREFIXES)

    return False


def _classify_interface_type(platform_name: str, interface_name: str) -> str:
    normalized = interface_name.lower()
    if platform_name == "windows":
        if "ethernet" in normalized or "以太网" in interface_name:
            return "ethernet"
        if (
            "wi-fi" in normalized
            or "wifi" in normalized
            or "wlan" in normalized
            or "wireless" in normalized
            or "local area connection" in normalized
        ):
            return "wifi"
        return "unknown"

    if platform_name == "linux":
        if re.match(r"^(eth|en[opsx])", normalized):
            return "ethernet"
        if re.match(r"^(wlan|wlp|wlx)", normalized):
            return "wifi"
        return "unknown"

    if platform_name == "darwin":
        if re.match(r"^en\d+$", normalized):
            return "unknown"
        return "unknown"

    return "unknown"


def _sort_ip_addresses(ips: list[str]) -> list[str]:
    return sorted(ips, key=_ip_sort_key)


def _sort_interfaces(interfaces: list[tuple[str, int]]) -> list[tuple[str, int]]:
    return sorted(interfaces, key=lambda item: (_ip_sort_key(item[0]), item[1]))


def _sort_interface_candidates(
    interfaces: list[NetworkInterfaceCandidate],
    platform_name: str,
) -> list[NetworkInterfaceCandidate]:
    priority = {
        "ethernet": 0,
        "wifi": 1,
        "unknown": 2,
    }
    return sorted(
        interfaces,
        key=lambda item: (
            _windows_hotspot_rank(platform_name, item.ip),
            priority.get(item.interface_type, 3),
            _ip_sort_key(item.ip),
            item.prefix_length,
            item.name.lower(),
        ),
    )


def _windows_hotspot_rank(platform_name: str, ip: str) -> int:
    if platform_name == "windows" and any(
        ip.startswith(prefix) for prefix in WINDOWS_HOTSPOT_PREFIXES
    ):
        return 0
    return 1


def _ip_sort_key(ip: str) -> tuple[int, str]:
    if any(ip.startswith(prefix) for prefix in get_preferred_hotspot_prefixes()):
        return (0, ip)
    if any(ip.startswith(prefix) for prefix in get_known_hotspot_prefixes()):
        return (1, ip)
    return (2, ip)


# ============================================================
# Tailscale 读取 / Tailscale discovery
# ============================================================
def _is_tailscale_cgnat_ip(ip: str) -> bool:
    """2026-09-25 新增：判断地址是否落在 Tailscale 使用的 100.64.0.0/10 段。"""
    try:
        return ipaddress.IPv4Address(ip) in ipaddress.IPv4Network("100.64.0.0/10")
    except ipaddress.AddressValueError:
        return False


def _get_tailscale_ipv4() -> Optional[str]:
    """2026-09-25 新增：读取本机 Tailscale IPv4，取不到返回 None。

    背景：用户手机开启 Tailscale 后完全连不上 PC。Android 在 VPN lockdown 模式下
    会禁止 socket 绕过 VPN，此时唯一可达的路径是 Tailscale 隧道；但 tailscale0 是
    /32 的 CGNAT 地址，会被 _is_vpn_or_virtual_interface（接口名含 tailscale）和
    _is_discoverable_private_ip（is_private 为假、前缀长度 32 超出 1..30）过滤掉，
    于是 QR 与 WebSocket 监听地址里都没有它，手机无路可走。

    这里改用 tailscale CLI 直接读地址，作为「额外候选」追加，不改动原有物理网卡
    枚举与排序，避免影响既有的 IP 选择行为。未安装、未登录或超时都静默返回 None，
    保持改动前的行为不变。
    """
    try:
        output = subprocess.check_output(
            ["tailscale", "ip", "-4"],
            env=system_subprocess_env(),
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=tuning.TAILSCALE_PROBE_TIMEOUT_SEC,
        )
    except Exception:
        return None
    for line in str(output).splitlines():
        candidate = line.strip()
        if candidate and _is_tailscale_cgnat_ip(candidate):
            return candidate
    return None


_TAILSCALE_CACHE_LOCK = threading.Lock()
_TAILSCALE_CACHE: dict[str, object] = {
    "reader": None,
    "ip": None,
    "read_at": float("-inf"),
}


def _tailscale_ipv4_cached(reader) -> Optional[str]:
    """按 reader 身份 + TTL 缓存 Tailscale CLI 读取结果。

    reader 用函数对象本身做缓存键：生产路径始终传同一个函数对象，命中缓存；
    单测用 patch 换掉 reader 时对象身份不同，自动 miss，避免测试间串味。
    """
    now = time.monotonic()
    with _TAILSCALE_CACHE_LOCK:
        if (
            _TAILSCALE_CACHE["reader"] is reader
            and now - float(_TAILSCALE_CACHE["read_at"]) < tuning.TAILSCALE_PROBE_TTL_SEC
        ):
            logging.debug("Tailscale 地址缓存命中: %s", _TAILSCALE_CACHE["ip"])
            return _TAILSCALE_CACHE["ip"]  # type: ignore[return-value]

    started = time.perf_counter()
    tailscale_ip = reader()
    duration_ms = (time.perf_counter() - started) * 1000
    with _TAILSCALE_CACHE_LOCK:
        _TAILSCALE_CACHE["reader"] = reader
        _TAILSCALE_CACHE["ip"] = tailscale_ip
        _TAILSCALE_CACHE["read_at"] = time.monotonic()
    logging.debug(
        "Tailscale 地址读取: %s (%.2f ms)",
        tailscale_ip or "none",
        duration_ms,
    )
    return tailscale_ip


def _append_tailscale_interface(
    interfaces: list[tuple[str, str]],
    tailscale_ipv4=None,
) -> list[tuple[str, str]]:
    """2026-09-25 新增：把 Tailscale 地址追加到服务接口列表末尾。

    顺序很关键：局域网/热点地址继续排在前面（QR 首选与既有行为不变），Tailscale
    地址只作为「开了 VPN 时仍然连得上」的兜底候选。Tailscale 是 /32 点对点地址，
    没有广播地址，这里用空字符串占位，调用方只用它取 IP 并做绑定。
    """
    reader = tailscale_ipv4 if tailscale_ipv4 is not None else _get_tailscale_ipv4
    tailscale_ip = _tailscale_ipv4_cached(reader)
    if not tailscale_ip:
        return interfaces
    if any(ip == tailscale_ip for ip, _broadcast in interfaces):
        return interfaces
    return [*interfaces, (tailscale_ip, "")]


# ============================================================
# 接口快照缓存 / Interface snapshot cache
# ============================================================
class InterfaceSnapshotCache:
    """TTL 接口快照：同一 TTL 窗口内所有调用方共享一次真实枚举。

    ``refresh_generation`` 每次真实枚举 +1，供监听重绑防抖判断「是否真的是新采样」；
    ``version`` 只在接口内容变化时 +1，供诊断日志减少噪声。
    ``interfaces`` 列表原地更新，旧代码里 ``SERVER_INTERFACES`` 的引用因此保持有效。
    """

    def __init__(self, *, ttl_sec: Optional[float] = None, clock=None) -> None:
        self._ttl_sec = tuning.NETWORK_SNAPSHOT_TTL_SEC if ttl_sec is None else float(ttl_sec)
        self._clock = clock or time.monotonic
        self._refresh_lock = threading.Lock()
        self._state_lock = threading.Lock()
        self.interfaces: list[tuple[str, str]] = []
        self._bound_ips: list[str] = []
        self._initialized = False
        self._version = 0
        self._refresh_generation = 0
        self._last_refresh_at = float("-inf")
        self._last_refresh_ms = 0.0

    @property
    def state_lock(self) -> threading.Lock:
        return self._state_lock

    @property
    def ttl_sec(self) -> float:
        return self._ttl_sec

    @property
    def initialized(self) -> bool:
        with self._state_lock:
            return self._initialized

    @property
    def version(self) -> int:
        with self._state_lock:
            return self._version

    @property
    def refresh_generation(self) -> int:
        with self._state_lock:
            return self._refresh_generation

    @property
    def last_refresh_ms(self) -> float:
        with self._state_lock:
            return self._last_refresh_ms

    def snapshot(self) -> InterfaceSnapshot:
        with self._state_lock:
            return InterfaceSnapshot(
                tuple(self.interfaces),
                self._version,
                self._refresh_generation,
            )

    def refresh(
        self,
        discover,
        tailscale_ipv4,
        *,
        log_changes: bool = True,
        force: bool = True,
    ) -> InterfaceSnapshot:
        """重新枚举；``force=False`` 时若另一线程刚在 TTL 内刷新过则直接复用。"""
        with self._refresh_lock:
            now = self._clock()
            with self._state_lock:
                recently_refreshed = (
                    self._initialized
                    and (now - self._last_refresh_at) < self._ttl_sec
                )
            if not force and recently_refreshed:
                return self.snapshot()

            started = time.perf_counter()
            candidates = discover()
            discovered_interfaces = calculate_broadcast_addresses(
                [(candidate.ip, candidate.prefix_length) for candidate in candidates]
            )
            latest_interfaces = _append_tailscale_interface(
                discovered_interfaces,
                tailscale_ipv4=tailscale_ipv4,
            )
            duration_ms = (time.perf_counter() - started) * 1000

            with self._state_lock:
                was_initialized = self._initialized
                previous_interfaces = list(self.interfaces)
                changed = latest_interfaces != self.interfaces
                if changed:
                    self.interfaces[:] = latest_interfaces
                self._initialized = True
                self._refresh_generation += 1
                if changed:
                    self._version += 1
                self._last_refresh_at = self._clock()
                self._last_refresh_ms = duration_ms
                snapshot = InterfaceSnapshot(
                    tuple(self.interfaces),
                    self._version,
                    self._refresh_generation,
                )

            if tuning.LOG_INTERFACE_ENUMERATIONS:
                logging.debug(
                    "网络接口枚举 #%d 完成: %.2f ms, 候选=%d, 快照=%d",
                    snapshot.refresh_generation,
                    duration_ms,
                    len(candidates),
                    len(snapshot.interfaces),
                )
            if log_changes and (changed or not was_initialized):
                logging.info(
                    "QR/WS 网络接口刷新（枚举耗时 %.2f ms）: "
                    f"{_format_server_interface_ips(previous_interfaces)} -> "
                    f"{_format_server_interface_ips(list(snapshot.interfaces))}",
                    duration_ms,
                )
                log_detected_network_interfaces(candidates)
            return snapshot

    def get(
        self,
        discover,
        tailscale_ipv4,
        *,
        refresh: bool = False,
        log_changes: bool = False,
    ) -> InterfaceSnapshot:
        with self._state_lock:
            fresh = (
                self._initialized
                and (self._clock() - self._last_refresh_at) < self._ttl_sec
            )
            if not refresh and fresh:
                return InterfaceSnapshot(
                    tuple(self.interfaces),
                    self._version,
                    self._refresh_generation,
                )
        return self.refresh(
            discover,
            tailscale_ipv4,
            log_changes=log_changes,
            force=refresh,
        )

    def set_bound_ips(self, hosts: list[str]) -> None:
        normalized_hosts = list(dict.fromkeys(hosts))
        with self._state_lock:
            self._bound_ips = normalized_hosts

    def get_bound_ips(self) -> list[str]:
        with self._state_lock:
            return list(self._bound_ips)

    def reset(self) -> None:
        """清空快照（仅测试用，模拟进程刚启动的状态）。"""
        with self._refresh_lock:
            with self._state_lock:
                self.interfaces[:] = []
                self._bound_ips = []
                self._initialized = False
                self._version = 0
                self._refresh_generation = 0
                self._last_refresh_at = float("-inf")
                self._last_refresh_ms = 0.0


_DEFAULT_CACHE = InterfaceSnapshotCache()
# 兼容旧代码/旧测试：SERVER_INTERFACES 与缓存内部列表是同一个对象（原地更新）。
SERVER_INTERFACES: list[tuple[str, str]] = _DEFAULT_CACHE.interfaces
SERVER_INTERFACES_LOCK = _DEFAULT_CACHE.state_lock


def _resolve_providers(discover=None, tailscale_ipv4=None):
    return (
        discover if discover is not None else get_all_network_candidates,
        tailscale_ipv4 if tailscale_ipv4 is not None else _get_tailscale_ipv4,
    )


def refresh_server_interfaces(
    *,
    log_changes: bool = True,
    discover=None,
    tailscale_ipv4=None,
) -> list[tuple[str, str]]:
    """Force-refresh the QR/WS interface snapshot from the current OS network state."""
    snapshot = _DEFAULT_CACHE.refresh(
        *_resolve_providers(discover, tailscale_ipv4),
        log_changes=log_changes,
        force=True,
    )
    return list(snapshot.interfaces)


def get_interface_snapshot(
    *,
    refresh: bool = False,
    discover=None,
    tailscale_ipv4=None,
) -> InterfaceSnapshot:
    return _DEFAULT_CACHE.get(
        *_resolve_providers(discover, tailscale_ipv4),
        refresh=refresh,
    )


def get_server_interfaces(
    *,
    refresh: bool = False,
    discover=None,
    tailscale_ipv4=None,
) -> list[tuple[str, str]]:
    snapshot = get_interface_snapshot(
        refresh=refresh,
        discover=discover,
        tailscale_ipv4=tailscale_ipv4,
    )
    return list(snapshot.interfaces)


def _format_server_interface_ips(interfaces: list[tuple[str, str]]) -> str:
    return ", ".join(ip for ip, _broadcast in interfaces) or "none"


def get_primary_server_ip(
    *,
    refresh: bool = False,
    discover=None,
    tailscale_ipv4=None,
) -> str:
    server_interfaces = get_server_interfaces(
        refresh=refresh,
        discover=discover,
        tailscale_ipv4=tailscale_ipv4,
    )
    if server_interfaces:
        return server_interfaces[0][0]
    return get_hotspot_ip()


def get_advertised_server_ips(
    *,
    refresh: bool = False,
    discover=None,
    tailscale_ipv4=None,
) -> list[str]:
    snapshot = get_interface_snapshot(
        refresh=refresh,
        discover=discover,
        tailscale_ipv4=tailscale_ipv4,
    )
    return get_advertised_server_ips_for_snapshot(snapshot)


def get_advertised_server_ips_for_snapshot(snapshot: InterfaceSnapshot) -> list[str]:
    ips: list[str] = []
    for ip, _broadcast in snapshot.interfaces:
        if ip not in ips:
            ips.append(ip)
    if not ips:
        fallback_ip = get_hotspot_ip()
        if fallback_ip:
            ips.append(fallback_ip)
    return ips


def get_bound_server_ips() -> list[str]:
    return _DEFAULT_CACHE.get_bound_ips()


def set_bound_server_ips(hosts: list[str]) -> None:
    _DEFAULT_CACHE.set_bound_ips(hosts)


def get_qr_advertised_server_ips(
    *,
    refresh: bool = False,
    discover=None,
    tailscale_ipv4=None,
) -> list[str]:
    bound_ips = get_bound_server_ips()
    if bound_ips:
        return bound_ips
    return get_advertised_server_ips(
        refresh=refresh,
        discover=discover,
        tailscale_ipv4=tailscale_ipv4,
    )


def is_snapshot_initialized() -> bool:
    return _DEFAULT_CACHE.initialized


def reset_interface_snapshot_cache() -> None:
    """清空默认快照缓存；仅供单测构造确定性的首次枚举场景。"""
    _DEFAULT_CACHE.reset()


def log_detected_network_interfaces(interfaces: list[NetworkInterfaceCandidate]) -> None:
    if not interfaces:
        logging.warning("未检测到可用于 QR 连接的私有 IPv4 接口。")
        logging.info(f"回退 QR IP: {get_hotspot_ip()}")
        return

    logging.info(f"检测到 {len(interfaces)} 个 QR 连接候选网络接口:")
    for candidate in interfaces:
        label = candidate.interface_type
        if any(candidate.ip.startswith(prefix) for prefix in get_known_hotspot_prefixes()):
            label = f"{label}/hotspot"
        logging.info(f"  - {candidate.ip}/{candidate.prefix_length} ({label}; {candidate.name or 'unknown'})")
