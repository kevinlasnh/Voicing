import 'package:flutter/foundation.dart';

import 'connection_tuning.dart';
import 'network_profile.dart';

/// 单个已知服务器地址的历史记录（2026-11-20 新增，schema v2 核心）。
///
/// 纯数据 + 纯计算，不做任何网络 IO、不读时钟（时间由调用方传入 nowMs），
/// 因此单元测试可以完全确定性地驱动。地址簿记录「哪个 IP 在哪个网络环境
/// 成功过」，这是同一个 PC 在多个网络都能免重扫自动连接的关键。
@immutable
class SavedAddress {
  const SavedAddress({
    required this.ip,
    this.networkKey = '',
    this.networkKind = 'unknown',
    this.lastSuccessTs = 0,
    this.lastSeenTs = 0,
    this.successCount = 0,
    this.failureCount = 0,
  });

  /// 目标地址（PC 的某个实际可监听 IPv4）。
  final String ip;

  /// 该地址成功连接时手机所处的网络环境 Key，如 `wifi:192.168.1.0/24`。
  /// 空字符串表示历史数据 / 未知网络（v1 迁移、二维码首次扫码）。
  final String networkKey;

  /// 网络环境类型：wifi / ethernet / mobile / vpn / unknown。
  final String networkKind;

  /// 最近一次成功连接的时间戳（毫秒）；0 表示从未成功。
  final int lastSuccessTs;

  /// 最近一次被探测（成功或失败）的时间戳（毫秒）。
  final int lastSeenTs;

  final int successCount;
  final int failureCount;

  bool get hasNetworkKey => networkKey.isNotEmpty;

  /// 是否 Tailscale CGNAT 地址（100.64.0.0/10）。
  bool get isTailscale => Ipv4.isTailscaleCgnat(ip);

  /// 是否 RFC1918 私有 LAN 地址（不含 Tailscale CGNAT）。
  bool get isPrivateLan => Ipv4.isPrivateLan(ip) && !isTailscale;

  SavedAddress copyWith({
    String? ip,
    String? networkKey,
    String? networkKind,
    int? lastSuccessTs,
    int? lastSeenTs,
    int? successCount,
    int? failureCount,
  }) {
    return SavedAddress(
      ip: ip ?? this.ip,
      networkKey: networkKey ?? this.networkKey,
      networkKind: networkKind ?? this.networkKind,
      lastSuccessTs: lastSuccessTs ?? this.lastSuccessTs,
      lastSeenTs: lastSeenTs ?? this.lastSeenTs,
      successCount: successCount ?? this.successCount,
      failureCount: failureCount ?? this.failureCount,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'ip': ip,
      'network_key': networkKey,
      'network_kind': networkKind,
      'last_success_ts': lastSuccessTs,
      'last_seen_ts': lastSeenTs,
      'success_count': successCount,
      'failure_count': failureCount,
    };
  }

  /// 宽松解析：非法条目返回 null，由地址簿跳过（历史数据可能被手工改坏）。
  static SavedAddress? tryParse(Object? raw) {
    if (raw is! Map) {
      return null;
    }
    final ip = raw['ip'];
    if (ip is! String || !Ipv4.isValid(ip.trim())) {
      return null;
    }
    final normalizedIp = ip.trim();
    return SavedAddress(
      ip: normalizedIp,
      networkKey: _readString(raw['network_key']),
      networkKind: _readString(raw['network_kind']).isEmpty
          ? 'unknown'
          : _readString(raw['network_kind']),
      lastSuccessTs: _readInt(raw['last_success_ts']) ?? 0,
      lastSeenTs: _readInt(raw['last_seen_ts']) ?? 0,
      successCount: _readInt(raw['success_count']) ?? 0,
      failureCount: _readInt(raw['failure_count']) ?? 0,
    );
  }

  static String _readString(Object? value) => value is String ? value.trim() : '';

  static int? _readInt(Object? value) {
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
    return other is SavedAddress &&
        other.ip == ip &&
        other.networkKey == networkKey &&
        other.networkKind == networkKind &&
        other.lastSuccessTs == lastSuccessTs &&
        other.lastSeenTs == lastSeenTs &&
        other.successCount == successCount &&
        other.failureCount == failureCount;
  }

  @override
  int get hashCode => Object.hash(
        ip,
        networkKey,
        networkKind,
        lastSuccessTs,
        lastSeenTs,
        successCount,
        failureCount,
      );

  @override
  String toString() =>
      'SavedAddress($ip, key=$networkKey, kind=$networkKind, '
      'ok=$successCount, fail=$failureCount, lastOk=$lastSuccessTs)';
}

/// 服务器地址簿：纯 Dart 候选排序 / 合并 / 裁剪 / schema v2 序列化。
///
/// 核心不变量（有单测覆盖）：裁剪到上限时，**每个不同 networkKey 的最近成功
/// 地址都会被保留**。因此用户在家 WiFi / 公司 WiFi 各扫码成功后，即使地址
/// 历史超过上限，两个网络的成功地址也不会互相挤掉，回到任一网络都能免重扫。
class ServerAddressBook {
  const ServerAddressBook(this.addresses);

  /// 空地址簿；也是 SavedServer 未携带地址簿时的默认值。
  static const ServerAddressBook empty = ServerAddressBook(<SavedAddress>[]);

  /// 每个 networkKey 至少保留一条最近成功地址所需的排序权重。
  static const int defaultMaxAddresses = 12;

  final List<SavedAddress> addresses;

  bool get isEmpty => addresses.isEmpty;

  bool get isNotEmpty => addresses.isNotEmpty;

  List<String> get ips =>
      addresses.map((item) => item.ip).toList(growable: false);

  SavedAddress? addressFor(String ip) {
    for (final entry in addresses) {
      if (entry.ip == ip) {
        return entry;
      }
    }
    return null;
  }

  /// 所有成功过的 networkKey（去重，用于日志/调试与裁剪不变量）。
  List<String> get successfulNetworkKeys {
    final keys = <String>{};
    for (final entry in addresses) {
      if (entry.lastSuccessTs > 0) {
        keys.add(entry.networkKey);
      }
    }
    return keys.toList(growable: false);
  }

  /// 从 schema v2 JSON 的 addresses 数组解析；非法条目跳过，不抛异常。
  factory ServerAddressBook.fromJson(Object? raw) {
    if (raw is! List) {
      return ServerAddressBook.empty;
    }
    final parsed = <SavedAddress>[];
    final seen = <String>{};
    for (final entry in raw) {
      final address = SavedAddress.tryParse(entry);
      if (address == null || !seen.add(address.ip)) {
        continue;
      }
      parsed.add(address);
    }
    return ServerAddressBook(parsed);
  }

  List<Map<String, dynamic>> toJson() {
    return addresses.map((entry) => entry.toJson()).toList(growable: false);
  }

  /// v1 数据迁移：旧 saved_server 只有 ip/ips，没有网络信息。
  ///
  /// 把主地址视为最近成功地址（时间取 last_connected_ts），其余候选只有
  /// 「见过」时间、没有成功计数；后续真实连接成功会补上网络 Key。
  factory ServerAddressBook.fromLegacyCandidates({
    required String primaryIp,
    required Iterable<String> candidateIps,
    required int lastConnectedTs,
  }) {
    final result = <SavedAddress>[];
    final seen = <String>{};
    for (final rawIp in candidateIps) {
      final ip = rawIp.trim();
      if (ip.isEmpty || !seen.add(ip)) {
        continue;
      }
      final isPrimary = ip == primaryIp;
      result.add(
        SavedAddress(
          ip: ip,
          lastSuccessTs: isPrimary ? lastConnectedTs : 0,
          lastSeenTs: lastConnectedTs,
          successCount: isPrimary && lastConnectedTs > 0 ? 1 : 0,
        ),
      );
    }
    if (result.isEmpty && primaryIp.isNotEmpty && Ipv4.isValid(primaryIp)) {
      result.add(
        SavedAddress(
          ip: primaryIp,
          lastSuccessTs: lastConnectedTs,
          lastSeenTs: lastConnectedTs,
          successCount: lastConnectedTs > 0 ? 1 : 0,
        ),
      );
    }
    return ServerAddressBook(result);
  }

  /// 二维码候选初始化地址簿：与本地接口同子网的候选直接标注当前 networkKey，
  /// 其它候选保持未知网络，等真正成功后再补。
  factory ServerAddressBook.initialBookForCandidates({
    required Iterable<String> candidateIps,
    required NetworkSnapshot snapshot,
    required int nowMs,
  }) {
    final result = <SavedAddress>[];
    final seen = <String>{};
    for (final rawIp in candidateIps) {
      final ip = rawIp.trim();
      if (ip.isEmpty || !seen.add(ip) || !Ipv4.isValid(ip)) {
        continue;
      }
      final context = snapshot.networkContextFor(ip);
      result.add(
        SavedAddress(
          ip: ip,
          networkKey: context.networkKey,
          networkKind: context.networkKind,
          lastSeenTs: nowMs,
        ),
      );
    }
    return ServerAddressBook(result);
  }

  /// 合并另一份地址历史：同一 IP 合并计数与时间，保留全部不同 IP。
  ServerAddressBook merge(Iterable<SavedAddress> incoming) {
    final result = List<SavedAddress>.of(addresses);
    final indexByIp = <String, int>{
      for (var i = 0; i < result.length; i++) result[i].ip: i,
    };
    for (final entry in incoming) {
      if (!Ipv4.isValid(entry.ip)) {
        continue;
      }
      final existingIndex = indexByIp[entry.ip];
      if (existingIndex == null) {
        indexByIp[entry.ip] = result.length;
        result.add(entry);
      } else {
        result[existingIndex] = _mergeEntry(result[existingIndex], entry);
      }
    }
    return ServerAddressBook(result);
  }

  static SavedAddress _mergeEntry(SavedAddress a, SavedAddress b) {
    // 网络上下文取「更近一次成功」的那条；都没成功过则优先已有非空 Key。
    final preferB = b.lastSuccessTs > a.lastSuccessTs ||
        (b.lastSuccessTs == a.lastSuccessTs &&
            a.networkKey.isEmpty &&
            b.networkKey.isNotEmpty);
    final contextSource = preferB ? b : a;
    final fallbackSource = a.networkKey.isNotEmpty ? a : b;
    final networkKey = contextSource.networkKey.isNotEmpty
        ? contextSource.networkKey
        : fallbackSource.networkKey;
    final networkKind = contextSource.networkKind != 'unknown'
        ? contextSource.networkKind
        : fallbackSource.networkKind;
    return SavedAddress(
      ip: a.ip,
      networkKey: networkKey,
      networkKind: networkKind,
      lastSuccessTs: a.lastSuccessTs > b.lastSuccessTs
          ? a.lastSuccessTs
          : b.lastSuccessTs,
      lastSeenTs: a.lastSeenTs > b.lastSeenTs ? a.lastSeenTs : b.lastSeenTs,
      successCount:
          a.successCount > b.successCount ? a.successCount : b.successCount,
      failureCount:
          a.failureCount > b.failureCount ? a.failureCount : b.failureCount,
    );
  }

  /// 记录一次真实成功：写网络上下文、提升成功计数、递减失败计数。
  ///
  /// 失败计数递减是为了让「一次网络抖动」造成的降权能被后续成功逐步抵消，
  /// 不会把某个网络的成功地址永久压下去。
  ServerAddressBook recordSuccess({
    required String ip,
    required String networkKey,
    required String networkKind,
    required int nowMs,
  }) {
    final normalizedIp = ip.trim();
    if (!Ipv4.isValid(normalizedIp)) {
      return this;
    }
    final result = List<SavedAddress>.of(addresses);
    final index = result.indexWhere((entry) => entry.ip == normalizedIp);
    if (index < 0) {
      result.add(
        SavedAddress(
          ip: normalizedIp,
          networkKey: networkKey,
          networkKind: networkKind,
          lastSuccessTs: nowMs,
          lastSeenTs: nowMs,
          successCount: 1,
        ),
      );
      return ServerAddressBook(result);
    }
    final previous = result[index];
    result[index] = previous.copyWith(
      networkKey: networkKey.isNotEmpty ? networkKey : previous.networkKey,
      networkKind: networkKind != 'unknown'
          ? networkKind
          : (previous.networkKind.isEmpty ? 'unknown' : previous.networkKind),
      lastSuccessTs: nowMs,
      lastSeenTs: nowMs,
      successCount: previous.successCount + 1,
      failureCount:
          previous.failureCount > 0 ? previous.failureCount - 1 : 0,
    );
    return ServerAddressBook(result);
  }

  /// 记录一次探测失败；只累加失败计数，绝不影响任何成功历史。
  ServerAddressBook recordFailure({required String ip, required int nowMs}) {
    final normalizedIp = ip.trim();
    if (!Ipv4.isValid(normalizedIp)) {
      return this;
    }
    final result = List<SavedAddress>.of(addresses);
    final index = result.indexWhere((entry) => entry.ip == normalizedIp);
    if (index < 0) {
      result.add(
        SavedAddress(
          ip: normalizedIp,
          lastSeenTs: nowMs,
          failureCount: 1,
        ),
      );
      return ServerAddressBook(result);
    }
    final previous = result[index];
    result[index] = previous.copyWith(
      lastSeenTs: nowMs,
      failureCount: previous.failureCount + 1,
    );
    return ServerAddressBook(result);
  }

  /// 计算单个候选在当前网络环境下的评分（越大越优先）。
  int scoreOf(
    SavedAddress candidate,
    NetworkSnapshot snapshot, {
    required int nowMs,
    AddressBookWeights weights = const AddressBookWeights(),
  }) {
    var score = 0;
    final currentKey = snapshot.networkKey;
    final keyMatches = currentKey.isNotEmpty && candidate.networkKey == currentKey;
    if (keyMatches) {
      score += weights.networkKeyMatchBonus;
    }

    final sameSubnet = snapshot.containsInLocalSubnet(candidate.ip);
    if (sameSubnet) {
      score += weights.sameSubnetBonus;
    }

    final currentHasTailscale = snapshot.hasTailscale;
    if (currentHasTailscale && candidate.isTailscale) {
      score += weights.dualTailscaleBonus;
    }

    if (candidate.isPrivateLan) {
      // 只有「当前网络已知、但候选既不同子网也没有本网络成功历史」的 LAN
      // 地址才是不可路由的（典型：PC 的 docker 网段 172.17.0.0/16，或 PC
      // 在另一个 WiFi 下的地址）。必须显著降权，避免它抢占前 3 竞速名额。
      // 注意：同子网或本网络成功过的 LAN 地址是「有证据可达」的，绝不能降权，
      // 否则会排到 Tailscale 兜底地址后面（2026-11-20 单测暴露的排序 bug）。
      if (snapshot.isKnown && !sameSubnet && !keyMatches) {
        score += weights.foreignPrivateLanPenalty;
        // 同场景下若手机还有 Tailscale 可用，隧道地址比「无证据的 LAN 地址」
        // 更可靠，再给一份轻微降权，保证双端 Tailscale 候选排在它前面。
        if (currentHasTailscale) {
          score += weights.localTailscaleLanPenalty;
        }
      }
    }

    score += weights.recencyBonus(
      lastSuccessTs: candidate.lastSuccessTs,
      nowMs: nowMs,
    );
    score += weights.countsBonus(
      successCount: candidate.successCount,
      failureCount: candidate.failureCount,
    );
    return score;
  }

  /// 按当前网络画像评分排序；同分时用时间/成功计数/IP 字典序保证确定性。
  List<SavedAddress> rankedFor(
    NetworkSnapshot snapshot, {
    required int nowMs,
    AddressBookWeights weights = const AddressBookWeights(),
  }) {
    final scored = List<_ScoredAddress>.generate(
      addresses.length,
      (index) => _ScoredAddress(
        address: addresses[index],
        index: index,
        score: scoreOf(
          addresses[index],
          snapshot,
          nowMs: nowMs,
          weights: weights,
        ),
      ),
    );
    scored.sort(_compareScored);
    return scored.map((entry) => entry.address).toList(growable: false);
  }

  /// 排序后的候选 IP 列表（地址簿可能包含重复？构造时已去重）。
  List<String> rankedIpsFor(
    NetworkSnapshot snapshot, {
    required int nowMs,
    AddressBookWeights weights = const AddressBookWeights(),
  }) {
    return rankedFor(snapshot, nowMs: nowMs, weights: weights)
        .map((entry) => entry.ip)
        .toList(growable: false);
  }

  static int _compareScored(_ScoredAddress a, _ScoredAddress b) {
    if (a.score != b.score) {
      return b.score - a.score;
    }
    if (a.address.lastSuccessTs != b.address.lastSuccessTs) {
      return b.address.lastSuccessTs - a.address.lastSuccessTs;
    }
    if (a.address.lastSeenTs != b.address.lastSeenTs) {
      return b.address.lastSeenTs - a.address.lastSeenTs;
    }
    if (a.address.successCount != b.address.successCount) {
      return b.address.successCount - a.address.successCount;
    }
    final byIp = a.address.ip.compareTo(b.address.ip);
    return byIp != 0 ? byIp : a.index - b.index;
  }

  /// 裁剪到上限，但永不丢弃「不同 networkKey 的最近成功地址」。
  ///
  /// 这是多网络免重扫的核心不变量：即使上限是 12、某个网络只成功过 1 次且
  /// 很久没连，它的最近成功地址也一定保留。保护集合本身超过上限时宁可变大
  /// 也不破坏不变量（不同网络数实际很小）。
  ServerAddressBook trimmed({
    required int nowMs,
    int maxAddresses = defaultMaxAddresses,
  }) {
    if (addresses.length <= maxAddresses) {
      return this;
    }
    final protected = <int>{};
    final latestSuccessByGroup = <String, int>{};
    for (var index = 0; index < addresses.length; index++) {
      final entry = addresses[index];
      if (entry.lastSuccessTs <= 0) {
        continue;
      }
      // 没有 networkKey 的旧数据归为同一组，保留最近成功的一条即可。
      final group = entry.networkKey.isEmpty ? '<unknown>' : entry.networkKey;
      final existing = latestSuccessByGroup[group];
      if (existing == null ||
          entry.lastSuccessTs > addresses[existing].lastSuccessTs) {
        latestSuccessByGroup[group] = index;
      }
    }
    protected.addAll(latestSuccessByGroup.values);

    final rankedIndexes = List<int>.generate(addresses.length, (index) => index)
      ..sort((a, b) => _compareForTrim(addresses[a], addresses[b], a, b));
    final kept = <int>{...protected};
    for (final index in rankedIndexes) {
      if (kept.length >= maxAddresses) {
        break;
      }
      kept.add(index);
    }
    final result = <SavedAddress>[
      for (var index = 0; index < addresses.length; index++)
        if (kept.contains(index)) addresses[index],
    ];
    return ServerAddressBook(result);
  }

  /// 裁剪用的网络无关排序：历史成功率越高、越近越优先。
  static int _compareForTrim(
    SavedAddress a,
    SavedAddress b,
    int indexA,
    int indexB,
  ) {
    if (a.lastSuccessTs != b.lastSuccessTs) {
      return b.lastSuccessTs - a.lastSuccessTs;
    }
    if (a.successCount != b.successCount) {
      return b.successCount - a.successCount;
    }
    if (a.lastSeenTs != b.lastSeenTs) {
      return b.lastSeenTs - a.lastSeenTs;
    }
    final byIp = a.ip.compareTo(b.ip);
    return byIp != 0 ? byIp : indexA - indexB;
  }

  @override
  bool operator ==(Object other) {
    if (other is! ServerAddressBook ||
        other.addresses.length != addresses.length) {
      return false;
    }
    for (var i = 0; i < addresses.length; i++) {
      if (other.addresses[i] != addresses[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(addresses);

  @override
  String toString() => 'ServerAddressBook($addresses)';
}

class _ScoredAddress {
  const _ScoredAddress({
    required this.address,
    required this.index,
    required this.score,
  });

  final SavedAddress address;
  final int index;
  final int score;
}
