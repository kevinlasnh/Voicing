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

  /// 多设备列表内的稳定 Key（2026-11-22 新增）。
  ///
  /// 有 PC 的持久 `device_id` 时直接用它；早期手动 IP / 旧数据没有 device_id，
  /// 退化为 `legacy:ip:port`，保证同一台设备重复添加时能被识别而不是并列两份。
  String get deviceKey =>
      deviceId.isNotEmpty ? deviceId : 'legacy:$ip:$port';

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
  /// 只在同一设备（或旧数据没有 device_id）时合并；2026-11-22 多设备后，
  /// 不同设备是并列保存在设备列表里，不再存在「替换」语义，也绝不能把
  /// 不同设备的地址历史混进同一条记录。
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

/// 多设备快照（2026-11-22 新增，schema v3）。
///
/// [servers] 是这台手机配对过的全部 PC（按配对先后顺序，稳定不重排），
/// [activeDeviceKey] 是用户当前在「设备选择」里选中的发送目标。
class PairedDevicesSnapshot {
  const PairedDevicesSnapshot({
    this.servers = const <SavedServer>[],
    this.activeDeviceKey = '',
  });

  static const PairedDevicesSnapshot empty = PairedDevicesSnapshot();

  final List<SavedServer> servers;
  final String activeDeviceKey;
}

/// 已配对 PC 的本地存储。
///
/// 2026-11-22 由「单设备覆盖」升级为「多设备列表」（schema v3）：
/// - 新格式写在 `saved_servers`（JSON：schema_version + servers 数组），
///   活跃设备 Key 单独写 `active_device_key`；
/// - 旧格式 `saved_server`（v1/v2 单设备）读入时自动迁移成列表，
///   同时继续回写一份单设备 `saved_server`（= 活跃设备），保证降级/回滚
///   到旧版本仍能读到一台可用设备；
/// - 所有写入都在 SharedPreferences 上串行执行（见 controller 的持久化队列），
///   这里保持纯数据层，不做网络 IO、不做业务合并。
class SavedServerStore {
  static const String savedServerKey = 'saved_server';
  static const String savedServersKey = 'saved_servers';
  static const String activeDeviceKey = 'active_device_key';
  static const String legacyManualServerIpKey = 'manual_server_ip';
  static const String legacyManualServerPortKey = 'manual_server_port';

  /// 列表存储格式版本；单台设备内部仍是 [SavedServer.currentSchemaVersion]。
  static const int savedServersSchemaVersion = 3;

  const SavedServerStore();

  /// 兼容旧单设备 API：返回活跃设备（无活跃记录时取第一台）。
  Future<SavedServer?> load() async {
    final snapshot = await loadSnapshot();
    if (snapshot.servers.isEmpty) {
      return null;
    }
    for (final server in snapshot.servers) {
      if (server.deviceKey == snapshot.activeDeviceKey) {
        return server;
      }
    }
    return snapshot.servers.first;
  }

  /// 读取全部已配对设备 + 活跃设备 Key，并完成 v1/v2 单设备数据迁移。
  Future<PairedDevicesSnapshot> loadSnapshot() async {
    final prefs = await SharedPreferences.getInstance();

    final rawList = prefs.getString(savedServersKey);
    if (rawList != null && rawList.isNotEmpty) {
      final servers = _decodeServerList(rawList);
      // 空列表 / 所有条目都损坏时不能当成「用户删空设备」返回：正常清空会
      // 删除 saved_servers Key，不会留下空数组。这里回退到旧单设备镜像迁移，
      // 避免明明还有一份可用 saved_server 却显示没有设备。
      if (servers != null && servers.isNotEmpty) {
        final storedActiveKey = (prefs.getString(activeDeviceKey) ?? '').trim();
        var activeKey = _resolveActiveKey(servers, storedActiveKey);

        // 降级到旧版 APK 时，旧版只会写单设备 saved_server（可能新配对/切换过）。
        // 升级回来必须与 v3 列表对账：同一 deviceKey 合并地址历史，新 deviceKey
        // 追加进列表；若镜像记录明显更新，则把它设为活跃设备。否则降级期间
        // 的变化会被静默丢弃。
        final rawLegacy = prefs.getString(savedServerKey);
        final legacy = _parseStoredServer(rawLegacy);
        if (legacy == null && rawLegacy != null && rawLegacy.isNotEmpty) {
          // 降级镜像损坏：删掉，避免每次启动重复解析失败（v3 列表仍是权威）。
          await prefs.remove(savedServerKey);
        }
        if (legacy != null) {
          final merged = List<SavedServer>.of(servers);
          final index = merged.indexWhere(
            (server) => server.deviceKey == legacy.deviceKey,
          );
          var changed = false;
          if (index >= 0) {
            // 同一台设备：谁更新就以谁的身份字段为主（降级期间可能改过名/换了
            // 主地址、刷新过 lastConnectedTs），再把另一份的地址历史并进来。
            final current = merged[index];
            final base = legacy.lastConnectedTs > current.lastConnectedTs
                ? legacy
                : current;
            final other = identical(base, legacy) ? current : legacy;
            final reconciled = base.mergeAddressHistoryFrom(other);
            if (reconciled != current) {
              merged[index] = reconciled;
              changed = true;
            }
          } else {
            merged.add(legacy);
            changed = true;
          }
          final currentActive = merged.firstWhere(
            (server) => server.deviceKey == activeKey,
            orElse: () => merged.first,
          );
          if (legacy.lastConnectedTs > currentActive.lastConnectedTs) {
            activeKey = legacy.deviceKey;
            changed = true;
          }
          if (changed) {
            await saveAll(merged, activeDeviceKey: activeKey);
          }
          return PairedDevicesSnapshot(
            servers: List<SavedServer>.unmodifiable(merged),
            activeDeviceKey: activeKey,
          );
        }
        return PairedDevicesSnapshot(
          servers: List<SavedServer>.unmodifiable(servers),
          activeDeviceKey: activeKey,
        );
      }
      // v3 列表损坏：丢弃，避免每次启动都解析失败；后续走旧格式迁移。
      await prefs.remove(savedServersKey);
    }

    final servers = <SavedServer>[];
    final rawSavedServer = prefs.getString(savedServerKey);
    final parsedSavedServer = _parseStoredServer(rawSavedServer);
    if (parsedSavedServer != null) {
      servers.add(parsedSavedServer);
    } else if (rawSavedServer != null && rawSavedServer.isNotEmpty) {
      // 旧单设备数据损坏：删除后继续尝试手动 IP 迁移。
      await prefs.remove(savedServerKey);
    }

    if (servers.isEmpty) {
      final migrated = await _migrateLegacyManualServer(prefs);
      if (migrated != null) {
        servers.add(migrated);
      }
    }

    if (servers.isEmpty) {
      return PairedDevicesSnapshot.empty;
    }

    // 迁移结果立刻回写成 v3 列表 + 单设备兼容字段，避免每次启动重复迁移。
    await saveAll(servers, activeDeviceKey: servers.first.deviceKey);
    return PairedDevicesSnapshot(
      servers: List<SavedServer>.unmodifiable(servers),
      activeDeviceKey: servers.first.deviceKey,
    );
  }

  /// 兼容旧单设备 API：按 deviceKey 覆盖或追加一台设备，并把它设为活跃设备。
  Future<void> save(SavedServer server) async {
    final snapshot = await loadSnapshot();
    final servers = List<SavedServer>.of(snapshot.servers);
    final index = servers.indexWhere(
      (existing) => existing.deviceKey == server.deviceKey,
    );
    if (index >= 0) {
      servers[index] = server;
    } else {
      servers.add(server);
    }
    await saveAll(servers, activeDeviceKey: server.deviceKey);
  }

  /// 全量写回设备列表与活跃设备 Key（顺序即 UI 展示顺序）。
  Future<void> saveAll(
    List<SavedServer> servers, {
    String? activeDeviceKey,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(legacyManualServerIpKey);
    await prefs.remove(legacyManualServerPortKey);

    if (servers.isEmpty) {
      await prefs.remove(savedServersKey);
      await prefs.remove(savedServerKey);
      await prefs.remove(SavedServerStore.activeDeviceKey);
      return;
    }

    final activeKey = _resolveActiveKey(servers, activeDeviceKey ?? '');
    final activeServer = servers.firstWhere(
      (server) => server.deviceKey == activeKey,
      orElse: () => servers.first,
    );
    final payload = <String, dynamic>{
      'schema_version': savedServersSchemaVersion,
      'servers': servers.map((server) => server.toJson()).toList(),
    };
    await prefs.setString(savedServersKey, json.encode(payload));
    await prefs.setString(SavedServerStore.activeDeviceKey, activeServer.deviceKey);
    // 兼容字段：旧版本只认单台 saved_server，写入当前活跃设备。
    await prefs.setString(savedServerKey, json.encode(activeServer.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(savedServerKey);
    await prefs.remove(savedServersKey);
    await prefs.remove(activeDeviceKey);
    await prefs.remove(legacyManualServerIpKey);
    await prefs.remove(legacyManualServerPortKey);
  }

  static String _resolveActiveKey(
    List<SavedServer> servers,
    String storedKey,
  ) {
    if (servers.isEmpty) {
      return '';
    }
    final normalized = storedKey.trim();
    if (normalized.isNotEmpty &&
        servers.any((server) => server.deviceKey == normalized)) {
      return normalized;
    }
    // 活跃设备缺失（首次迁移 / 设备被删）：退回最近连接过的一台。
    var latest = servers.first;
    for (final server in servers) {
      if (server.lastConnectedTs > latest.lastConnectedTs) {
        latest = server;
      }
    }
    return latest.deviceKey;
  }

  /// 宽松解析单设备 JSON（v1/v2 saved_server）：失败返回 null，不抛异常。
  static SavedServer? _parseStoredServer(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) {
        return null;
      }
      return SavedServer.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  /// 解析 v3 设备列表；格式不合法返回 null（调用方决定是否降级迁移）。
  static List<SavedServer>? _decodeServerList(String raw) {
    try {
      final decoded = json.decode(raw);
      Object? rawServers;
      if (decoded is List) {
        rawServers = decoded;
      } else if (decoded is Map) {
        rawServers = decoded['servers'];
      }
      if (rawServers is! List) {
        return null;
      }
      final servers = <SavedServer>[];
      for (final rawServer in rawServers) {
        if (rawServer is! Map) {
          continue;
        }
        try {
          servers.add(SavedServer.fromJson(Map<String, dynamic>.from(rawServer)));
        } catch (_) {
          // 单条损坏只跳过这条，不让整份列表失效。
        }
      }
      return servers;
    } catch (_) {
      return null;
    }
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
    // 直接写列表，不能走 save()：save() 会再次 loadSnapshot()，而此时旧
    // manual_server_* Key 还在，会递归触发迁移导致死循环。
    await saveAll([migrated], activeDeviceKey: migrated.deviceKey);
    return migrated;
  }
}
