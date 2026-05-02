import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import socket
import voice_coding
from voice_coding import (
    NetworkInterfaceCandidate,
    calculate_broadcast_addresses,
    extract_command_interface_candidates,
    extract_command_interfaces,
    get_advertised_server_ips,
    get_bound_server_ips,
    get_primary_server_ip,
    get_psutil_network_candidates,
    get_qr_advertised_server_ips,
    refresh_server_interfaces,
    set_bound_server_ips,
)


class NetworkInterfaceParsingTests(unittest.TestCase):
    def test_extract_command_interfaces_windows_filters_tentative_link_local_and_slash_32(self):
        output = """
[
  {"IPAddress":"169.254.42.11","PrefixLength":16,"InterfaceAlias":"Bluetooth","AddressState":1,"SkipAsSource":false},
  {"IPAddress":"192.168.1.23","PrefixLength":24,"InterfaceAlias":"Ethernet","AddressState":4,"SkipAsSource":false},
  {"IPAddress":"192.168.137.1","PrefixLength":24,"InterfaceAlias":"Local Area Connection* 10","AddressState":4,"SkipAsSource":false},
  {"IPAddress":"10.16.177.83","PrefixLength":18,"InterfaceAlias":"WLAN","AddressState":4,"SkipAsSource":false},
  {"IPAddress":"10.99.0.2","PrefixLength":24,"InterfaceAlias":"WireGuard Tunnel","AddressState":4,"SkipAsSource":false},
  {"IPAddress":"100.97.45.87","PrefixLength":32,"InterfaceAlias":"Tailscale","AddressState":4,"SkipAsSource":false}
]
"""
        self.assertEqual(
            extract_command_interfaces("windows", output),
            [("192.168.137.1", 24), ("192.168.1.23", 24), ("10.16.177.83", 18)],
        )
        candidates = extract_command_interface_candidates("windows", output)
        self.assertEqual(candidates[0].ip, "192.168.137.1")

    def test_extract_command_interfaces_linux_requires_global_ipv4_with_broadcast(self):
        output = """
[
  {
    "ifname": "eth0",
    "addr_info": [
      {"family":"inet","local":"192.168.1.23","prefixlen":24,"broadcast":"192.168.1.255","scope":"global"}
    ]
  },
  {
    "ifname": "wlan0",
    "addr_info": [
      {"family":"inet","local":"10.42.0.1","prefixlen":24,"broadcast":"10.42.0.255","scope":"global"}
    ]
  },
  {
    "ifname": "wg0",
    "addr_info": [
      {"family":"inet","local":"10.99.0.2","prefixlen":24,"broadcast":"10.99.0.255","scope":"global"}
    ]
  },
  {
    "ifname": "tailscale0",
    "addr_info": [
      {"family":"inet","local":"100.97.45.87","prefixlen":32,"scope":"global"}
    ]
  }
]
"""
        self.assertEqual(
            extract_command_interfaces("linux", output),
            [("192.168.1.23", 24), ("10.42.0.1", 24)],
        )

    def test_extract_command_interfaces_macos_parses_hex_netmask_and_skips_point_to_point(self):
        output = """
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet 192.168.2.1 netmask 0xffffff00 broadcast 192.168.2.255
en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet 10.0.0.5 netmask 0xffffff00 broadcast 10.0.0.255
lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
    inet 127.0.0.1 netmask 0xff000000
utun4: flags=8051<UP,POINTOPOINT,RUNNING,MULTICAST> mtu 1380
    inet 100.97.45.87 --> 100.97.45.87 netmask 0xffffffff
"""
        self.assertEqual(
            extract_command_interfaces("darwin", output),
            [("192.168.2.1", 24), ("10.0.0.5", 24)],
        )

    def test_extract_command_interfaces_macos_treats_en_interfaces_as_unknown(self):
        output = """
en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet 192.168.2.10 netmask 0xffffff00 broadcast 192.168.2.255
en1: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet 10.16.177.83 netmask 0xffffc000 broadcast 10.16.191.255
en5: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
    inet 172.20.10.2 netmask 0xfffffff0 broadcast 172.20.10.15
"""
        candidates = extract_command_interface_candidates("darwin", output)

        self.assertEqual(
            [(candidate.ip, candidate.interface_type) for candidate in candidates],
            [
                ("192.168.2.10", "unknown"),
                ("10.16.177.83", "unknown"),
                ("172.20.10.2", "unknown"),
            ],
        )

    def test_extract_command_interfaces_empty_output_returns_empty_list(self):
        self.assertEqual(extract_command_interfaces("linux", ""), [])

    def test_calculate_broadcast_addresses_skips_invalid_values(self):
        self.assertEqual(
            calculate_broadcast_addresses(
                [
                    ("192.168.1.100", 24),
                    ("192.168.137.1", 24),
                    ("10.42.0.1", 24),
                    ("10.0.0.5", 16),
                    ("invalid", 24),
                ]
            ),
            [
                ("192.168.1.100", "192.168.1.255"),
                ("192.168.137.1", "192.168.137.255"),
                ("10.42.0.1", "10.42.0.255"),
                ("10.0.0.5", "10.0.255.255"),
            ],
        )

    def test_psutil_network_candidates_filter_and_sort_runtime_interfaces(self):
        class FakeAddress:
            def __init__(self, family, address, netmask):
                self.family = family
                self.address = address
                self.netmask = netmask

        class FakePsutil:
            @staticmethod
            def net_if_addrs():
                return {
                    "Tailscale": [
                        FakeAddress(socket.AF_INET, "100.97.45.87", "255.255.255.255")
                    ],
                    "WLAN": [
                        FakeAddress(socket.AF_INET, "10.16.177.83", "255.255.192.0")
                    ],
                    "Local Area Connection* 10": [
                        FakeAddress(socket.AF_INET, "192.168.137.1", "255.255.255.0")
                    ],
                    "Bluetooth": [
                        FakeAddress(socket.AF_INET, "169.254.42.11", "255.255.0.0")
                    ],
                }

        original_psutil = voice_coding.psutil
        try:
            voice_coding.psutil = FakePsutil
            candidates = get_psutil_network_candidates("windows")
        finally:
            voice_coding.psutil = original_psutil

        self.assertEqual(
            [(candidate.ip, candidate.prefix_length, candidate.name) for candidate in candidates],
            [
                ("192.168.137.1", 24, "Local Area Connection* 10"),
                ("10.16.177.83", 18, "WLAN"),
            ],
        )

    def test_refresh_server_interfaces_replaces_stale_cached_ips(self):
        original_get_all_network_candidates = voice_coding.get_all_network_candidates
        original_server_interfaces = voice_coding.SERVER_INTERFACES
        original_initialized = voice_coding.SERVER_INTERFACES_INITIALIZED
        try:
            voice_coding.SERVER_INTERFACES = [("192.168.1.23", "192.168.1.255")]
            voice_coding.SERVER_INTERFACES_INITIALIZED = True
            voice_coding.get_all_network_candidates = lambda: [
                NetworkInterfaceCandidate(
                    ip="10.16.177.83",
                    prefix_length=18,
                    name="WLAN",
                    interface_type="wifi",
                )
            ]

            self.assertEqual(
                refresh_server_interfaces(log_changes=False),
                [("10.16.177.83", "10.16.191.255")],
            )
            self.assertEqual(get_primary_server_ip(), "10.16.177.83")
            self.assertEqual(get_advertised_server_ips(), ["10.16.177.83"])
        finally:
            voice_coding.get_all_network_candidates = original_get_all_network_candidates
            voice_coding.SERVER_INTERFACES = original_server_interfaces
            voice_coding.SERVER_INTERFACES_INITIALIZED = original_initialized

    def test_qr_advertised_ips_prefer_bound_hosts_without_hiding_fresh_candidates(self):
        original_get_all_network_candidates = voice_coding.get_all_network_candidates
        original_server_interfaces = voice_coding.SERVER_INTERFACES
        original_initialized = voice_coding.SERVER_INTERFACES_INITIALIZED
        original_bound_ips = get_bound_server_ips()
        try:
            voice_coding.SERVER_INTERFACES = [("192.168.1.23", "192.168.1.255")]
            voice_coding.SERVER_INTERFACES_INITIALIZED = True
            voice_coding.get_all_network_candidates = lambda: [
                NetworkInterfaceCandidate(
                    ip="10.16.177.83",
                    prefix_length=18,
                    name="WLAN",
                    interface_type="wifi",
                ),
            ]
            set_bound_server_ips(["192.168.1.23", "192.168.1.23"])

            self.assertEqual(get_qr_advertised_server_ips(refresh=True), ["192.168.1.23"])
            self.assertEqual(get_advertised_server_ips(refresh=True), ["10.16.177.83"])
        finally:
            voice_coding.get_all_network_candidates = original_get_all_network_candidates
            voice_coding.SERVER_INTERFACES = original_server_interfaces
            voice_coding.SERVER_INTERFACES_INITIALIZED = original_initialized
            set_bound_server_ips(original_bound_ips)

    def test_get_advertised_server_ips_can_force_refresh_current_pool(self):
        original_get_all_network_candidates = voice_coding.get_all_network_candidates
        original_server_interfaces = voice_coding.SERVER_INTERFACES
        original_initialized = voice_coding.SERVER_INTERFACES_INITIALIZED
        try:
            voice_coding.SERVER_INTERFACES = [("192.168.1.23", "192.168.1.255")]
            voice_coding.SERVER_INTERFACES_INITIALIZED = True
            voice_coding.get_all_network_candidates = lambda: [
                NetworkInterfaceCandidate(
                    ip="192.168.137.1",
                    prefix_length=24,
                    name="Local Area Connection* 10",
                    interface_type="wifi",
                ),
                NetworkInterfaceCandidate(
                    ip="10.16.177.83",
                    prefix_length=18,
                    name="WLAN",
                    interface_type="wifi",
                ),
            ]

            self.assertEqual(
                get_advertised_server_ips(refresh=True),
                ["192.168.137.1", "10.16.177.83"],
            )
            self.assertEqual(get_primary_server_ip(), "192.168.137.1")
        finally:
            voice_coding.get_all_network_candidates = original_get_all_network_candidates
            voice_coding.SERVER_INTERFACES = original_server_interfaces
            voice_coding.SERVER_INTERFACES_INITIALIZED = original_initialized


if __name__ == "__main__":
    unittest.main()
