import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'app_logger.dart';

/// 网络画像（2026-11-20 新增，跨网络快速配对核心能力之一）。
///
/// 目标：不读 SSID / 不申请定位权限，只用 IPv4 接口 + 前缀长度描述手机
/// 当前所处的网络环境。同一手机在两个网络（例如家里 WiFi 和公司 WiFi）
/// 各扫码成功一次后，地址簿里会分别记录两个 networkKey；以后回到任一网络
/// 都能靠 networkKey 命中把上次成功的地址排到最前，1~2 秒内并行连上。
///
/// 分三层：
/// 1. [Ipv4]：纯 IPv4 计算（解析、掩码、子网包含、私有/CGNAT 判定）；
/// 2. [NetworkSnapshot] / [NetworkInterfaceInfo]：一次网络环境快照；
/// 3. [NetworkSnapshotProvider]：原生 MethodChannel + EventChannel 实现
///    （`voicing/network` / `voicing/network_state_events`）和 dart:io 回退。
enum NetworkInterfaceKind {
  wifi,
  vpn,
  mobile,
  ethernet,
  unknown;

  /// 从原生返回的字符串解析；未知值一律降级为 unknown，不抛异常。
  static NetworkInterfaceKind parse(Object? raw) {
    if (raw is! String) {
      return NetworkInterfaceKind.unknown;
    }
    final normalized = raw.trim().toLowerCase();
    for (final kind in NetworkInterfaceKind.values) {
      if (kind.name == normalized) {
        return kind;
      }
    }
    return NetworkInterfaceKind.unknown;
  }

  /// dart:io 回退实现只能拿到接口名，用命名约定近似接口类型。
  static NetworkInterfaceKind fromInterfaceName(String interfaceName) {
    final name = interfaceName.toLowerCase();
    if (name.startsWith('wlan') ||
        name.startsWith('wifi') ||
        name.startsWith('ap')) {
      return NetworkInterfaceKind.wifi;
    }
    if (name.startsWith('tun') ||
        name.startsWith('ppp') ||
        name.startsWith('wg') ||
        name.contains('tailscale')) {
      return NetworkInterfaceKind.vpn;
    }
    if (name.startsWith('rmnet') ||
        name.startsWith('ccmni') ||
        name.startsWith('wwan') ||
        name.startsWith('radio')) {
      return NetworkInterfaceKind.mobile;
    }
    if (name.startsWith('eth')) {
      return NetworkInterfaceKind.ethernet;
    }
    return NetworkInterfaceKind.unknown;
  }
}

/// 纯 IPv4 计算工具；不依赖网络 IO，供地址簿与网络画像共用。
class Ipv4 {
  const Ipv4._();

  /// 把点分十进制 IPv4 解析为 32 位无符号整数；非法输入返回 null。
  static int? parse(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    final parts = value.trim().split('.');
    if (parts.length != 4) {
      return null;
    }
    var result = 0;
    for (final part in parts) {
      if (part.isEmpty || part.length > 3) {
        return null;
      }
      final octet = int.tryParse(part);
      if (octet == null || octet < 0 || octet > 255) {
        return null;
      }
      result = (result << 8) | octet;
    }
    return result;
  }

  static bool isValid(String? value) => parse(value) != null;

  /// CIDR 前缀长度校验。
  static bool isValidPrefix(int prefixLength) =>
      prefixLength >= 0 && prefixLength <= 32;

  /// 子网掩码；prefixLength == 0 时为 0（任意地址），32 时为全 1。
  static int maskForPrefix(int prefixLength) {
    if (prefixLength <= 0) {
      return 0;
    }
    if (prefixLength >= 32) {
      return 0xFFFFFFFF;
    }
    return (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF;
  }

  /// 计算网络号，例如 192.168.1.23/24 -> 192.168.1.0。
  static String? networkAddress(String? ip, int prefixLength) {
    final value = parse(ip);
    if (value == null || !isValidPrefix(prefixLength)) {
      return null;
    }
    return _format(value & maskForPrefix(prefixLength));
  }

  /// 网络 CIDR 字符串，例如 192.168.1.0/24。
  static String? networkCidr(String? ip, int prefixLength) {
    final network = networkAddress(ip, prefixLength);
    return network == null ? null : '$network/$prefixLength';
  }

  /// 判断 targetIp 是否落在 [ip]/[prefixLength] 这个子网内。
  static bool isInSubnet({
    required String? ip,
    required int prefixLength,
    required String? targetIp,
  }) {
    final local = parse(ip);
    final target = parse(targetIp);
    if (local == null || target == null || !isValidPrefix(prefixLength)) {
      return false;
    }
    final mask = maskForPrefix(prefixLength);
    return (local & mask) == (target & mask);
  }

  /// RFC1918 私有地址：10/8、172.16/12、192.168/16。
  ///
  /// 注意 Tailscale 的 100.64/10 属于 CGNAT 共享地址段，不算私有 LAN，
  /// 单独由 [isTailscaleCgnat] 判定，避免「本地有 Tailscale 时把隧道地址
  /// 误当成不可达 LAN 地址」。
  static bool isPrivateLan(String? ip) {
    final value = parse(ip);
    if (value == null) {
      return false;
    }
    final first = (value >> 24) & 0xFF;
    final second = (value >> 16) & 0xFF;
    if (first == 10) {
      return true;
    }
    if (first == 172 && second >= 16 && second <= 31) {
      return true;
    }
    return first == 192 && second == 168;
  }

  /// Tailscale CGNAT 段：100.64.0.0/10（RFC 6598）。
  static bool isTailscaleCgnat(String? ip) {
    final value = parse(ip);
    if (value == null) {
      return false;
    }
    // 0x64400000 即 100.64.0.0；掩码 0xFFC00000 对应 /10。
    return (value & _cgnatMask) == _cgnatBase;
  }

  static const int _cgnatMask = 0xFFC00000;
  static const int _cgnatBase = 0x64400000;

  static String _format(int value) {
    return '${(value >> 24) & 0xFF}.${(value >> 16) & 0xFF}.'
        '${(value >> 8) & 0xFF}.${value & 0xFF}';
  }
}

/// 单个本地 IPv4 接口描述；[kind] 由原生 ConnectivityManager / 接口名推断。
class NetworkInterfaceInfo {
  const NetworkInterfaceInfo({
    required this.name,
    required this.ip,
    required this.prefixLength,
    required this.kind,
  });

  final String name;
  final String ip;
  final int prefixLength;
  final NetworkInterfaceKind kind;

  bool get isVpn => kind == NetworkInterfaceKind.vpn;

  /// 该接口所在子网的 CIDR，例如 192.168.1.0/24。
  String get networkCidr => Ipv4.networkCidr(ip, prefixLength) ?? '$ip/32';

  bool contains(String targetIp) => Ipv4.isInSubnet(
        ip: ip,
        prefixLength: prefixLength,
        targetIp: targetIp,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'ip': ip,
        'prefixLength': prefixLength,
        'kind': kind.name,
      };

  /// 解析原生 / JSON 接口；非法条目返回 null 由调用方跳过。
  static NetworkInterfaceInfo? fromJson(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final name = raw['name'];
    final ip = raw['ip'];
    if (name is! String || ip is! String || !Ipv4.isValid(ip)) {
      return null;
    }
    final rawPrefix = raw['prefixLength'] ?? raw['prefix_length'];
    final prefixLength = rawPrefix is int
        ? rawPrefix
        : (rawPrefix is num ? rawPrefix.toInt() : 24);
    if (!Ipv4.isValidPrefix(prefixLength)) {
      return null;
    }
    return NetworkInterfaceInfo(
      name: name,
      ip: ip,
      prefixLength: prefixLength,
      kind: NetworkInterfaceKind.parse(raw['kind']),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is NetworkInterfaceInfo &&
        other.name == name &&
        other.ip == ip &&
        other.prefixLength == prefixLength &&
        other.kind == kind;
  }

  @override
  int get hashCode => Object.hash(name, ip, prefixLength, kind);

  @override
  String toString() => '$name:$ip/$prefixLength(${kind.name})';
}

/// 一次本地网络环境快照。
///
/// [networkKey] 是跨网络配对的核心标识：取「代表性非 VPN 私网接口」的
/// `kind:network/prefix`，例如 `wifi:192.168.1.0/24`；多接口时按
/// 「私有 > 非私有、wifi > ethernet > mobile > vpn > unknown、接口名」
/// 确定性选择，保证同一环境下每次算出的 key 一致。
class NetworkSnapshot {
  const NetworkSnapshot({
    this.interfaces = const <NetworkInterfaceInfo>[],
    this.approximate = false,
  });

  /// 空快照：没有任何可用 IPv4 接口（例如飞行模式），也用于未知环境。
  static const NetworkSnapshot empty = NetworkSnapshot();

  final List<NetworkInterfaceInfo> interfaces;

  /// true 表示接口前缀长度是近似值（dart:io 回退拿不到真实 prefixLength，
  /// 按 /24 近似），用于日志与调试，不参与评分。
  final bool approximate;

  bool get isEmpty => interfaces.isEmpty;

  /// 网络画像已知：至少有一个非 VPN 接口或 VPN 接口。
  bool get isKnown => interfaces.isNotEmpty;

  List<NetworkInterfaceInfo> get nonVpnInterfaces =>
      interfaces.where((item) => !item.isVpn).toList(growable: false);

  /// 是否存在 Tailscale 隧道接口（100.64.0.0/10）。
  bool get hasTailscale =>
      interfaces.any((item) => Ipv4.isTailscaleCgnat(item.ip));

  /// 是否至少有一个非 VPN 的私有 LAN 接口（说明手机当前有可用的局域网）。
  bool get hasPrivateLan => interfaces
      .any((item) => !item.isVpn && Ipv4.isPrivateLan(item.ip));

  /// 代表性接口：优先非 VPN 私网接口，其次任意非 VPN 接口，最后 VPN 接口。
  NetworkInterfaceInfo? get primaryInterface {
    if (interfaces.isEmpty) {
      return null;
    }
    final nonVpn = nonVpnInterfaces;
    final pool = nonVpn.isNotEmpty ? nonVpn : interfaces;
    final sorted = List<NetworkInterfaceInfo>.of(pool)..sort(_comparePrimary);
    return sorted.first;
  }

  /// 当前网络环境 Key，例如 `wifi:192.168.1.0/24`；无接口时为 ''。
  String get networkKey {
    final primary = primaryInterface;
    if (primary == null) {
      return '';
    }
    return '${primary.kind.name}:${primary.networkCidr}';
  }

  /// 代表性接口类型（记录成功历史时用），例如 wifi / vpn / mobile。
  String get primaryKind => primaryInterface?.kind.name ?? 'unknown';

  /// 网络环境签名：用于控制器判断快照是否真的变化，避免重复重启竞速。
  String get signature {
    if (interfaces.isEmpty) {
      return '';
    }
    final parts = interfaces
        .map((item) => '${item.name}:${item.networkCidr}')
        .toList(growable: false)
      ..sort();
    return '$networkKey|${parts.join(',')}';
  }

  /// 目标 IP 是否与任一本地接口同子网（"是否可达同网段"判断）。
  bool containsInLocalSubnet(String? targetIp) {
    if (targetIp == null || targetIp.isEmpty) {
      return false;
    }
    return interfaces.any((item) => item.contains(targetIp));
  }

  /// 返回包含目标 IP 的第一批接口中的确定性选择（按接口名排序）。
  NetworkInterfaceInfo? interfaceContaining(String? targetIp) {
    if (targetIp == null || targetIp.isEmpty) {
      return null;
    }
    final matches = interfaces
        .where((item) => item.contains(targetIp))
        .toList(growable: false)
      ..sort((a, b) {
        final byName = a.name.compareTo(b.name);
        return byName != 0 ? byName : a.ip.compareTo(b.ip);
      });
    return matches.isEmpty ? null : matches.first;
  }

  /// 给候选 IP 标注它所属的网络上下文：
  /// - 与本地接口同子网：使用当前 networkKey（地址就在这个网络里可达）；
  /// - 否则置空（未知网络），由后续 recordSuccess 写入真实成功环境。
  SavedAddressNetworkContext networkContextFor(String ip) {
    final iface = interfaceContaining(ip);
    if (iface == null) {
      return const SavedAddressNetworkContext(networkKey: '', networkKind: 'unknown');
    }
    return SavedAddressNetworkContext(
      networkKey: networkKey,
      networkKind: iface.kind.name,
    );
  }

  Map<String, dynamic> toJson() => {
        'approximate': approximate,
        'interfaces': interfaces.map((item) => item.toJson()).toList(),
      };

  /// 解析原生 MethodChannel / EventChannel 返回的快照；结构不对返回 null。
  static NetworkSnapshot? fromNativeMap(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final rawInterfaces = raw['interfaces'];
    if (rawInterfaces is! List) {
      return null;
    }
    final parsed = <NetworkInterfaceInfo>[];
    final seen = <String>{};
    for (final entry in rawInterfaces) {
      final info = NetworkInterfaceInfo.fromJson(entry);
      if (info == null) {
        continue;
      }
      if (seen.add('${info.name}/${info.ip}')) {
        parsed.add(info);
      }
    }
    return NetworkSnapshot(
      interfaces: parsed,
      approximate: raw['approximate'] == true,
    );
  }

  static int _comparePrimary(NetworkInterfaceInfo a, NetworkInterfaceInfo b) {
    final aPrivate = Ipv4.isPrivateLan(a.ip) ? 0 : 1;
    final bPrivate = Ipv4.isPrivateLan(b.ip) ? 0 : 1;
    if (aPrivate != bPrivate) {
      return aPrivate - bPrivate;
    }
    final byKind = _kindRank(a.kind) - _kindRank(b.kind);
    if (byKind != 0) {
      return byKind;
    }
    final byName = a.name.compareTo(b.name);
    return byName != 0 ? byName : a.ip.compareTo(b.ip);
  }

  static int _kindRank(NetworkInterfaceKind kind) {
    switch (kind) {
      case NetworkInterfaceKind.wifi:
        return 0;
      case NetworkInterfaceKind.ethernet:
        return 1;
      case NetworkInterfaceKind.mobile:
        return 2;
      case NetworkInterfaceKind.vpn:
        return 3;
      case NetworkInterfaceKind.unknown:
        return 4;
    }
  }

  @override
  bool operator ==(Object other) {
    if (other is! NetworkSnapshot ||
        other.approximate != approximate ||
        other.interfaces.length != interfaces.length) {
      return false;
    }
    for (var i = 0; i < interfaces.length; i++) {
      if (other.interfaces[i] != interfaces[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(approximate, Object.hashAll(interfaces));

  @override
  String toString() =>
      'NetworkSnapshot(networkKey=$networkKey, interfaces=$interfaces, approximate=$approximate)';
}

/// 候选 IP 的网络上下文标注结果（值对象，避免在地址簿里直接依赖快照）。
class SavedAddressNetworkContext {
  const SavedAddressNetworkContext({
    required this.networkKey,
    required this.networkKind,
  });

  final String networkKey;
  final String networkKind;
}

/// 网络快照 provider 抽象（2026-11-20 新增）。
///
/// 生产默认用 [NativeNetworkSnapshotProvider]：MethodChannel
/// `voicing/network` 的 `getNetworkSnapshot` 取快照，EventChannel
/// `voicing/network_state_events` 订阅变化；原生不可用（旧 APK / 非 Android
/// 环境 / 插件缺失）时静默退化到 [DartIoNetworkSnapshotProvider]。
/// 单元测试注入 fake 即可完全脱离真实网络。
abstract class NetworkSnapshotProvider {
  /// 生产环境默认实现：原生优先，dart:io 兜底。
  static NetworkSnapshotProvider platform({
    Duration debounce = const Duration(milliseconds: 400),
    Duration snapshotTimeout = const Duration(milliseconds: 800),
  }) {
    return NativeNetworkSnapshotProvider(
      fallback: const DartIoNetworkSnapshotProvider(),
      debounce: debounce,
      snapshotTimeout: snapshotTimeout,
    );
  }

  Future<NetworkSnapshot> snapshot();

  /// 网络变化订阅（已防抖）。永不抛错：原生不支持时返回空流。
  Stream<NetworkSnapshot> get changes;

  Future<void> dispose();
}

/// 原生网络快照实现（MethodChannel + EventChannel）。
///
/// 错误处理原则：网络画像只是「加速器」，任何原生异常都不能让配对/连接崩溃，
/// 必须静默退化为空快照或 dart:io 回退，并按 warning 记录一次原因。
class NativeNetworkSnapshotProvider implements NetworkSnapshotProvider {
  NativeNetworkSnapshotProvider({
    NetworkSnapshotProvider? fallback,
    this.debounce = const Duration(milliseconds: 400),
    this.snapshotTimeout = const Duration(milliseconds: 800),
  }) : _fallback = fallback;

  static const MethodChannel _methodChannel = MethodChannel('voicing/network');
  static const EventChannel _eventChannel =
      EventChannel('voicing/network_state_events');

  final NetworkSnapshotProvider? _fallback;
  final Duration debounce;
  final Duration snapshotTimeout;

  StreamController<NetworkSnapshot>? _changesController;
  StreamSubscription<dynamic>? _eventSubscription;
  Timer? _debounceTimer;
  NetworkSnapshot? _pendingSnapshot;
  bool _nativeUnavailable = false;

  @override
  Future<NetworkSnapshot> snapshot() async {
    if (!_nativeUnavailable) {
      try {
        final raw = await _methodChannel
            .invokeMethod<dynamic>('getNetworkSnapshot')
            .timeout(snapshotTimeout);
        final parsed = NetworkSnapshot.fromNativeMap(raw);
        if (parsed == null) {
          AppLogger.warning('原生网络快照结构非法，退化为 dart:io 近似快照');
        } else {
          return parsed;
        }
      } on MissingPluginException {
        _nativeUnavailable = true;
        AppLogger.warning('原生网络快照方法不存在（旧版本 native），退化为 dart:io');
      } on TimeoutException {
        AppLogger.warning('原生网络快照超时，退化为 dart:io 近似快照');
      } on PlatformException catch (error, stackTrace) {
        AppLogger.warning(
          '原生网络快照调用失败，退化为 dart:io 近似快照',
          error: error,
          stackTrace: stackTrace,
        );
      } catch (error, stackTrace) {
        AppLogger.warning(
          '原生网络快照异常，退化为 dart:io 近似快照',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    return await _fallbackSnapshot();
  }

  @override
  Stream<NetworkSnapshot> get changes {
    final existing = _changesController;
    if (existing != null) {
      return existing.stream;
    }
    final controller = StreamController<NetworkSnapshot>.broadcast();
    _changesController = controller;
    _subscribeNativeEvents(controller);
    return controller.stream;
  }

  void _subscribeNativeEvents(StreamController<NetworkSnapshot> controller) {
    if (_nativeUnavailable) {
      return;
    }
    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
        (event) {
          final snapshot = NetworkSnapshot.fromNativeMap(event);
          if (snapshot == null) {
            return;
          }
          // 400ms 防抖：网络在切换瞬间会连续触发 onAvailable/onLost/
          // onCapabilitiesChanged，等稳定后再通知控制器，避免反复重启竞速。
          _pendingSnapshot = snapshot;
          _debounceTimer?.cancel();
          _debounceTimer = Timer(debounce, () {
            final pending = _pendingSnapshot;
            _pendingSnapshot = null;
            if (pending != null && !controller.isClosed) {
              controller.add(pending);
            }
          });
        },
        onError: (Object error, StackTrace stackTrace) {
          AppLogger.warning(
            '网络状态事件订阅失败，网络自适应降级（不影响连接）',
            error: error,
            stackTrace: stackTrace,
          );
          _nativeUnavailable = true;
        },
        onDone: () {},
      );
    } on MissingPluginException {
      _nativeUnavailable = true;
      AppLogger.warning('网络状态事件通道不存在（旧版本 native），自适应降级');
    } catch (error, stackTrace) {
      AppLogger.warning(
        '网络状态事件订阅异常，网络自适应降级',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<NetworkSnapshot> _fallbackSnapshot() async {
    final fallback = _fallback;
    if (fallback == null) {
      return NetworkSnapshot.empty;
    }
    try {
      return await fallback.snapshot();
    } catch (error, stackTrace) {
      AppLogger.warning(
        'dart:io 网络快照回退失败',
        error: error,
        stackTrace: stackTrace,
      );
      return NetworkSnapshot.empty;
    }
  }

  @override
  Future<void> dispose() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final subscription = _eventSubscription;
    _eventSubscription = null;
    if (subscription != null) {
      await subscription.cancel();
    }
    final controller = _changesController;
    _changesController = null;
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    await _fallback?.dispose();
  }
}

/// dart:io 回退实现：`NetworkInterface.list` 拿不到前缀长度，
/// 统一按 /24 近似并在快照里标记 approximate=true。
///
/// 这个实现只在原生不可用时使用，用于「至少知道当前有哪些子网」的粗排序；
/// 真正的跨网络判定仍依赖原生快照的真实 prefixLength。
class DartIoNetworkSnapshotProvider implements NetworkSnapshotProvider {
  const DartIoNetworkSnapshotProvider({this.approximatePrefixLength = 24});

  final int approximatePrefixLength;

  @override
  Future<NetworkSnapshot> snapshot() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
        includeLinkLocal: false,
      );
      final infos = <NetworkInterfaceInfo>[];
      for (final interface in interfaces) {
        final kind = NetworkInterfaceKind.fromInterfaceName(interface.name);
        for (final address in interface.addresses) {
          if (address.type != InternetAddressType.IPv4 ||
              address.isLoopback ||
              !Ipv4.isValid(address.address)) {
            continue;
          }
          infos.add(
            NetworkInterfaceInfo(
              name: interface.name,
              ip: address.address,
              prefixLength: approximatePrefixLength,
              kind: kind,
            ),
          );
        }
      }
      return NetworkSnapshot(interfaces: infos, approximate: true);
    } catch (error, stackTrace) {
      AppLogger.warning(
        'dart:io 网络接口枚举失败',
        error: error,
        stackTrace: stackTrace,
      );
      return NetworkSnapshot.empty;
    }
  }

  @override
  Stream<NetworkSnapshot> get changes => const Stream<NetworkSnapshot>.empty();

  @override
  Future<void> dispose() async {}
}
