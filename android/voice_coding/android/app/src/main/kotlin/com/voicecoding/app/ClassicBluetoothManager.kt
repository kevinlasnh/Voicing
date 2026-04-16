package com.voicecoding.app

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.util.UUID

class ClassicBluetoothManager(
    private val activity: FlutterFragmentActivity,
    private val emitEvent: (Map<String, Any?>) -> Unit,
) {
    private val mainHandler = Handler(Looper.getMainLooper())
    private val bluetoothAdapter: BluetoothAdapter? by lazy {
        val manager = activity.getSystemService(BluetoothManager::class.java)
        manager?.adapter
    }

    private var activeSocket: BluetoothSocket? = null
    private var activeAddress: String? = null
    private var pendingPermissionCallback: ((Boolean) -> Unit)? = null
    private var pendingEnableCallback: ((Boolean) -> Unit)? = null

    private val requestConnectPermissionLauncher =
        activity.registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
            pendingPermissionCallback?.invoke(granted)
            pendingPermissionCallback = null
        }

    private val requestEnableBluetoothLauncher =
        activity.registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
            pendingEnableCallback?.invoke(
                result.resultCode == Activity.RESULT_OK || isBluetoothEnabled(),
            )
            pendingEnableCallback = null
        }

    fun isSupported(): Boolean {
        return activity.packageManager.hasSystemFeature(PackageManager.FEATURE_BLUETOOTH)
    }

    fun requestConnectPermission(callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            callback(true)
            return
        }

        val granted = ContextCompat.checkSelfPermission(
            activity,
            Manifest.permission.BLUETOOTH_CONNECT,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            callback(true)
            return
        }

        pendingPermissionCallback = callback
        requestConnectPermissionLauncher.launch(Manifest.permission.BLUETOOTH_CONNECT)
    }

    fun requestEnableBluetooth(callback: (Boolean) -> Unit) {
        if (!isSupported()) {
            callback(false)
            return
        }

        if (isBluetoothEnabled()) {
            callback(true)
            return
        }

        val intent = Intent(BluetoothAdapter.ACTION_REQUEST_ENABLE)
        pendingEnableCallback = callback
        requestEnableBluetoothLauncher.launch(intent)
    }

    fun openSystemBluetoothSettings() {
        activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
    }

    fun getBondedDevices(): List<Map<String, Any?>> {
        val adapter = bluetoothAdapter ?: return emptyList()
        if (!hasConnectPermission()) {
            return emptyList()
        }

        return adapter.bondedDevices
            .sortedBy { device -> device.name ?: device.address }
            .map { device ->
                mapOf(
                    "name" to (device.name ?: "未命名设备"),
                    "address" to device.address,
                )
            }
    }

    fun connect(address: String, serviceUuid: String) {
        disconnect()

        val adapter = bluetoothAdapter ?: throw IllegalStateException("Bluetooth unsupported")
        if (!hasConnectPermission()) {
            throw SecurityException("BLUETOOTH_CONNECT permission is required")
        }

        val device = adapter.getRemoteDevice(address)
        val connectThread = Thread {
            val socket = device.createRfcommSocketToServiceRecord(UUID.fromString(serviceUuid))
            try {
                adapter.cancelDiscovery()
                socket.connect()
                activeSocket = socket
                activeAddress = address
                emitOnMain(
                    mapOf(
                        "type" to "connected",
                        "address" to address,
                        "name" to (device.name ?: "桌面端"),
                    ),
                )
                startReadLoop(socket, device)
            } catch (error: Exception) {
                try {
                    socket.close()
                } catch (_: IOException) {
                }
                emitOnMain(
                    mapOf(
                        "type" to "error",
                        "message" to (error.message ?: "Bluetooth connect failed"),
                    ),
                )
                emitDisconnected(address)
            }
        }
        connectThread.isDaemon = true
        connectThread.start()
    }

    fun disconnect() {
        val socket = activeSocket ?: return
        activeSocket = null
        activeAddress = null
        try {
            socket.close()
        } catch (_: IOException) {
        }
    }

    fun send(payload: String) {
        val socket = activeSocket ?: throw IllegalStateException("Bluetooth socket not connected")
        val bytes = payload.toByteArray(StandardCharsets.UTF_8)
        socket.outputStream.write(bytes)
        socket.outputStream.flush()
    }

    private fun startReadLoop(socket: BluetoothSocket, device: BluetoothDevice) {
        val readThread = Thread {
            val buffer = ByteArray(4096)
            try {
                while (true) {
                    val read = socket.inputStream.read(buffer)
                    if (read <= 0) {
                        break
                    }

                    emitOnMain(
                        mapOf(
                            "type" to "data",
                            "payload" to String(buffer, 0, read, StandardCharsets.UTF_8),
                        ),
                    )
                }
            } catch (error: IOException) {
                emitOnMain(
                    mapOf(
                        "type" to "error",
                        "message" to (error.message ?: "Bluetooth read failed"),
                    ),
                )
            } finally {
                if (activeSocket == socket) {
                    activeSocket = null
                    activeAddress = null
                }
                emitDisconnected(device.address)
                try {
                    socket.close()
                } catch (_: IOException) {
                }
            }
        }
        readThread.isDaemon = true
        readThread.start()
    }

    private fun emitDisconnected(address: String?) {
        emitOnMain(
            mapOf(
                "type" to "disconnected",
                "address" to address,
            ),
        )
    }

    private fun emitOnMain(event: Map<String, Any?>) {
        mainHandler.post {
            emitEvent(event)
        }
    }

    private fun hasConnectPermission(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
            ContextCompat.checkSelfPermission(
                activity,
                Manifest.permission.BLUETOOTH_CONNECT,
            ) == PackageManager.PERMISSION_GRANTED
    }

    private fun isBluetoothEnabled(): Boolean {
        return bluetoothAdapter?.isEnabled == true
    }
}
