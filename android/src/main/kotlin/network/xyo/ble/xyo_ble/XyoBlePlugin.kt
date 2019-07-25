package network.xyo.ble.xyo_ble

import android.content.Context
import android.util.Log
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import network.xyo.ble.devices.XY4BluetoothDevice
import network.xyo.ble.devices.XYBluetoothDevice
import network.xyo.ble.devices.XYIBeaconBluetoothDevice
import network.xyo.ble.gatt.server.XYBluetoothAdvertiser
import network.xyo.ble.gatt.server.XYBluetoothGattServer
import network.xyo.ble.scanner.XYSmartScan
import network.xyo.ble.scanner.XYSmartScanModern
import network.xyo.modbluetoothkotlin.advertiser.XyoBluetoothAdvertiser
import network.xyo.modbluetoothkotlin.client.XyoBluetoothClient
import network.xyo.modbluetoothkotlin.client.XyoSentinelX
import network.xyo.modbluetoothkotlin.server.XyoBluetoothServer
import network.xyo.sdkcorekotlin.boundWitness.XyoBoundWitness
import network.xyo.sdkcorekotlin.node.XyoNodeListener
import java.util.*
import kotlin.collections.ArrayList

@kotlin.ExperimentalUnsignedTypes
class XyoBlePlugin(context: Context, registrar: Registrar): MethodCallHandler, XYSmartScan.Listener() {

  val smartScan = XYSmartScanModern(context.applicationContext)
  val server = XYBluetoothGattServer(context.applicationContext)
  val serverHelper = XyoBluetoothServer(server)

  val advertiser = XYBluetoothAdvertiser(context.applicationContext)
  val advertiserHelper = XyoBluetoothAdvertiser(0, 0, advertiser)

  val scannerChannel = EventChannel(registrar.messenger(), "network.xyo/smartscan")
  val scannerStreamHandler = SmartScanEventHandler()

  val boundWitnessChannel = EventChannel(registrar.messenger(), "network.xyo/boundwitness")
  val boundWitnessStreamHandler = BoundWitnessStreamHandler()

  val addDeviceChannel = EventChannel(registrar.messenger(), "network.xyo/add_device")
  val addDeviceStreamHandler = AddDeviceEventHandler()

  val bridgeManager = BridgeManager(context)

  init {
    scannerChannel.setStreamHandler(scannerStreamHandler)
    boundWitnessChannel.setStreamHandler(boundWitnessStreamHandler)
    addDeviceChannel.setStreamHandler(addDeviceStreamHandler)

    XYIBeaconBluetoothDevice.enable(true)
    XyoBluetoothClient.enable(true)
    XyoSentinelX.enable(true)
    XY4BluetoothDevice.enable(true)

    val status = smartScan.status

    smartScan.addListener("XyoBlePlugin", this)

    GlobalScope.launch {
      if (status == XYSmartScan.Status.Enabled) {
        smartScan.start().await()
        server.startServer()
      }

      // pull things up from storage or start a new chain if needed
      bridgeManager.restoreAndInitBridge().await()
      bridgeManager.bridge.addListener("flutter_entry", onBoundWitness)
    }
  }

  override fun statusChanged(status: XYSmartScan.Status) {
    super.statusChanged(status)
  }

  override fun connectionStateChanged(device: XYBluetoothDevice, newState: Int) {
    super.connectionStateChanged(device, newState)
  }

  override fun detected(device: XYBluetoothDevice) {
    this@XyoBlePlugin.scannerStreamHandler.sendMessage(device)
    super.detected(device)
  }

  override fun entered(device: XYBluetoothDevice) {
    this@XyoBlePlugin.addDeviceStreamHandler.sendMessage(device)
    super.entered(device)
  }

  override fun exited(device: XYBluetoothDevice) {
    super.exited(device)
  }

  companion object {
      @JvmStatic fun registerWith(registrar: Registrar) {
      val channel = MethodChannel(registrar.messenger(), "network.xyo/xyo_ble")
      channel.setMethodCallHandler(XyoBlePlugin(registrar.activeContext(), registrar))
    }
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    GlobalScope.launch {
      Log.i("XyoBlePlugin", "onMethodCall: " + call.method)
      if (call.method == "getPlatformVersion") {
        result.success("Android ${android.os.Build.VERSION.RELEASE}")
      } else if (call.method == "gattSingle") {
        result.success(this@XyoBlePlugin.gattSingle(call, result).await())
      } else if (call.method == "gattGroup") {
        result.success(this@XyoBlePlugin.gattGroup(call, result).await())
      } else if (call.method == "gattList") {
        result.success(this@XyoBlePlugin.gattList(call, result).await())
      } else if (call.method == "startBoundWitness") {
        ui {
          result.success(this@XyoBlePlugin.startBoundWitness())
        }
      } else if (call.method == "stopBoundWitness") {
        result.success(this@XyoBlePlugin.stopBoundWitness())
      } else if (call.method == "addDeviceStartListening") {
        result.success(this@XyoBlePlugin.addDeviceStartListening())
      } else if (call.method == "addDeviceStopListening") {
        result.success(this@XyoBlePlugin.addDeviceStopListening())
      } else {
        result.notImplemented()
      }
    }
  }

  fun gattSingle(call: MethodCall, result: Result): Deferred<Boolean> {
    return GattSingleRequest.process(smartScan, call.arguments, result)
  }

  fun gattGroup(call: MethodCall, result: Result): Deferred<Boolean> {
    return GattGroupRequest.process(smartScan, call.arguments, result)
  }

  fun gattList(call: MethodCall, result: Result): Deferred<Boolean> {
    return GattGroupRequest.process(smartScan, call.arguments, result)
  }

  fun startBoundWitness(): Boolean {
    smartScan.addListener("flutter_entry_scan", bridgeManager.bridge.scanCallback)
    serverHelper.listener = bridgeManager.bridge.serverCallback
    
//    runBlocking {
//      val result = advertiserHelper.startAdvertiser().await()
//      println("Started advertiser: " + result.await()?.error)
//    }

    return true
  }

  fun stopBoundWitness(): Boolean {
    smartScan.removeListener("flutter_entry_scan")
    serverHelper.listener = null

    advertiserHelper.stopAdvertiser()

    return true
  }

  fun addDeviceStartListening(): Boolean {
    return false
  }

  fun addDeviceStopListening(): Boolean {
    return false
  }


  private val onBoundWitness = object : XyoNodeListener() {
    override fun onBoundWitnessEndSuccess(boundWitness: XyoBoundWitness) {
     GlobalScope.launch {
        val hashes = bridgeManager.bridge.blockRepository.getAllOriginBlockHashes().await() ?: return@launch
        val models = ArrayList<BoundWitness.DeviceBoundWitness>()

        for (hash in hashes) {
          val model = InteractionModel(bridgeManager.bridge.blockRepository, hash.bytesCopy, Date(), true)
          models.add(model.toBuffer())
        }

        boundWitnessStreamHandler.sendMessage(models.toTypedArray())

     }
    }
  }

}