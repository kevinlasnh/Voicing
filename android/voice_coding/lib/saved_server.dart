import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'server_address_book.dart';

/// 已配对服务器（2026-11-20 起 schemaVersion = 2）。
///
/// v2 在 v1 的 `device_id/ip/ips/port/name/os/last_connected_ts` 之上增加
/// `addresses` 地址簿：每个候选 IP 记录「在哪个网络环境成功过、成功/失败
/// 次数、最近成功时间」。schema v1 的历史数据在 [SavedServer.fromJson] 里
/// 自动迁移成地址簿（主地址视为最近一次成功），旧字段继续输出，保证降级/
/// 回滚到 v1 代码时仍能读到 ip/ips。
class SavedServer {
  static const int currentSchemaVersion = 2;

  const SavedServer({
    this.schemaVersion = currentSchemaVersion,
    required this.deviceId,
    required this.ip,
    this.ips = const [],
    required this.port,
    required this.name,
    required this.os,
    required this.lastConnectedTs,
    this.addresses = ServerAddressBook.empty,
  });

  final int schemaVersion;
  final String deviceId;
  final String ip;
  final List<String> ips;
  final int port;
  final String name;
  final String os;
  final int lastConnectedTs;

  /// 显式地址簿（v2）。为空时 [addressBook] 会从 ip/ips 推导兼容地址簿，
  /// 保证旧的构造点（测试、手动输入、二维码）无需改动也带网络上下文结构。
  final ServerAddressBook addresses;

  bool get hasDeviceId => deviceId.isNotEmpty;

  String get displayName => name.isNotEmpty ? name : ip;

  /// 地址簿（保证包含主地址与所有候选；无显式地址簿时按 v1 语义推导）。
  ServerAddressBook get addressBook {
    if (addresses.isNotEmpty) {
      return addresses;
    }
    return ServerAddressBook.fromLegacyCandidates(
      primaryIp: ip,
      candidateIps: candidateIps,
      lastConnectedTs: lastConnectedTs,
    );
  }

  /// 候选 IP：主地址优先，合并 ips 与地址簿里的历史地址并去重。
  List<String> get candidateIps => normalizeIpCandidates(
        ip,
        <dynamic>[...ips, ...addresses.ips],
      );

  factory SavedServer.fromJson(Map<String, dynamic> json) {
    final ip = _readString(json['ip']);
    final port = _readInt(json['port']);
    if (ip.isEmpty || port == null) {
      throw const FormatException('saved_server is missing ip or port');
    }

    final lastConnectedTs = _readInt(json['last_connected_ts']) ?? 0;
    final legacyIps = _readStringList(json['ips']);
    final parsedAddresses = ServerAddressBook.fromJson(json['addresses']);
    // v1 -> v2 迁移：旧数据没有 addresses，把 ip/ips 转成地址簿候选。
    // v2 数据已经带地址簿时只补「缺失的 ip/ips 条目」，绝不用 last_connected_ts
    // 覆盖已有记录的时间/计数语义，否则 fromJson(toJson(x)) 不再等于 x，
    // 会把「某网络最近成功」的时间错误刷新成当前连接时间。
    final legacyCandidates = normalizeIpCandidates(ip, legacyIps);
    final addressBook = parsedAddresses.isNotEmpty
        ? _includeMissingLegacyCandidates(
            parsedAddresses,
            legacyCandidates,
            lastConnectedTs,
          )
        : ServerAddressBook.fromLegacyCandidates(
            primaryIp: ip,
            candidateIps: legacyCandidates,
            lastConnectedTs: lastConnectedTs,
          );

    return SavedServer(
      // 内存/输出统一为当前 schema；v1 迁移发生在 fromJson 读入阶段。
      schemaVersion: currentSchemaVersion,
      deviceId: _readString(json['device_id']),
      ip: ip,
      ips: legacyIps,
      port: port,
      name: _readString(json['name']),
      os: _readString(json['os']),
      lastConnectedTs: lastConnectedTs,
      addresses: addressBook,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'schema_version': currentSchemaVersion,
      'device_id': deviceId,
      'ip': ip,
      // 兼容字段：旧版本（v1）只认 ip/ips，保持原样输出。
      'ips': candidateIps,
      'port': port,
      'name': name,
      'os': os,
      'last_connected_ts': lastConnectedTs,
      'addresses': addressBook.toJson(),
    };
  }

  SavedServer copyWith({
    int? schemaVersion,
    String? deviceId,
    String? ip,
    List<String>? ips,
    int? port,
    String? name,
    String? os,
    int? lastConnectedTs,
    ServerAddressBook? addresses,
  }) {
    return SavedServer(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      deviceId: deviceId ?? this.deviceId,
      ip: ip ?? this.ip,
      ips: ips ?? this.ips,
      port: port ?? this.port,
      name: name ?? this.name,
      os: os ?? this.os,
      lastConnectedTs: lastConnectedTs ?? this.lastConnectedTs,
      addresses: addresses ?? this.addresses,
    );
  }

  SavedServer mergeCandidateIpsFrom(SavedServer previous) {
    if (!_canMergeCandidateIps(previous, this)) {
      return this;
    }

    return copyWith(
      ips: normalizeIpCandidates(
        ip,
        <dynamic>[
          ...candidateIps,
          ...previous.candidateIps,
        ],
      ),
    );
  }

  /// v2 合并：候选 IP + 地址簿历史一起合并，保留不同网络的全部成功记录。
  ///
  /// 只在同一设备（或旧数据没有 device_id）时合并；不同设备必须经用户确认
  /// 后直接替换，不能把旧设备的历史地址混进来。
  SavedServer mergeAddressHistoryFrom(SavedServer previous) {
    if (!_canMergeCandidateIps(previous, this)) {
      return this;
    }
    final mergedBook = addressBook.merge(previous.addressBook.addresses);
    return copyWith(
      ips: normalizeIpCandidates(
        ip,
        <dynamic>[
          ...candidateIps,
          ...previous.candidateIps,
        ],
      ),
      addresses: mergedBook,
    );
  }

  /// 提升主地址（本次成功候选），所有候选与地址簿保持不变。
  SavedServer promotePrimary(String primaryIp) {
    final normalized = primaryIp.trim();
    if (normalized.isEmpty || normalized == ip) {
      return this;
    }
    return copyWith(
      ip: normalized,
      ips: normalizeIpCandidates(normalized, candidateIps),
    );
  }

  static String readString(dynamic value) => _readString(value);

  static int? readInt(dynamic value) => _readInt(value);

  static List<String> normalizeIpCandidates(
    String primaryIp,
    Iterable<dynamic> values,
  ) {
    final candidates = <String>[];

    void add(dynamic value) {
      final ip = _readString(value);
      if (ip.isNotEmpty && !candidates.contains(ip)) {
        candidates.add(ip);
      }
    }

    add(primaryIp);
    for (final value in values) {
      add(value);
    }
    return candidates;
  }

  static String _readString(dynamic value) {
    return value is String ? value.trim() : '';
  }

  static List<String> _readStringList(dynamic value) {
    if (value is! List) {
      return const [];
    }
    return normalizeIpCandidates('', value);
  }

  static int? _readInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  @override
  bool operator ==(Object other) {
    return other is SavedServer &&
        other.deviceId == deviceId &&
        other.ip == ip &&
        _listEquals(other.candidateIps, candidateIps) &&
        other.port == port &&
        other.name == name &&
        other.os == os &&
        other.lastConnectedTs == lastConnectedTs &&
        other.addressBook == addressBook;
  }

  @override
  int get hashCode => Object.hash(
        deviceId,
        ip,
        Object.hashAll(candidateIps),
        port,
        name,
        os,
        lastConnectedTs,
        addressBook,
      );
}

/// v2 地址簿与旧 ip/ips 字段的兼容：只为地址簿里缺失的候选追加「见过」记录，
/// 不覆盖已有条目的成功时间/计数/网络 Key。
///
/// 这样 `SavedServer.fromJson(toJson(x)) == x` 恒成立，且手工改坏缺主地址的
/// 旧数据仍能恢复出完整候选池。
ServerAddressBook _includeMissingLegacyCandidates(
  ServerAddressBook book,
  List<String> candidateIps,
  int lastConnectedTs,
) {
  final missing = <SavedAddress>[];
  for (final candidateIp in candidateIps) {
    if (candidateIp.isEmpty || book.addressFor(candidateIp) != null) {
      continue;
    }
    missing.add(SavedAddress(ip: candidateIp, lastSeenTs: lastConnectedTs));
  }
  if (missing.isEmpty) {
    return book;
  }
  return book.merge(missing);
}

bool _canMergeCandidateIps(SavedServer previous, SavedServer incoming) {
  if (previous.hasDeviceId && incoming.hasDeviceId) {
    return previous.deviceId == incoming.deviceId;
  }

  // Legacy saved_server records may not have device_id yet. Preserve their
  // address history when a QR scan upgrades the same saved PC to a modern ID.
  return true;
}

bool _listEquals(List<String> a, List<String> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

class SavedServerStore {
  static const String savedServerKey = 'saved_server';
  static const String legacyManualServerIpKey = 'manual_server_ip';
  static const String legacyManualServerPortKey = 'manual_server_port';

  const SavedServerStore();

  Future<SavedServer?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final rawSavedServer = prefs.getString(savedServerKey);
    if (rawSavedServer != null && rawSavedServer.isNotEmpty) {
      try {
        final decoded = json.decode(rawSavedServer);
        if (decoded is Map) {
          final map = Map<String, dynamic>.from(decoded);
          final server = SavedServer.fromJson(map);
          // v1 -> v2：读入时已迁移成地址簿，顺手回写一次，避免每次启动重复迁移。
          if (SavedServer.readInt(map['schema_version']) !=
              SavedServer.currentSchemaVersion) {
            await save(server);
          }
          return server;
        }
      } catch (_) {
        await prefs.remove(savedServerKey);
      }
    }

    return _migrateLegacyManualServer(prefs);
  }

  Future<void> save(SavedServer server) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(savedServerKey, json.encode(server.toJson()));
    await prefs.remove(legacyManualServerIpKey);
    await prefs.remove(legacyManualServerPortKey);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(savedServerKey);
    await prefs.remove(legacyManualServerIpKey);
    await prefs.remove(legacyManualServerPortKey);
  }

  Future<SavedServer?> _migrateLegacyManualServer(
    SharedPreferences prefs,
  ) async {
    final ip = prefs.getString(legacyManualServerIpKey)?.trim();
    final rawPort = prefs.get(legacyManualServerPortKey);
    final port = SavedServer.readInt(rawPort);
    if (ip == null || ip.isEmpty || port == null) {
      return null;
    }

    final migrated = SavedServer(
      deviceId: '',
      ip: ip,
      port: port,
      name: '',
      os: '',
      lastConnectedTs: DateTime.now().millisecondsSinceEpoch,
    );
    await save(migrated);
    return migrated;
  }
}
