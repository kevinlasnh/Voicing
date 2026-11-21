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
}
