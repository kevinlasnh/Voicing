import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

abstract class VoicingWebSocketSink {
  Future<void> add(Object? data);

  Future<void> close([int? closeCode, String? closeReason]);
}

abstract class VoicingWebSocketChannel {
  Stream<dynamic> get stream;

  VoicingWebSocketSink get sink;
}

class VoicingWebSocketConnector {
  static VoicingWebSocketChannel connect(
    Uri uri, {
    Duration? connectTimeout,
    bool preferNativeWifi = true,
  }) {
    if (preferNativeWifi && Platform.isAndroid) {
      return NativeWifiWebSocketChannel.connect(
        uri,
        connectTimeout: connectTimeout,
      );
    }

    return DartIoWebSocketChannel.connect(
      uri,
      connectTimeout: connectTimeout,
    );
  }
}

class DartIoWebSocketChannel implements VoicingWebSocketChannel {
  DartIoWebSocketChannel._(this._delegate)
      : sink = _DartIoWebSocketSink(_delegate.sink);

  factory DartIoWebSocketChannel.connect(
    Uri uri, {
    Duration? connectTimeout,
  }) {
    return DartIoWebSocketChannel._(
      IOWebSocketChannel.connect(uri, connectTimeout: connectTimeout),
    );
  }

  final WebSocketChannel _delegate;

  @override
  Stream<dynamic> get stream => _delegate.stream;

  @override
  final VoicingWebSocketSink sink;
}

class _DartIoWebSocketSink implements VoicingWebSocketSink {
  const _DartIoWebSocketSink(this._delegate);

  final WebSocketSink _delegate;

  @override
  Future<void> add(Object? data) async {
    _delegate.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await _delegate.close(closeCode, closeReason);
  }
}

class NativeWifiWebSocketChannel implements VoicingWebSocketChannel {
  static const MethodChannel _methodChannel = MethodChannel('voicing/network');
  static const EventChannel _eventChannel =
      EventChannel('voicing/network_events');

  static int _nextConnectionId = 1;
  static final Map<int, StreamController<dynamic>> _controllers =
      <int, StreamController<dynamic>>{};
  static final Map<int, List<Map<dynamic, dynamic>>> _pendingEvents =
      <int, List<Map<dynamic, dynamic>>>{};
  static StreamSubscription<dynamic>? _eventSubscription;

  NativeWifiWebSocketChannel._(
    Future<int> idFuture,
    this._streamController,
  ) : sink = _NativeWifiWebSocketSink(idFuture);

  factory NativeWifiWebSocketChannel.connect(
    Uri uri, {
    Duration? connectTimeout,
  }) {
    _ensureEventSubscription();
    final streamController = StreamController<dynamic>();
    final requestedId = _nextConnectionId++;
    _controllers[requestedId] = streamController;
    final idFuture = _methodChannel.invokeMethod<int>(
      'connectWifiWebSocket',
      <String, Object?>{
        'id': requestedId,
        'url': uri.toString(),
        'timeoutMs': connectTimeout?.inMilliseconds ?? 8000,
      },
    ).then((nativeId) {
      if (nativeId == null) {
        throw StateError('native websocket connection id is null');
      }
      if (nativeId != requestedId &&
          identical(_controllers[requestedId], streamController)) {
        _controllers.remove(requestedId);
        _controllers[nativeId] = streamController;
      }
      _replayPendingEvents(nativeId);
      return nativeId;
    }).catchError((Object error, StackTrace stackTrace) {
      if (identical(_controllers[requestedId], streamController)) {
        _controllers.remove(requestedId);
        streamController.addError(error, stackTrace);
        unawaited(streamController.close());
      }
      throw error;
    });

    return NativeWifiWebSocketChannel._(idFuture, streamController);
  }

  final StreamController<dynamic> _streamController;

  @override
  Stream<dynamic> get stream => _streamController.stream;

  @override
  final VoicingWebSocketSink sink;

  static void _ensureEventSubscription() {
    _eventSubscription ??= _eventChannel.receiveBroadcastStream().listen(
      _handleNativeEvent,
      onError: (Object error, StackTrace stackTrace) {
        for (final controller in _controllers.values) {
          controller.addError(error, stackTrace);
        }
      },
    );
  }

  static void _handleNativeEvent(dynamic event) {
    if (event is! Map) {
      return;
    }
    final id = event['id'];
    if (id is! int) {
      return;
    }

    final controller = _controllers[id];
    if (controller == null) {
      _pendingEvents
          .putIfAbsent(id, () => <Map<dynamic, dynamic>>[])
          .add(event);
      return;
    }

    _dispatchNativeEvent(controller, id, event);
  }

  static void _replayPendingEvents(int id) {
    final controller = _controllers[id];
    if (controller == null) {
      return;
    }
    final events = _pendingEvents.remove(id);
    if (events == null) {
      return;
    }
    for (final event in events) {
      _dispatchNativeEvent(controller, id, event);
    }
  }

  static void _dispatchNativeEvent(
    StreamController<dynamic> controller,
    int id,
    Map<dynamic, dynamic> event,
  ) {
    final type = event['event'];
    if (type == 'message') {
      controller.add(event['data']);
    } else if (type == 'failure') {
      controller.addError(
        PlatformException(
          code: 'native_websocket_failure',
          message: event['message']?.toString(),
        ),
      );
      _controllers.remove(id);
      unawaited(controller.close());
    } else if (type == 'closed') {
      _controllers.remove(id);
      unawaited(controller.close());
    }
  }
}

class _NativeWifiWebSocketSink implements VoicingWebSocketSink {
  const _NativeWifiWebSocketSink(this._idFuture);

  static const MethodChannel _methodChannel = MethodChannel('voicing/network');

  final Future<int> _idFuture;

  @override
  Future<void> add(Object? data) async {
    final id = await _idFuture;
    final sent = await _methodChannel.invokeMethod<bool>(
      'sendWebSocketMessage',
      <String, Object?>{
        'id': id,
        'message': data?.toString() ?? '',
      },
    );
    if (sent != true) {
      throw PlatformException(
        code: 'native_websocket_send_failed',
        message: 'Native WebSocket refused the message',
      );
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    try {
      final id = await _idFuture;
      await _methodChannel.invokeMethod<void>(
        'closeWebSocket',
        <String, Object?>{
          'id': id,
          'code': closeCode ?? 1000,
          'reason': closeReason ?? '',
        },
      );
    } catch (_) {
      // close() is used as best-effort cleanup when reconnecting or disposing.
      // If the native connection failed before producing an id, there is
      // nothing left to close and callers should not see an unhandled Future.
    }
  }
}
