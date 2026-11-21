"""接口快照缓存 / 容器网桥过滤 / 枚举频次 单测（不触真实网络）。"""
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import network_interfaces as ni
from voice_coding import NetworkInterfaceCandidate


class FakeClock:
    def __init__(self, now=100.0):
        self.now = now

    def __call__(self):
        return self.now


class FakeDiscovery:
    def __init__(self, candidates):
        self.candidates = list(candidates)
        self.calls = 0

    def __call__(self):
        self.calls += 1
        return list(self.candidates)


def _candidate(ip, prefix=24, name="wlan0", interface_type="wifi"):
    return NetworkInterfaceCandidate(ip, prefix, name, interface_type)


class InterfaceSnapshotCacheTests(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.cache = ni.InterfaceSnapshotCache(ttl_sec=1.5, clock=self.clock)
        self.discover = FakeDiscovery([_candidate("192.168.50.113")])
        self.reader_calls = 0

        def reader():
            self.reader_calls += 1
            return None

        self.reader = reader

    def test_second_read_within_ttl_uses_cached_snapshot(self):
        first = self.cache.get(self.discover, self.reader)
        second = self.cache.get(self.discover, self.reader)

        self.assertEqual(self.discover.calls, 1, "TTL 内重复读取不应再次枚举")
        self.assertEqual(first.interfaces, second.interfaces)
        self.assertEqual(first.refresh_generation, second.refresh_generation)
        self.assertEqual(second.interfaces, (("192.168.50.113", "192.168.50.255"),))

    def test_read_after_ttl_refreshes_snapshot(self):
        self.cache.get(self.discover, self.reader)
        self.clock.now += 1.6
        snapshot = self.cache.get(self.discover, self.reader)

        self.assertEqual(self.discover.calls, 2)
        self.assertEqual(snapshot.refresh_generation, 2)

    def test_explicit_refresh_always_enumerates(self):
        self.cache.get(self.discover, self.reader)
        self.cache.get(self.discover, self.reader, refresh=True)

        self.assertEqual(self.discover.calls, 2, "显式 refresh=True 必须绕过 TTL")

    def test_force_false_refresh_reuses_recent_enumeration(self):
        # 模拟两个线程同时判定过期：后拿到 refresh_lock 的一方不应再枚举一次。
        self.cache.get(self.discover, self.reader)
        self.cache.refresh(self.discover, self.reader, force=False)

        self.assertEqual(self.discover.calls, 1)

    def test_version_changes_only_when_content_changes(self):
        first = self.cache.refresh(self.discover, self.reader)
        self.assertEqual(first.version, 1)

        second = self.cache.refresh(self.discover, self.reader)
        self.assertEqual(second.version, 1, "接口内容未变时 version 不应自增")
        self.assertEqual(second.refresh_generation, 2)

        self.discover.candidates = [_candidate("10.16.177.83", 18, "wlan0")]
        third = self.cache.refresh(self.discover, self.reader)
        self.assertEqual(third.version, 2)
        self.assertEqual(third.interfaces, (("10.16.177.83", "10.16.191.255"),))

    def test_tailscale_reader_result_is_cached_by_reader_identity(self):
        self.cache.refresh(self.discover, self.reader)
        self.cache.refresh(self.discover, self.reader)
        self.assertEqual(self.reader_calls, 1, "同一 reader 的 Tailscale CLI 结果应在 TTL 内复用")

        calls = 0

        def other_reader():
            nonlocal calls
            calls += 1
            return "100.102.136.4"

        snapshot = self.cache.refresh(self.discover, other_reader)
        self.assertEqual(calls, 1)
        self.assertEqual(
            snapshot.interfaces,
            (
                ("192.168.50.113", "192.168.50.255"),
                ("100.102.136.4", ""),
            ),
        )

    def test_bound_ips_are_deduplicated_and_isolated_from_interfaces(self):
        self.cache.set_bound_ips(["192.168.1.23", "192.168.1.23", "10.0.0.5"])
        self.assertEqual(self.cache.get_bound_ips(), ["192.168.1.23", "10.0.0.5"])
        self.assertEqual(self.cache.snapshot().interfaces, ())


class ModuleSnapshotCacheTests(unittest.TestCase):
    def setUp(self):
        ni.reset_interface_snapshot_cache()
        self.addCleanup(ni.reset_interface_snapshot_cache)
        self.discover = FakeDiscovery([_candidate("192.168.50.113")])

    def test_shared_snapshot_avoids_duplicate_enumeration_in_same_ttl(self):
        with (
            patch.object(ni, "get_all_network_candidates", self.discover),
            patch.object(ni, "_get_tailscale_ipv4", return_value=None),
        ):
            self.assertEqual(
                ni.refresh_server_interfaces(log_changes=False),
                [("192.168.50.113", "192.168.50.255")],
            )
            self.assertEqual(self.discover.calls, 1)

            # Qt 定时器 / server 监听循环 / QR 读取共享同一快照：不再触发枚举
            self.assertEqual(
                ni.get_advertised_server_ips(),
                ["192.168.50.113"],
            )
            self.assertEqual(ni.get_primary_server_ip(), "192.168.50.113")
            snapshot = ni.get_interface_snapshot()
            self.assertEqual(self.discover.calls, 1)

    def test_snapshot_generation_and_version_exposed_for_rebind_debounce(self):
        with (
            patch.object(ni, "get_all_network_candidates", self.discover),
            patch.object(ni, "_get_tailscale_ipv4", return_value=None),
        ):
            first = ni.get_interface_snapshot(refresh=True)
            second = ni.get_interface_snapshot()
            self.assertEqual(first.version, 1)
            self.assertEqual(second.version, 1)
            self.assertEqual(second.refresh_generation, first.refresh_generation)

            self.discover.candidates = [_candidate("10.16.177.83", 18, "wlan0")]
            third = ni.get_interface_snapshot(refresh=True)
            self.assertEqual(third.version, 2)
            self.assertGreater(third.refresh_generation, second.refresh_generation)


if __name__ == "__main__":
    unittest.main()
