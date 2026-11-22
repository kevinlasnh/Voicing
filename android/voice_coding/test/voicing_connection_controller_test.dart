import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicing/connection_recovery_policy.dart';
import 'package:voicing/connection_tuning.dart';
import 'package:voicing/network_profile.dart';
import 'package:voicing/saved_server.dart';
import 'package:voicing/server_address_book.dart';
import 'package:voicing/voicing_connection_controller.dart';
import 'package:voicing/voicing_websocket.dart';

/// `VoicingConnectionController` 连接路径单元测试（2026-11-20 新增）。
///
/// 全部使用 fake：FakeNetworkSnapshotProvider 注入网络画像，FakeChannelFactory
/// 注入建链/握手行为（不碰真实 socket/native channel），SharedPreferences 用
/// mock 存储。覆盖：
/// 1. 已保存重连按地址簿评分顺序竞速、winner 才是 _serverIp、失败候选不写成功历史；
/// 2. 扫码并行探测，只有完成 connected + ping(qr_scan) + pong 的候选胜出；
/// 3. generation 变化后旧竞速回调不生效；
/// 4. disconnected/connecting 状态网络变化立即重排重连，已连接不被扰动。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 每个用例必须从空的 SharedPreferences 开始：否则前一个用例保存的
  // saved_server 会被后一个用例 initialize() 直接加载，造成跨用例污染
  // （2026-11-20 全量跑时「generation 失效」用例曾因此拿到旧设备）。
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'saved reconnect races best address first and records success only on connected',
    () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      // 地址簿：同 networkKey/同子网的 B 地址应排第一；其它网络成功过的 A
      // 地址 + docker 网段分别排第二、第三（docker 不可路由被显著降权）。
      final savedServer = SavedServer(
        deviceId: 'pc-1',
        ip: '192.168.1.50',
        ips: const ['192.168.1.50', '192.168.9.9', '172.17.0.1'],
        port: 9527,
        name: 'FakePC',
        os: 'linux',
        lastConnectedTs: nowMs - 1000,
        addresses: ServerAddressBook([
          SavedAddress(
            ip: '192.168.1.50',
            networkKey: 'wifi:192.168.1.0/24',
            networkKind: 'wifi',
            lastSuccessTs: nowMs - 1000,
            lastSeenTs: nowMs - 1000,
            successCount: 2,
          ),
          SavedAddress(
            ip: '192.168.9.9',
            networkKey: 'wifi:192.168.9.0/24',
            networkKind: 'wifi',
            lastSuccessTs: nowMs - 5000,
            lastSeenTs: nowMs - 5000,
            successCount: 1,
          ),
          SavedAddress(ip: '172.17.0.1', lastSeenTs: nowMs - 9000),
        ]),
      );
      await seedSavedServer(savedServer);

      final provider = FakeNetworkSnapshotProvider(
        wifiSnapshot(ip: '192.168.1.5'),
      );
      final factory = FakeChannelFactory();
      // winner 故意延迟 30ms 才 connected，让 stagger 5/10ms 的失败候选先启动，
      // 从而验证失败计数只累加、不写成功历史。
      factory.behaviors['192.168.1.50'] = FakeServerBehavior(
        accept: true,
        connectedDelay: const Duration(milliseconds: 30),
      );
      factory.behaviors['192.168.9.9'] = FakeServerBehavior(accept: false);
      factory.behaviors['172.17.0.1'] = FakeServerBehavior(accept: false);

      final controller = VoicingConnectionController(
        tuning: fastTuning(),
        networkSnapshotProvider: provider,
        channelFactory: factory.call,
      );
      addTearDown(() async {
        controller.dispose();
        await provider.dispose();
      });

      await controller.initialize();
      await settleUntil(() => controller.status == ConnectionStatus.connected);

      expect(controller.serverIp, '192.168.1.50');
      // 竞速第一个启动的候选必须是评分最高的地址，而不是 172.17 docker 网段。
      expect(factory.channels.first.uri.host, '192.168.1.50');

      final book = controller.savedServer!.addressBook;
      expect(book.addressFor('192.168.1.50')!.successCount, greaterThan(2));
      expect(
        book.addressFor('192.168.1.50')!.networkKey,
        'wifi:192.168.1.0/24',
      );
      // 失败候选：成功计数保持 0，失败计数 +1。
      expect(book.addressFor('192.168.9.9')!.successCount, 1);
      expect(book.addressFor('192.168.9.9')!.failureCount, greaterThan(0));
      expect(book.addressFor('172.17.0.1')!.successCount, 0);
      expect(book.addressFor('172.17.0.1')!.failureCount, greaterThan(0));
    },
  );

  test(
    'QR pairing requires connected + qr_scan ping/pong and probes candidates in parallel',
    () async {
      final provider = FakeNetworkSnapshotProvider(NetworkSnapshot.empty);
      final factory = FakeChannelFactory();
      // 候选 0：能连上但永不回 pong → 不能算成功；
      // 候选 1：connected + ping(qr_scan) + pong → 才是 winner。
      factory.behaviors['192.168.1.50'] = FakeServerBehavior(
        accept: true,
        respondToPing: false,
      );
      factory.behaviors['10.0.0.5'] = FakeServerBehavior(
        accept: true,
        respondToPing: true,
      );

      final controller = VoicingConnectionController(
        tuning: fastTuning(),
        networkSnapshotProvider: provider,
        channelFactory: factory.call,
      );
      addTearDown(() async {
        controller.dispose();
        await provider.dispose();
      });

      await controller.initialize();
      controller.enterQrScanMode();
      controller.handleQrDetected(
        jsonEncode({
          'v': 1,
          'type': 'voicing',
          'device_id': 'pc-1',
          'ip': '192.168.1.50',
          'ips': ['192.168.1.50', '10.0.0.5'],
          'port': 9527,
          'name': 'FakePC',
          'os': 'linux',
        }),
        const [],
      );
      await settleUntil(() => controller.status == ConnectionStatus.connected);

      expect(controller.savedServer, isNotNull);
      expect(controller.savedServer!.ip, '10.0.0.5');
      expect(controller.qrScanMode, isFalse);
      // 两个候选都启动过 → 并行竞速生效。
      final probedHosts = factory.channels.map((channel) => channel.uri.host).toSet();
      expect(probedHosts.contains('192.168.1.50'), isTrue);
      expect(probedHosts.contains('10.0.0.5'), isTrue);
      expect(
        controller.savedServer!.addressBook
            .addressFor('10.0.0.5')!
            .successCount,
        greaterThanOrEqualTo(1),
      );
    },
  );

  test('QR generation change invalidates stale race callbacks', () async {
    final provider = FakeNetworkSnapshotProvider(NetworkSnapshot.empty);
    final factory = FakeChannelFactory();
    // 两个候选都能连上但永不回 pong → 竞速会挂到 attempt timeout。
    factory.behaviors['192.168.1.50'] = FakeServerBehavior(accept: true);
    factory.behaviors['10.0.0.5'] = FakeServerBehavior(accept: true);

    final controller = VoicingConnectionController(
      tuning: fastTuning(),
      networkSnapshotProvider: provider,
      channelFactory: factory.call,
    );
    addTearDown(() async {
      controller.dispose();
      await provider.dispose();
    });

    await controller.initialize();
    controller.enterQrScanMode();
    controller.handleQrDetected(
      jsonEncode({
        'v': 1,
        'type': 'voicing',
        'device_id': 'pc-1',
        'ip': '192.168.1.50',
        'ips': ['192.168.1.50', '10.0.0.5'],
        'port': 9527,
        'name': 'FakePC',
        'os': 'linux',
      }),
      const [],
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    controller.exitQrScanMode();
    // 等超过 attempt timeout，确保旧竞速的收尾回调即使执行也不会保存。
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(controller.hasStoredServer, isFalse);
    expect(controller.qrPairingSucceeded, isFalse);
    expect(controller.status, ConnectionStatus.disconnected);
  });

  test(
    'network change during disconnected/connecting re-ranks and reconnects immediately',
    () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final savedServer = SavedServer(
        deviceId: 'pc-1',
        ip: '192.168.9.9',
        ips: const ['192.168.9.9', '192.168.1.50'],
        port: 9527,
        name: 'FakePC',
        os: 'linux',
        lastConnectedTs: nowMs - 1000,
        addresses: ServerAddressBook([
          SavedAddress(
            ip: '192.168.9.9',
            networkKey: 'wifi:192.168.9.0/24',
            networkKind: 'wifi',
            lastSuccessTs: nowMs - 1000,
            lastSeenTs: nowMs - 1000,
            successCount: 1,
          ),
          SavedAddress(
            ip: '192.168.1.50',
            networkKey: 'wifi:192.168.1.0/24',
            networkKind: 'wifi',
            lastSuccessTs: nowMs - 2000,
            lastSeenTs: nowMs - 2000,
            successCount: 1,
          ),
        ]),
      );
      await seedSavedServer(savedServer);

      // 初始网络 C：两个地址都不可达 → 竞速全失败进入 3s backoff。
      final provider = FakeNetworkSnapshotProvider(
        wifiSnapshot(ip: '172.20.0.5'),
      );
      final factory = FakeChannelFactory();
      factory.behaviors['192.168.9.9'] = FakeServerBehavior(accept: false);
      factory.behaviors['192.168.1.50'] = FakeServerBehavior(accept: false);

      final controller = VoicingConnectionController(
        tuning: fastTuning(),
        networkSnapshotProvider: provider,
        channelFactory: factory.call,
      );
      addTearDown(() async {
        controller.dispose();
        await provider.dispose();
      });

      await controller.initialize();
      await settleUntil(
        () => controller.status == ConnectionStatus.disconnected,
      );
      final connectionsBeforeSwitch = factory.channels.length;

      // 切到网络 B：不等待 3s backoff，应立即用新快照重排并连上 B 地址。
      factory.behaviors['192.168.1.50']!.accept = true;
      provider.emit(wifiSnapshot(ip: '192.168.1.5'));
      await settleUntil(() => controller.status == ConnectionStatus.connected);

      expect(controller.serverIp, '192.168.1.50');
      expect(controller.currentNetworkKey, 'wifi:192.168.1.0/24');
      expect(
        factory.channels[connectionsBeforeSwitch].uri.host,
        '192.168.1.50',
      );

      // 已连接时网络再变化：不打断当前连接、不重开 socket。
      final connectionsAfterConnected = factory.channels.length;
      provider.emit(NetworkSnapshot.empty);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(controller.status, ConnectionStatus.connected);
      expect(controller.serverIp, '192.168.1.50');
      expect(factory.channels.length, connectionsAfterConnected);
    },
  );

  test(
    'multiple paired devices connect concurrently and text goes to active device',
    () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final pcA = SavedServer(
        deviceId: 'pc-a',
        ip: '192.168.1.50',
        ips: const ['192.168.1.50'],
        port: 9527,
        name: 'Office-PC',
        os: 'windows',
        lastConnectedTs: nowMs - 2000,
      );
      final pcB = SavedServer(
        deviceId: 'pc-b',
        ip: '192.168.1.60',
        ips: const ['192.168.1.60'],
        port: 9527,
        name: 'Home-Laptop',
        os: 'linux',
        lastConnectedTs: nowMs - 1000,
      );
      // 2026-11-22：v3 多设备列表 + 活跃设备 = pc-b。
      await seedPairedDevices([pcA, pcB], activeDeviceKey: 'pc-b');

      final provider = FakeNetworkSnapshotProvider(
        wifiSnapshot(ip: '192.168.1.5'),
      );
      final factory = FakeChannelFactory();
      factory.behaviors['192.168.1.50'] = FakeServerBehavior(accept: true);
      factory.behaviors['192.168.1.60'] = FakeServerBehavior(accept: true);

      final controller = VoicingConnectionController(
        tuning: fastTuning(),
        networkSnapshotProvider: provider,
        channelFactory: factory.call,
      );
      addTearDown(() async {
        controller.dispose();
        await provider.dispose();
      });

      await controller.initialize();
      await settleUntil(
        () => controller.pairedDevices.length == 2 &&
            controller.pairedDevices.every((device) => device.connected),
      );

      expect(
        controller.pairedDevices.map((device) => device.deviceKey),
        ['pc-a', 'pc-b'],
      );
      expect(controller.activeDeviceKey, 'pc-b');
      expect(controller.status, ConnectionStatus.connected);
      expect(controller.activeDeviceName, 'Home-Laptop');

      controller.textController.text = 'hello pc-b';
      await controller.sendText();
      final pcBChannel = factory.channels
          .where((channel) => channel.uri.host == '192.168.1.60')
          .last;
      expect(
        pcBChannel.sentMessages.any(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['content'] ==
              'hello pc-b',
        ),
        isTrue,
      );

      // 切换发送目标后只发新目标，且两台设备的连接都保持（不重开 socket）。
      controller.selectDevice('pc-a');
      expect(controller.activeDeviceKey, 'pc-a');
      final connectionsBeforeSwitch = factory.channels.length;
      controller.textController.text = 'hello pc-a';
      await controller.sendText();
      final pcAChannel = factory.channels
          .where((channel) => channel.uri.host == '192.168.1.50')
          .last;
      expect(
        pcAChannel.sentMessages.any(
          (message) =>
              (jsonDecode(message) as Map<String, dynamic>)['content'] ==
              'hello pc-a',
        ),
        isTrue,
      );
      expect(factory.channels.length, connectionsBeforeSwitch);
      expect(
        controller.pairedDevices.every((device) => device.connected),
        isTrue,
      );
    },
  );

  test(
    'ACK from a non-active device never clears the active input box',
    () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final pcA = SavedServer(
        deviceId: 'pc-a',
        ip: '192.168.1.50',
        ips: const ['192.168.1.50'],
        port: 9527,
        name: 'Office-PC',
        os: 'windows',
        lastConnectedTs: nowMs - 2000,
      );
      final pcB = SavedServer(
        deviceId: 'pc-b',
        ip: '192.168.1.60',
        ips: const ['192.168.1.60'],
        port: 9527,
        name: 'Home-Laptop',
        os: 'linux',
        lastConnectedTs: nowMs - 1000,
      );
      await seedPairedDevices([pcA, pcB], activeDeviceKey: 'pc-b');

      final provider = FakeNetworkSnapshotProvider(
        wifiSnapshot(ip: '192.168.1.5'),
      );
      final factory = FakeChannelFactory();
      factory.behaviors['192.168.1.50'] = FakeServerBehavior(accept: true);
      factory.behaviors['192.168.1.60'] = FakeServerBehavior(accept: true);

      final controller = VoicingConnectionController(
        tuning: fastTuning(),
        networkSnapshotProvider: provider,
        channelFactory: factory.call,
      );
      addTearDown(() async {
        controller.dispose();
        await provider.dispose();
      });

      await controller.initialize();
      await settleUntil(
        () => controller.pairedDevices.length == 2 &&
            controller.pairedDevices.every((device) => device.connected),
      );

      final pcAChannel = factory.channels
          .where((channel) => channel.uri.host == '192.168.1.50')
          .last;
      final pcBChannel = factory.channels
          .where((channel) => channel.uri.host == '192.168.1.60')
          .last;

      controller.textController.text = 'draft for active device';
      // 非活跃设备的迟到 ACK 不应清空当前输入。
      pcAChannel.emitAck();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.textController.text, 'draft for active device');

      // 活跃设备的 ACK 才清空输入（与原单设备语义一致）。
      pcBChannel.emitAck();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(controller.textController.text, isEmpty);
    },
  );

  test('legacy manual device upgrades its key to the connected device_id', () async {
    // 旧版手动 IP 记录没有 device_id；连上后必须把列表 Key 原地升级为
    // PC 的真实 device_id，否则设备选择菜单会出现一条永远对不上身份的旧记录。
    const legacy = SavedServer(
      deviceId: '',
      ip: '192.168.1.50',
      port: 9527,
      name: '',
      os: '',
      lastConnectedTs: 1713883200000,
    );
    await seedSavedServer(legacy);

    final provider = FakeNetworkSnapshotProvider(
      wifiSnapshot(ip: '192.168.1.5'),
    );
    final factory = FakeChannelFactory();
    factory.behaviors['192.168.1.50'] = FakeServerBehavior(accept: true);

    final controller = VoicingConnectionController(
      tuning: fastTuning(),
      networkSnapshotProvider: provider,
      channelFactory: factory.call,
    );
    addTearDown(() async {
      controller.dispose();
      await provider.dispose();
    });

    await controller.initialize();
    await settleUntil(() => controller.status == ConnectionStatus.connected);

    expect(controller.pairedDevices, hasLength(1));
    expect(controller.pairedDevices.single.deviceKey, 'pc-1');
    expect(controller.activeDeviceKey, 'pc-1');
    expect(controller.savedServer!.deviceId, 'pc-1');
    expect(controller.activeDeviceName, 'FakePC');
  });

  test(
    'manual address update keeps the existing device identity and single entry',
    () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final pcA = SavedServer(
        deviceId: 'pc-a',
        ip: '192.168.1.50',
        ips: const ['192.168.1.50'],
        port: 9527,
        name: 'Office-PC',
        os: 'windows',
        lastConnectedTs: nowMs - 1000,
      );
      await seedPairedDevices([pcA], activeDeviceKey: 'pc-a');

      final provider = FakeNetworkSnapshotProvider(
        wifiSnapshot(ip: '192.168.1.5'),
      );
      final factory = FakeChannelFactory();
      factory.behaviors['192.168.1.50'] = FakeServerBehavior(accept: true);

      final controller = VoicingConnectionController(
        tuning: fastTuning(),
        networkSnapshotProvider: provider,
        channelFactory: factory.call,
      );
      addTearDown(() async {
        controller.dispose();
        await provider.dispose();
      });

      await controller.initialize();
      await settleUntil(() => controller.status == ConnectionStatus.connected);

      // 手动输入一台已经 QR 配对过的 PC 的地址：应更新原记录而不是新增一条。
      await controller.setManualServer(ip: '192.168.1.50', port: 9527);
      await settleUntil(() => controller.status == ConnectionStatus.connected);

      expect(controller.pairedDevices, hasLength(1));
      expect(controller.activeDeviceKey, 'pc-a');
      expect(controller.savedServer!.deviceId, 'pc-a');
      expect(controller.savedServer!.displayName, 'Office-PC');
    },
  );

  test(
    'removing the active device falls back to another connected device',
    () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final pcA = SavedServer(
        deviceId: 'pc-a',
        ip: '192.168.1.50',
        ips: const ['192.168.1.50'],
        port: 9527,
        name: 'Office-PC',
        os: 'windows',
        lastConnectedTs: nowMs - 2000,
      );
      final pcB = SavedServer(
        deviceId: 'pc-b',
        ip: '192.168.1.60',
        ips: const ['192.168.1.60'],
        port: 9527,
        name: 'Home-Laptop',
        os: 'linux',
        lastConnectedTs: nowMs - 1000,
      );
      await seedPairedDevices([pcA, pcB], activeDeviceKey: 'pc-b');

      final provider = FakeNetworkSnapshotProvider(
        wifiSnapshot(ip: '192.168.1.5'),
      );
      final factory = FakeChannelFactory();
      factory.behaviors['192.168.1.50'] = FakeServerBehavior(accept: true);
      factory.behaviors['192.168.1.60'] = FakeServerBehavior(accept: true);

      final controller = VoicingConnectionController(
        tuning: fastTuning(),
        networkSnapshotProvider: provider,
        channelFactory: factory.call,
      );
      addTearDown(() async {
        controller.dispose();
        await provider.dispose();
      });

      await controller.initialize();
      await settleUntil(
        () => controller.pairedDevices.length == 2 &&
            controller.pairedDevices.every((device) => device.connected),
      );

      controller.removeDevice('pc-b');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(
        controller.pairedDevices.map((device) => device.deviceKey),
        ['pc-a'],
      );
      expect(controller.activeDeviceKey, 'pc-a');
      expect(controller.status, ConnectionStatus.connected);

      // 持久化列表也必须同步删除，不能下次启动又复活设备。
      final prefs = await SharedPreferences.getInstance();
      final decoded = jsonDecode(
        prefs.getString(SavedServerStore.savedServersKey)!,
      ) as Map<String, dynamic>;
      final stored = decoded['servers'] as List<dynamic>;
      expect(stored, hasLength(1));
      expect((stored.single as Map<String, dynamic>)['device_id'], 'pc-a');
    },
  );

  test(
    'dispose during the QR reveal window causes no post-dispose notifications',
    () async {
      final provider = FakeNetworkSnapshotProvider(NetworkSnapshot.empty);
      final factory = FakeChannelFactory();
      factory.behaviors['192.168.1.50'] = FakeServerBehavior(
        accept: true,
        respondToPing: true,
      );

      final controller = VoicingConnectionController(
        tuning: const ConnectionTuning(
          raceStagger: Duration(milliseconds: 5),
          raceWidth: 3,
          savedRaceCandidateCount: 3,
          knownNetworkAttemptTimeout: Duration(milliseconds: 150),
          unknownNetworkAttemptTimeout: Duration(milliseconds: 150),
          raceBudget: Duration(milliseconds: 400),
          qrResultRevealDelay: Duration(milliseconds: 200),
          qrSuccessHoldDelay: Duration(milliseconds: 1),
          qrFailureHoldDelay: Duration(milliseconds: 1),
        ),
        networkSnapshotProvider: provider,
        channelFactory: factory.call,
      );
      addTearDown(() async {
        controller.dispose();
        await provider.dispose();
      });

      await controller.initialize();
      controller.enterQrScanMode();
      controller.handleQrDetected(
        jsonEncode({
          'v': 1,
          'type': 'voicing',
          'device_id': 'pc-a',
          'ip': '192.168.1.50',
          'ips': ['192.168.1.50'],
          'port': 9527,
          'name': 'Office-PC',
          'os': 'windows',
        }),
        const [],
      );
      // 让 QR 竞速胜出并进入 reveal 延时窗口。
      await Future<void>.delayed(const Duration(milliseconds: 60));
      controller.dispose();
      // 跨过 reveal/hold 窗口：旧回调必须被 generation 失效，不 notify 已销毁对象。
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(controller.qrScanMode, isFalse);
      // 旧回调若在 dispose 后继续跑，会把扫码设备写回 links；这里断言没有。
      expect(controller.pairedDevices, isEmpty);
    },
  );

  test(
    'QR pairing appends a new device and keeps the previous connection alive',
    () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final pcA = SavedServer(
        deviceId: 'pc-a',
        ip: '192.168.1.50',
        ips: const ['192.168.1.50'],
        port: 9527,
        name: 'Office-PC',
        os: 'windows',
        lastConnectedTs: nowMs - 1000,
      );
      await seedPairedDevices([pcA], activeDeviceKey: 'pc-a');

      final provider = FakeNetworkSnapshotProvider(
        wifiSnapshot(ip: '192.168.1.5'),
      );
      final factory = FakeChannelFactory();
      factory.behaviors['192.168.1.50'] = FakeServerBehavior(accept: true);
      factory.behaviors['192.168.1.60'] = FakeServerBehavior(
        accept: true,
        respondToPing: true,
      );

      final controller = VoicingConnectionController(
        tuning: fastTuning(),
        networkSnapshotProvider: provider,
        channelFactory: factory.call,
      );
      addTearDown(() async {
        controller.dispose();
        await provider.dispose();
      });

      await controller.initialize();
      await settleUntil(() => controller.status == ConnectionStatus.connected);
      final pcAChannel = factory.channels
          .where((channel) => channel.uri.host == '192.168.1.50')
          .last;

      controller.enterQrScanMode();
      controller.handleQrDetected(
        jsonEncode({
          'v': 1,
          'type': 'voicing',
          'device_id': 'pc-b',
          'ip': '192.168.1.60',
          'ips': ['192.168.1.60'],
          'port': 9527,
          'name': 'Home-Laptop',
          'os': 'linux',
        }),
        const [],
      );
      await settleUntil(
        () => controller.pairedDevices.length == 2 &&
            controller.activeDeviceKey == 'pc-b' &&
            controller.status == ConnectionStatus.connected,
      );

      expect(controller.qrScanMode, isFalse);
      expect(
        controller.pairedDevices
            .firstWhere((device) => device.deviceKey == 'pc-a')
            .connected,
        isTrue,
      );
      // 旧设备没有被新的扫码覆盖/断开。
      expect(pcAChannel.closed, isFalse);
      expect(controller.activeDeviceName, 'Home-Laptop');
    },
  );

  test(
    'QR rescan of the same device merges candidates without duplicate entry',
    () async {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final pcA = SavedServer(
        deviceId: 'pc-a',
        ip: '192.168.1.50',
        ips: const ['192.168.1.50'],
        port: 9527,
        name: 'Office-PC',
        os: 'windows',
        lastConnectedTs: nowMs - 1000,
      );
      await seedPairedDevices([pcA], activeDeviceKey: 'pc-a');

      final provider = FakeNetworkSnapshotProvider(
        wifiSnapshot(ip: '192.168.1.5'),
      );
      final factory = FakeChannelFactory();
      factory.behaviors['192.168.1.50'] = FakeServerBehavior(accept: true);
      factory.behaviors['192.168.1.51'] = FakeServerBehavior(
        accept: true,
        respondToPing: true,
      );

      final controller = VoicingConnectionController(
        tuning: fastTuning(),
        networkSnapshotProvider: provider,
        channelFactory: factory.call,
      );
      addTearDown(() async {
        controller.dispose();
        await provider.dispose();
      });

      await controller.initialize();
      await settleUntil(() => controller.status == ConnectionStatus.connected);

      controller.enterQrScanMode();
      controller.handleQrDetected(
        jsonEncode({
          'v': 1,
          'type': 'voicing',
          'device_id': 'pc-a',
          'ip': '192.168.1.51',
          'ips': ['192.168.1.51', '192.168.1.50'],
          'port': 9527,
          'name': 'Office-PC',
          'os': 'windows',
        }),
        const [],
      );
      await settleUntil(
        () => controller.status == ConnectionStatus.connected &&
            controller.savedServer?.ip == '192.168.1.51',
      );

      expect(controller.pairedDevices, hasLength(1));
      expect(controller.activeDeviceKey, 'pc-a');
      expect(
        controller.savedServer!.candidateIps,
        containsAll(<String>['192.168.1.51', '192.168.1.50']),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// fake 与辅助
// ---------------------------------------------------------------------------

NetworkSnapshot wifiSnapshot({required String ip}) {
  return NetworkSnapshot(
    interfaces: [
      NetworkInterfaceInfo(
        name: 'wlan0',
        ip: ip,
        prefixLength: 24,
        kind: NetworkInterfaceKind.wifi,
      ),
    ],
  );
}

/// 把所有等待压缩到毫秒级，保证整份测试远低于 5 秒。
ConnectionTuning fastTuning() {
  return const ConnectionTuning(
    raceStagger: Duration(milliseconds: 5),
    raceWidth: 3,
    savedRaceCandidateCount: 3,
    knownNetworkAttemptTimeout: Duration(milliseconds: 150),
    unknownNetworkAttemptTimeout: Duration(milliseconds: 150),
    raceBudget: Duration(milliseconds: 400),
    qrResultRevealDelay: Duration(milliseconds: 1),
    qrSuccessHoldDelay: Duration(milliseconds: 1),
    qrFailureHoldDelay: Duration(milliseconds: 1),
  );
}

Future<void> seedSavedServer(SavedServer server) async {
  SharedPreferences.setMockInitialValues({
    SavedServerStore.savedServerKey: jsonEncode(server.toJson()),
  });
}

Future<void> seedPairedDevices(
  List<SavedServer> servers, {
  required String activeDeviceKey,
}) async {
  SharedPreferences.setMockInitialValues({
    SavedServerStore.savedServersKey: jsonEncode({
      'schema_version': SavedServerStore.savedServersSchemaVersion,
      'servers': servers.map((server) => server.toJson()).toList(),
    }),
    SavedServerStore.activeDeviceKey: activeDeviceKey,
  });
}

Future<void> settleUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met before $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  // 再让持久化/notify 的微任务收尾，避免断言读到中间态。
  await Future<void>.delayed(const Duration(milliseconds: 5));
}

class FakeNetworkSnapshotProvider implements NetworkSnapshotProvider {
  FakeNetworkSnapshotProvider(this._current);

  NetworkSnapshot _current;
  final StreamController<NetworkSnapshot> _changes =
      StreamController<NetworkSnapshot>.broadcast();

  @override
  Future<NetworkSnapshot> snapshot() async => _current;

  @override
  Stream<NetworkSnapshot> get changes => _changes.stream;

  void emit(NetworkSnapshot snapshot) {
    _current = snapshot;
    _changes.add(snapshot);
  }

  @override
  Future<void> dispose() async {
    if (!_changes.isClosed) {
      await _changes.close();
    }
  }
}

class FakeServerBehavior {
  FakeServerBehavior({
    this.accept = false,
    this.connectedDelay = Duration.zero,
    this.respondToPing = false,
  });

  bool accept;
  final Duration connectedDelay;

  /// 收到 ping 后是否回 pong（QR 扫码探测需要；正式心跳在测试窗口内不会触发）。
  final bool respondToPing;
}

class FakeChannelFactory {
  final Map<String, FakeServerBehavior> behaviors =
      <String, FakeServerBehavior>{};
  final List<FakeVoicingWebSocketChannel> channels = <FakeVoicingWebSocketChannel>[];

  VoicingWebSocketChannel call(
    Uri uri, {
    Duration? connectTimeout,
    bool preferNativeWifi = true,
  }) {
    final behavior = behaviors[uri.host] ?? FakeServerBehavior();
    final channel = FakeVoicingWebSocketChannel(uri, behavior);
    channels.add(channel);
    return channel;
  }
}

class FakeVoicingWebSocketChannel implements VoicingWebSocketChannel {
  FakeVoicingWebSocketChannel(this.uri, this._behavior) {
    _controller = StreamController<dynamic>(onListen: _handleListen);
    _sink = FakeVoicingWebSocketSink(this);
  }

  final Uri uri;
  final FakeServerBehavior _behavior;
  late final StreamController<dynamic> _controller;
  late final FakeVoicingWebSocketSink _sink;
  bool closed = false;

  /// 记录本通道收到的客户端消息，多设备路由断言用。
  final List<String> sentMessages = <String>[];

  @override
  Stream<dynamic> get stream => _controller.stream;

  @override
  VoicingWebSocketSink get sink => _sink;

  void _handleListen() {
    scheduleMicrotask(() {
      if (_controller.isClosed) {
        return;
      }
      if (!_behavior.accept) {
        _controller.addError(StateError('fake connection refused'));
        return;
      }
      void emitConnected() {
        _emit(jsonEncode(_connectedMessage()));
      }

      if (_behavior.connectedDelay == Duration.zero) {
        emitConnected();
      } else {
        Timer(_behavior.connectedDelay, emitConnected);
      }
    });
  }

  void _emit(String message) {
    if (!_controller.isClosed) {
      _controller.add(message);
    }
  }

  /// 主动向客户端发送一条 ACK（模拟 PC 端注入完成），用于多设备路由断言。
  void emitAck({bool clearInput = true}) {
    _emit(
      jsonEncode({
        'type': 'ack',
        'clear_input': clearInput,
      }),
    );
  }

  void handleSent(String message) {
    sentMessages.add(message);
    final decoded = jsonDecode(message);
    if (decoded is Map && decoded['type'] == 'ping' && _behavior.respondToPing) {
      _emit(jsonEncode({'type': 'pong', 'sync_enabled': true}));
    }
  }

  Future<void> closeChannel() async {
    closed = true;
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }

  Map<String, dynamic> _connectedMessage() {
    return {
      'type': 'connected',
      'message': 'ok',
      'sync_enabled': true,
      'computer_name': 'FakePC',
      'device_id': 'pc-1',
      'name': 'FakePC',
      'os': 'linux',
    };
  }
}

class FakeVoicingWebSocketSink implements VoicingWebSocketSink {
  FakeVoicingWebSocketSink(this._channel);

  final FakeVoicingWebSocketChannel _channel;

  @override
  Future<void> add(Object? data) async {
    if (data is String) {
      _channel.handleSent(data);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await _channel.closeChannel();
  }
}
