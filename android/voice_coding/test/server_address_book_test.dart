import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicing/connection_tuning.dart';
import 'package:voicing/network_profile.dart';
import 'package:voicing/saved_server.dart';
import 'package:voicing/server_address_book.dart';

/// 网络画像 + 地址簿（schema v2 / 跨网络排序 / 合并 / 裁剪不变量）单元测试。
///
/// 全部纯计算 + SharedPreferences mock，不碰真实网络与真实时间，整份文件
/// 毫秒级完成。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('NetworkSnapshot 网络画像', () {
    test('representative networkKey prefers non-VPN private wifi interface', () {
      const snapshot = NetworkSnapshot(
        interfaces: [
          NetworkInterfaceInfo(
            name: 'wlan0',
            ip: '192.168.1.5',
            prefixLength: 24,
            kind: NetworkInterfaceKind.wifi,
          ),
          NetworkInterfaceInfo(
            name: 'tun0',
            ip: '100.64.0.9',
            prefixLength: 32,
            kind: NetworkInterfaceKind.vpn,
          ),
          NetworkInterfaceInfo(
            name: 'rmnet0',
            ip: '10.20.30.40',
            prefixLength: 24,
            kind: NetworkInterfaceKind.mobile,
          ),
        ],
      );

      expect(snapshot.networkKey, 'wifi:192.168.1.0/24');
      expect(snapshot.primaryKind, 'wifi');
      expect(snapshot.hasTailscale, isTrue);
      expect(snapshot.hasPrivateLan, isTrue);
      expect(snapshot.containsInLocalSubnet('192.168.1.88'), isTrue);
      expect(snapshot.containsInLocalSubnet('10.20.30.99'), isTrue);
      expect(snapshot.containsInLocalSubnet('172.17.0.1'), isFalse);
      expect(snapshot.containsInLocalSubnet('100.64.0.7'), isFalse);
    });

    test('vpn-only snapshot is marked with vpn key prefix', () {
      const snapshot = NetworkSnapshot(
        interfaces: [
          NetworkInterfaceInfo(
            name: 'tun0',
            ip: '100.64.0.9',
            prefixLength: 32,
            kind: NetworkInterfaceKind.vpn,
          ),
        ],
      );

      expect(snapshot.networkKey, 'vpn:100.64.0.9/32');
      expect(snapshot.primaryKind, 'vpn');
      expect(snapshot.hasTailscale, isTrue);
    });

    test('candidate network context only tags addresses inside local subnet', () {
      const snapshot = NetworkSnapshot(
        interfaces: [
          NetworkInterfaceInfo(
            name: 'wlan0',
            ip: '192.168.1.5',
            prefixLength: 24,
            kind: NetworkInterfaceKind.wifi,
          ),
        ],
      );

      expect(snapshot.networkContextFor('192.168.1.50').networkKey,
          'wifi:192.168.1.0/24');
      expect(
          snapshot.networkContextFor('192.168.1.50').networkKind, 'wifi');
      // PC 的 docker 网段不在当前子网，不能被误标成当前网络。
      expect(snapshot.networkContextFor('172.17.0.1').networkKey, '');
      expect(snapshot.networkContextFor('100.64.0.7').networkKey, '');
    });

    test('IPv4 helpers validate, mask and classify addresses', () {
      expect(Ipv4.isValid('192.168.1.1'), isTrue);
      expect(Ipv4.isValid('999.1.1.1'), isFalse);
      expect(Ipv4.networkCidr('192.168.1.23', 24), '192.168.1.0/24');
      expect(Ipv4.isPrivateLan('172.16.5.5'), isTrue);
      expect(Ipv4.isPrivateLan('172.32.5.5'), isFalse);
      expect(Ipv4.isTailscaleCgnat('100.64.0.7'), isTrue);
      expect(Ipv4.isTailscaleCgnat('100.128.0.7'), isFalse);
    });
  });

  group('schema v1 -> v2 迁移', () {
    test('saved server v1 json migrates into address book without losing ips', () {
      final server = SavedServer.fromJson({
        'schema_version': 1,
        'device_id': 'pc-1',
        'ip': '192.168.1.50',
        'ips': ['192.168.1.50', '10.0.0.9'],
        'port': 9527,
        'name': 'Kevin-Desktop',
        'os': 'windows',
        'last_connected_ts': 1234,
      });

      expect(server.schemaVersion, 2);
      expect(server.candidateIps, ['192.168.1.50', '10.0.0.9']);
      final book = server.addressBook;
      expect(book.addressFor('192.168.1.50')!.lastSuccessTs, 1234);
      expect(book.addressFor('192.168.1.50')!.successCount, 1);
      expect(book.addressFor('10.0.0.9')!.successCount, 0);
      expect(book.ips.toSet(), {'192.168.1.50', '10.0.0.9'});

      final migrated = server.toJson();
      expect(migrated['schema_version'], 2);
      expect(migrated['ip'], '192.168.1.50');
      expect(migrated['ips'], ['192.168.1.50', '10.0.0.9']);
      expect(migrated['addresses'], isA<List<dynamic>>());
    });

    test('store rewrites v1 blob as schema v2 after load', () async {
      final v1Blob = jsonEncode({
        'schema_version': 1,
        'device_id': 'pc-1',
        'ip': '192.168.1.50',
        'ips': ['192.168.1.50'],
        'port': 9527,
        'name': 'PC',
        'os': 'linux',
        'last_connected_ts': 1234,
      });
      SharedPreferences.setMockInitialValues({
        SavedServerStore.savedServerKey: v1Blob,
      });

      final loaded = await const SavedServerStore().load();

      expect(loaded, isNotNull);
      expect(loaded!.schemaVersion, 2);
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(SavedServerStore.savedServerKey)!;
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['schema_version'], 2);
      expect(decoded['addresses'], isA<List<dynamic>>());
    });
  });

  group('跨网络合并', () {
    test('QR rescan merges history and keeps every network success', () {
      const snapshotA = NetworkSnapshot(
        interfaces: [
          NetworkInterfaceInfo(
            name: 'wlan0',
            ip: '192.168.9.5',
            prefixLength: 24,
            kind: NetworkInterfaceKind.wifi,
          ),
        ],
      );
      const snapshotB = NetworkSnapshot(
        interfaces: [
          NetworkInterfaceInfo(
            name: 'wlan0',
            ip: '192.168.1.5',
            prefixLength: 24,
            kind: NetworkInterfaceKind.wifi,
          ),
        ],
      );

      // 第一次扫码（网络 A）：192.168.9.9 + Tailscale 候选，成功地址记录网络 A。
      var bookA = ServerAddressBook.initialBookForCandidates(
        candidateIps: const ['192.168.9.9', '100.64.0.8'],
        snapshot: snapshotA,
        nowMs: 1000,
      );
      bookA = bookA.recordSuccess(
        ip: '192.168.9.9',
        networkKey: snapshotA.networkKey,
        networkKind: 'wifi',
        nowMs: 2000,
      );
      final serverA = SavedServer(
        deviceId: 'pc-1',
        ip: '192.168.9.9',
        ips: const ['192.168.9.9', '100.64.0.8'],
        port: 9527,
        name: 'PC',
        os: 'linux',
        lastConnectedTs: 2000,
        addresses: bookA,
      );

      // 第二次扫码（网络 B）：历史地址簿与本次成功地址合并。
      var bookB = ServerAddressBook.initialBookForCandidates(
        candidateIps: const ['192.168.1.50', '192.168.1.51'],
        snapshot: snapshotB,
        nowMs: 3000,
      );
      bookB = bookB.recordSuccess(
        ip: '192.168.1.50',
        networkKey: snapshotB.networkKey,
        networkKind: 'wifi',
        nowMs: 4000,
      );
      final incoming = SavedServer(
        deviceId: 'pc-1',
        ip: '192.168.1.50',
        ips: const ['192.168.1.50', '192.168.1.51'],
        port: 9527,
        name: 'PC',
        os: 'linux',
        lastConnectedTs: 4000,
        addresses: bookB,
      );

      final merged = incoming.mergeAddressHistoryFrom(serverA);

      expect(merged.ip, '192.168.1.50');
      expect(
        merged.candidateIps,
        containsAll([
          '192.168.1.50',
          '192.168.1.51',
          '192.168.9.9',
          '100.64.0.8',
        ]),
      );
      final mergedBook = merged.addressBook;
      expect(
        mergedBook.successfulNetworkKeys.toSet(),
        {'wifi:192.168.9.0/24', 'wifi:192.168.1.0/24'},
      );
      expect(
        mergedBook.addressFor('192.168.9.9')!.networkKey,
        'wifi:192.168.9.0/24',
      );
      expect(mergedBook.addressFor('192.168.9.9')!.successCount, 1);
      expect(
        mergedBook.addressFor('192.168.1.50')!.networkKey,
        'wifi:192.168.1.0/24',
      );

      // 回到任一网络，各自上次成功的地址都排第一（免重扫的核心排序语义）。
      expect(
        mergedBook.rankedIpsFor(snapshotA, nowMs: 5000).first,
        '192.168.9.9',
      );
      expect(
        mergedBook.rankedIpsFor(snapshotB, nowMs: 5000).first,
        '192.168.1.50',
      );
    });
  });

  group('候选评分排序', () {
    const weights = AddressBookWeights();
    const currentSnapshot = NetworkSnapshot(
      interfaces: [
        NetworkInterfaceInfo(
          name: 'wlan0',
          ip: '192.168.1.5',
          prefixLength: 24,
          kind: NetworkInterfaceKind.wifi,
        ),
        NetworkInterfaceInfo(
          name: 'tun0',
          ip: '100.64.0.9',
          prefixLength: 32,
          kind: NetworkInterfaceKind.vpn,
        ),
      ],
    );

    test('networkKey match > same subnet > tailscale > foreign private LAN', () {
      const book = ServerAddressBook([
        // 当前 networkKey 命中，但不在当前子网。
        SavedAddress(
          ip: '192.168.9.9',
          networkKey: 'wifi:192.168.1.0/24',
          networkKind: 'wifi',
        ),
        // 在当前本地子网，但 networkKey 是别的网络。
        SavedAddress(
          ip: '192.168.1.50',
          networkKey: 'wifi:192.168.9.0/24',
          networkKind: 'wifi',
        ),
        // 双端 Tailscale 候选。
        SavedAddress(ip: '100.64.0.7'),
        // PC docker 网段：不可路由，必须最后。
        SavedAddress(ip: '172.17.0.1'),
      ]);

      final ranked = book.rankedIpsFor(currentSnapshot, nowMs: 100000);
      expect(ranked, ['192.168.9.9', '192.168.1.50', '100.64.0.7', '172.17.0.1']);

      final scoreByIp = {
        for (final entry in book.addresses)
          entry.ip: book.scoreOf(
            entry,
            currentSnapshot,
            nowMs: 100000,
            weights: weights,
          ),
      };
      expect(scoreByIp['192.168.9.9'], 1000);
      expect(scoreByIp['192.168.1.50'], 800);
      expect(scoreByIp['100.64.0.7'], 700);
      expect(scoreByIp['172.17.0.1'], -400);
      expect(
        scoreByIp['192.168.9.9']! > scoreByIp['192.168.1.50']!,
        isTrue,
      );
      expect(
        scoreByIp['192.168.1.50']! > scoreByIp['100.64.0.7']!,
        isTrue,
      );
    });

    test('recent success and success/failure counts refine equal base scores', () {
      const snapshot = NetworkSnapshot(
        interfaces: [
          NetworkInterfaceInfo(
            name: 'wlan0',
            ip: '192.168.1.5',
            prefixLength: 24,
            kind: NetworkInterfaceKind.wifi,
          ),
        ],
      );
      const book = ServerAddressBook([
        SavedAddress(
          ip: '192.168.1.10',
          lastSuccessTs: 90000,
          lastSeenTs: 90000,
          successCount: 3,
        ),
        SavedAddress(
          ip: '192.168.1.11',
          lastSuccessTs: 1000,
          lastSeenTs: 1000,
          successCount: 0,
          failureCount: 4,
        ),
        SavedAddress(ip: '192.168.1.12'),
      ]);

      final ranked = book.rankedIpsFor(snapshot, nowMs: 100000);
      expect(ranked.first, '192.168.1.10');
      expect(ranked.last, '192.168.1.12');
    });
  });

  group('裁剪不变量', () {
    test('trim keeps latest successful address of every networkKey', () {
      final addresses = <SavedAddress>[];
      // 12 条同网络、从未成功但 lastSeen 很新的地址。
      for (var index = 0; index < 12; index++) {
        addresses.add(
          SavedAddress(
            ip: '192.168.1.${100 + index}',
            networkKey: 'wifi:192.168.1.0/24',
            networkKind: 'wifi',
            lastSeenTs: 9000 + index,
          ),
        );
      }
      // 另外两个不同网络的历史成功地址（时间更早）。
      addresses.add(
        const SavedAddress(
          ip: '10.0.0.50',
          networkKey: 'wifi:10.0.0.0/24',
          networkKind: 'wifi',
          lastSuccessTs: 5000,
          lastSeenTs: 5000,
          successCount: 1,
        ),
      );
      addresses.add(
        const SavedAddress(
          ip: '172.20.0.50',
          networkKey: 'wifi:172.20.0.0/24',
          networkKind: 'wifi',
          lastSuccessTs: 6000,
          lastSeenTs: 6000,
          successCount: 1,
        ),
      );

      final trimmed =
          ServerAddressBook(addresses).trimmed(nowMs: 10000, maxAddresses: 12);

      expect(trimmed.addresses.length, 12);
      expect(trimmed.ips, contains('10.0.0.50'));
      expect(trimmed.ips, contains('172.20.0.50'));
      // 裁剪稳定：再裁一次结果不变。
      expect(
        trimmed.trimmed(nowMs: 10000, maxAddresses: 12).addresses,
        trimmed.addresses,
      );
    });

    test('trim never drops protected network history even above the cap', () {
      final addresses = <SavedAddress>[
        for (var index = 0; index < 6; index++)
          SavedAddress(
            ip: '10.$index.0.10',
            networkKey: 'wifi:10.$index.0.0/24',
            lastSuccessTs: 1000 + index,
            lastSeenTs: 1000 + index,
            successCount: 1,
          ),
      ];

      final trimmed =
          ServerAddressBook(addresses).trimmed(nowMs: 10000, maxAddresses: 2);

      // 保护集合大于上限时宁可变大，也不破坏「每个网络保留最近成功地址」。
      expect(trimmed.addresses.length, 6);
    });
  });

  group('成功/失败计数与 JSON round-trip', () {
    test('recordFailure increments and recordSuccess gradually offsets it', () {
      var book = const ServerAddressBook([
        SavedAddress(
          ip: '192.168.1.50',
          networkKey: 'wifi:192.168.1.0/24',
          networkKind: 'wifi',
          lastSuccessTs: 1000,
          lastSeenTs: 1000,
          successCount: 2,
          failureCount: 2,
        ),
      ]);

      book = book.recordFailure(ip: '192.168.1.50', nowMs: 2000);
      expect(book.addressFor('192.168.1.50')!.failureCount, 3);
      expect(book.addressFor('192.168.1.50')!.successCount, 2);

      book = book.recordSuccess(
        ip: '192.168.1.50',
        networkKey: 'wifi:192.168.1.0/24',
        networkKind: 'wifi',
        nowMs: 3000,
      );
      expect(book.addressFor('192.168.1.50')!.successCount, 3);
      expect(book.addressFor('192.168.1.50')!.failureCount, 2);
      expect(book.addressFor('192.168.1.50')!.lastSuccessTs, 3000);
    });

    test('failure of unknown candidate never creates success history', () {
      var book = ServerAddressBook.empty;
      book = book.recordFailure(ip: '172.17.0.1', nowMs: 2000);

      final entry = book.addressFor('172.17.0.1')!;
      expect(entry.successCount, 0);
      expect(entry.lastSuccessTs, 0);
      expect(entry.failureCount, 1);
    });

    test('address book and saved server JSON round-trip', () {
      const book = ServerAddressBook([
        SavedAddress(
          ip: '192.168.1.50',
          networkKey: 'wifi:192.168.1.0/24',
          networkKind: 'wifi',
          lastSuccessTs: 2000,
          lastSeenTs: 3000,
          successCount: 2,
          failureCount: 1,
        ),
        SavedAddress(ip: '100.64.0.8'),
      ]);
      expect(ServerAddressBook.fromJson(book.toJson()), book);

      const server = SavedServer(
        deviceId: 'pc-1',
        ip: '192.168.1.50',
        ips: ['192.168.1.50', '100.64.0.8'],
        port: 9527,
        name: 'PC',
        os: 'linux',
        lastConnectedTs: 3000,
        addresses: book,
      );
      final restored = SavedServer.fromJson(server.toJson());
      expect(restored, server);
      expect(
        restored.addressBook.addressFor('192.168.1.50')!.networkKey,
        'wifi:192.168.1.0/24',
      );
    });

    test('unknown network still yields a stable deterministic order', () {
      const book = ServerAddressBook([
        SavedAddress(
          ip: '192.168.1.9',
          lastSuccessTs: 200,
          lastSeenTs: 300,
          successCount: 2,
        ),
        SavedAddress(
          ip: '10.0.0.9',
          lastSuccessTs: 100,
          lastSeenTs: 200,
          successCount: 1,
        ),
        SavedAddress(ip: '172.16.0.9', lastSeenTs: 100),
        SavedAddress(
          ip: '192.168.1.8',
          lastSuccessTs: 100,
          lastSeenTs: 200,
          successCount: 1,
        ),
      ]);

      final first = book.rankedIpsFor(NetworkSnapshot.empty, nowMs: 100000);
      final second = book.rankedIpsFor(NetworkSnapshot.empty, nowMs: 100000);

      expect(first, second);
      expect(
        first,
        ['192.168.1.9', '10.0.0.9', '192.168.1.8', '172.16.0.9'],
      );
    });
  });
}
