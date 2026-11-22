import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicing/saved_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saved server serializes expected v2 json shape', () {
    const server = SavedServer(
      deviceId: 'abc123',
      ip: '192.168.1.23',
      port: 9527,
      name: 'Kevin-Desktop',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );

    expect(server.toJson(), {
      'schema_version': 2,
      'device_id': 'abc123',
      'ip': '192.168.1.23',
      'ips': ['192.168.1.23'],
      'port': 9527,
      'name': 'Kevin-Desktop',
      'os': 'windows',
      'last_connected_ts': 1713883200000,
      'addresses': [
        {
          'ip': '192.168.1.23',
          'network_key': '',
          'network_kind': 'unknown',
          'last_success_ts': 1713883200000,
          'last_seen_ts': 1713883200000,
          'success_count': 1,
          'failure_count': 0,
        },
      ],
    });
    expect(SavedServer.fromJson(server.toJson()), server);
  });

  test('saved server keeps primary ip first and de-duplicates candidates', () {
    const server = SavedServer(
      deviceId: 'abc123',
      ip: '10.16.177.83',
      ips: ['192.168.137.1', '10.16.177.83', '192.168.137.1'],
      port: 9527,
      name: 'Kevin-Desktop',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );

    expect(server.candidateIps, ['10.16.177.83', '192.168.137.1']);
    expect(server.toJson()['ips'], ['10.16.177.83', '192.168.137.1']);
  });

  test('saved server promotes connected ip without losing older candidates',
      () {
    const server = SavedServer(
      deviceId: 'abc123',
      ip: '192.168.137.1',
      ips: ['192.168.137.1', '10.16.177.83'],
      port: 9527,
      name: 'Kevin-Desktop',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );

    final updated = server.copyWith(
      ip: '10.16.177.83',
      ips: server.candidateIps,
    );

    expect(updated.candidateIps, ['10.16.177.83', '192.168.137.1']);
    expect(updated.toJson()['ips'], ['10.16.177.83', '192.168.137.1']);
  });

  test('QR scan merge keeps old candidates for the same device', () {
    const previous = SavedServer(
      deviceId: 'abc123',
      ip: '192.168.137.1',
      ips: ['192.168.137.1'],
      port: 9527,
      name: 'Kevin-Desktop',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );
    const incoming = SavedServer(
      deviceId: 'abc123',
      ip: '10.16.177.83',
      ips: ['10.16.177.83'],
      port: 9527,
      name: 'Kevin-Desktop',
      os: 'windows',
      lastConnectedTs: 1713883300000,
    );

    final merged = incoming.mergeCandidateIpsFrom(previous);

    expect(merged.ip, '10.16.177.83');
    expect(merged.candidateIps, ['10.16.177.83', '192.168.137.1']);
  });

  test('QR scan merge does not keep old candidates for a replaced device', () {
    const previous = SavedServer(
      deviceId: 'old-device',
      ip: '192.168.137.1',
      ips: ['192.168.137.1'],
      port: 9527,
      name: 'Old-PC',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );
    const incoming = SavedServer(
      deviceId: 'new-device',
      ip: '10.16.177.83',
      ips: ['10.16.177.83'],
      port: 9527,
      name: 'New-PC',
      os: 'windows',
      lastConnectedTs: 1713883300000,
    );

    final merged = incoming.mergeCandidateIpsFrom(previous);

    expect(merged.candidateIps, ['10.16.177.83']);
  });

  test('QR scan merge preserves legacy candidates without device id', () {
    const previous = SavedServer(
      deviceId: '',
      ip: '192.168.137.1',
      ips: ['192.168.137.1'],
      port: 9527,
      name: '',
      os: '',
      lastConnectedTs: 1713883200000,
    );
    const incoming = SavedServer(
      deviceId: 'abc123',
      ip: '10.16.177.83',
      ips: ['10.16.177.83'],
      port: 9527,
      name: 'Kevin-Desktop',
      os: 'windows',
      lastConnectedTs: 1713883300000,
    );

    final merged = incoming.mergeCandidateIpsFrom(previous);

    expect(merged.candidateIps, ['10.16.177.83', '192.168.137.1']);
  });

  test('saved server loads legacy single-ip blobs as one candidate', () {
    final server = SavedServer.fromJson({
      'schema_version': 1,
      'device_id': 'abc123',
      'ip': '192.168.137.1',
      'port': 9527,
      'name': 'Kevin-Desktop',
      'os': 'windows',
      'last_connected_ts': 1713883200000,
    });

    expect(server.schemaVersion, 2);
    expect(server.ip, '192.168.137.1');
    expect(server.candidateIps, ['192.168.137.1']);
    expect(server.addressBook.addressFor('192.168.137.1'), isNotNull);
    expect(server.toJson()['schema_version'], 2);
  });

  test('store saves and loads saved_server blob', () async {
    const store = SavedServerStore();
    const server = SavedServer(
      deviceId: 'abc123',
      ip: '192.168.1.23',
      port: 9527,
      name: 'Kevin-Desktop',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );

    await store.save(server);

    final loaded = await store.load();
    expect(loaded, server);
  });

  test('store migrates legacy manual ip keys to saved_server', () async {
    SharedPreferences.setMockInitialValues({
      SavedServerStore.legacyManualServerIpKey: '10.0.0.8',
      SavedServerStore.legacyManualServerPortKey: 9527,
    });

    const store = SavedServerStore();
    final migrated = await store.load();

    expect(migrated, isNotNull);
    expect(migrated!.deviceId, '');
    expect(migrated.ip, '10.0.0.8');
    expect(migrated.port, 9527);

    final prefs = await SharedPreferences.getInstance();
    expect(
        prefs.containsKey(SavedServerStore.legacyManualServerIpKey), isFalse);
    expect(
      prefs.containsKey(SavedServerStore.legacyManualServerPortKey),
      isFalse,
    );

    final rawSavedServer = prefs.getString(SavedServerStore.savedServerKey);
    expect(rawSavedServer, isNotNull);
    final savedJson = json.decode(rawSavedServer!) as Map<String, dynamic>;
    expect(savedJson['schema_version'], 2);
    expect(savedJson['ip'], '10.0.0.8');
    expect(savedJson['ips'], ['10.0.0.8']);
    expect(savedJson['port'], 9527);
    expect(savedJson['addresses'], isA<List<dynamic>>());
  });

  test('store keeps multiple paired devices and active device key', () async {
    const store = SavedServerStore();
    const pcA = SavedServer(
      deviceId: 'pc-a',
      ip: '192.168.1.10',
      port: 9527,
      name: 'Office-PC',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );
    const pcB = SavedServer(
      deviceId: 'pc-b',
      ip: '192.168.1.20',
      port: 9527,
      name: 'Home-Laptop',
      os: 'linux',
      lastConnectedTs: 1713883300000,
    );

    await store.saveAll([pcA, pcB], activeDeviceKey: 'pc-b');

    final snapshot = await store.loadSnapshot();
    expect(snapshot.servers.map((server) => server.deviceKey), ['pc-a', 'pc-b']);
    expect(snapshot.activeDeviceKey, 'pc-b');
    // 兼容旧版本/旧代码：saved_server 仍写当前活跃设备。
    final loadedSingle = await store.load();
    expect(loadedSingle, pcB);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(SavedServerStore.savedServersKey), isNotNull);
    expect(prefs.getString(SavedServerStore.activeDeviceKey), 'pc-b');
    final legacyJson = json.decode(
      prefs.getString(SavedServerStore.savedServerKey)!,
    ) as Map<String, dynamic>;
    expect(legacyJson['device_id'], 'pc-b');
  });

  test('store migrates legacy single saved_server into v3 device list', () async {
    const legacy = SavedServer(
      deviceId: 'pc-legacy',
      ip: '192.168.1.30',
      port: 9527,
      name: 'Legacy-PC',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );
    SharedPreferences.setMockInitialValues({
      SavedServerStore.savedServerKey: jsonEncode(legacy.toJson()),
    });

    const store = SavedServerStore();
    final snapshot = await store.loadSnapshot();

    expect(snapshot.servers, hasLength(1));
    expect(snapshot.servers.single.deviceKey, 'pc-legacy');
    expect(snapshot.activeDeviceKey, 'pc-legacy');

    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getString(SavedServerStore.savedServersKey);
    expect(rawList, isNotNull);
    final decoded = json.decode(rawList!) as Map<String, dynamic>;
    expect(decoded['schema_version'], SavedServerStore.savedServersSchemaVersion);
    expect(decoded['servers'], hasLength(1));
  });

  test('store reconciles legacy single-device mirror after a downgrade', () async {
    const pcA = SavedServer(
      deviceId: 'pc-a',
      ip: '192.168.1.10',
      port: 9527,
      name: 'Office-PC',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );
    // 模拟：v3 列表里有 pc-a，但降级到旧 APK 期间又配对了 pc-b，旧版只写
    // 单设备 saved_server。升级回来必须把 pc-b 合并回列表并设为活跃设备。
    const pcB = SavedServer(
      deviceId: 'pc-b',
      ip: '192.168.1.20',
      port: 9527,
      name: 'Home-Laptop',
      os: 'linux',
      lastConnectedTs: 1713883400000,
    );
    SharedPreferences.setMockInitialValues({
      SavedServerStore.savedServersKey: jsonEncode({
        'schema_version': SavedServerStore.savedServersSchemaVersion,
        'servers': [pcA.toJson()],
      }),
      SavedServerStore.activeDeviceKey: 'pc-a',
      SavedServerStore.savedServerKey: jsonEncode(pcB.toJson()),
    });

    const store = SavedServerStore();
    final snapshot = await store.loadSnapshot();

    expect(snapshot.servers.map((server) => server.deviceKey), ['pc-a', 'pc-b']);
    expect(snapshot.activeDeviceKey, 'pc-b');
    final prefs = await SharedPreferences.getInstance();
    final rawList = prefs.getString(SavedServerStore.savedServersKey)!;
    final decoded = json.decode(rawList) as Map<String, dynamic>;
    expect(decoded['servers'], hasLength(2));
    expect(prefs.getString(SavedServerStore.activeDeviceKey), 'pc-b');
  });

  test('store reconciliation absorbs a newer same-device mirror identity', () async {
    const listed = SavedServer(
      deviceId: 'pc-a',
      ip: '192.168.1.10',
      ips: ['192.168.1.10'],
      port: 9527,
      name: 'Old-Name',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );
    // 降级期间同一台设备更新了名字/主地址；升级回来应以镜像的身份字段为准，
    // 同时保留列表里的旧地址历史。
    const mirror = SavedServer(
      deviceId: 'pc-a',
      ip: '192.168.1.11',
      ips: ['192.168.1.11', '192.168.1.10'],
      port: 9527,
      name: 'Office-PC',
      os: 'windows',
      lastConnectedTs: 1713883400000,
    );
    SharedPreferences.setMockInitialValues({
      SavedServerStore.savedServersKey: jsonEncode({
        'schema_version': SavedServerStore.savedServersSchemaVersion,
        'servers': [listed.toJson()],
      }),
      SavedServerStore.activeDeviceKey: 'pc-a',
      SavedServerStore.savedServerKey: jsonEncode(mirror.toJson()),
    });

    const store = SavedServerStore();
    final snapshot = await store.loadSnapshot();

    expect(snapshot.servers, hasLength(1));
    final reconciled = snapshot.servers.single;
    expect(reconciled.name, 'Office-PC');
    expect(reconciled.ip, '192.168.1.11');
    expect(reconciled.lastConnectedTs, 1713883400000);
    expect(reconciled.candidateIps, containsAll(<String>['192.168.1.11', '192.168.1.10']));
  });

  test('store falls back to legacy mirror when v3 entries are all corrupt', () async {
    const legacy = SavedServer(
      deviceId: 'pc-legacy',
      ip: '192.168.1.30',
      port: 9527,
      name: 'Legacy-PC',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );
    SharedPreferences.setMockInitialValues({
      SavedServerStore.savedServersKey: jsonEncode({
        'schema_version': SavedServerStore.savedServersSchemaVersion,
        'servers': [
          {'bad': 'entry'},
          'not-a-map',
        ],
      }),
      SavedServerStore.savedServerKey: jsonEncode(legacy.toJson()),
    });

    const store = SavedServerStore();
    final snapshot = await store.loadSnapshot();

    expect(snapshot.servers, hasLength(1));
    expect(snapshot.servers.single.deviceKey, 'pc-legacy');
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getString(SavedServerStore.savedServersKey),
      contains('pc-legacy'),
    );
  });

  test('store save() upserts by device key without dropping other devices', () async {
    const store = SavedServerStore();
    const pcA = SavedServer(
      deviceId: 'pc-a',
      ip: '192.168.1.10',
      port: 9527,
      name: 'Office-PC',
      os: 'windows',
      lastConnectedTs: 1713883200000,
    );
    const pcB = SavedServer(
      deviceId: 'pc-b',
      ip: '192.168.1.20',
      port: 9527,
      name: 'Home-Laptop',
      os: 'linux',
      lastConnectedTs: 1713883300000,
    );
    await store.saveAll([pcA, pcB], activeDeviceKey: 'pc-b');

    final updatedA = pcA.copyWith(lastConnectedTs: 1713883400000);
    await store.save(updatedA);

    final snapshot = await store.loadSnapshot();
    expect(snapshot.servers.map((server) => server.deviceKey), ['pc-a', 'pc-b']);
    expect(snapshot.servers.first.lastConnectedTs, 1713883400000);
    expect(snapshot.activeDeviceKey, 'pc-a');
  });
}
