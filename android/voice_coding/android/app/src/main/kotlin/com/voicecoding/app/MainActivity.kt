package com.voicecoding.app

import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private var eventSink: EventChannel.EventSink? = null
    private lateinit var bluetoothManager: ClassicBluetoothManager

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        bluetoothManager = ClassicBluetoothManager(this) { event ->
            eventSink?.success(event)
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "voicing/bluetooth/methods",
        ).setMethodCallHandler { call, result ->
            handleBluetoothMethodCall(call, result)
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "voicing/bluetooth/events",
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            },
        )
    }

    private fun handleBluetoothMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isSupported" -> result.success(bluetoothManager.isSupported())
            "requestConnectPermission" -> bluetoothManager.requestConnectPermission { granted ->
                result.success(granted)
            }
            "requestEnableBluetooth" -> bluetoothManager.requestEnableBluetooth { enabled ->
                result.success(enabled)
            }
            "openSystemBluetoothSettings" -> {
                bluetoothManager.openSystemBluetoothSettings()
                result.success(null)
            }
            "getBondedDevices" -> result.success(bluetoothManager.getBondedDevices())
            "connect" -> {
                val address = call.argument<String>("address")
                val serviceUuid = call.argument<String>("serviceUuid")
                if (address.isNullOrBlank() || serviceUuid.isNullOrBlank()) {
                    result.error("invalid_args", "address/serviceUuid required", null)
                    return
                }
                try {
                    bluetoothManager.connect(address, serviceUuid)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("connect_failed", error.message, null)
                }
            }
            "disconnect" -> {
                bluetoothManager.disconnect()
                result.success(null)
            }
            "send" -> {
                val payload = call.argument<String>("payload")
                if (payload == null) {
                    result.error("invalid_args", "payload required", null)
                    return
                }
                try {
                    bluetoothManager.send(payload)
                    result.success(null)
                } catch (error: Exception) {
                    result.error("send_failed", error.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}
