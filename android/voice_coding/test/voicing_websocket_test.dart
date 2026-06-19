import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicing/voicing_websocket.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('voicing/network');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('native wifi sink close ignores id resolution failures', () async {
    final calls = <MethodCall>[];

    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'connectWifiWebSocket') {
        throw PlatformException(
          code: 'connect_failed',
          message: 'cannot connect',
        );
      }
      return null;
    });

    final sink = NativeWifiWebSocketChannel.connect(
      Uri.parse('ws://192.168.1.2:9527'),
    ).sink;

    await sink.close();

    expect(calls.map((call) => call.method), ['connectWifiWebSocket']);
  });

  test('native wifi sink close forwards native id when available', () async {
    final calls = <MethodCall>[];

    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'connectWifiWebSocket') {
        return 7;
      }
      return null;
    });

    final sink = NativeWifiWebSocketChannel.connect(
      Uri.parse('ws://192.168.1.2:9527'),
    ).sink;

    await sink.close(1001, 'switching');

    expect(calls.map((call) => call.method), [
      'connectWifiWebSocket',
      'closeWebSocket',
    ]);
    expect(calls.last.arguments, {
      'id': 7,
      'code': 1001,
      'reason': 'switching',
    });
  });
}
