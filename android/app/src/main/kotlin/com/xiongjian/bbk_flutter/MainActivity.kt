package com.xiongjian.bbk_flutter

import android.hardware.input.InputManager
import android.os.Handler
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity

/**
 * 共享手柄插件桥：按钮和摇杆走同一个输入层，避免旧通道重复发送方向。
 *
 * 插件只处理手柄设备，普通键盘仍交给Flutter。Activity只负责输入和前台常亮，
 * 不持有游戏引擎；所有通道、监听器和窗口状态在Android主线程更新及释放。
 */
class MainActivity : FlutterActivity(), GamepadsCompatibleActivity {
    private var keyHandler: ((KeyEvent) -> Boolean)? = null
    private var motionHandler: ((MotionEvent) -> Boolean)? = null
    private val deviceListeners = mutableSetOf<InputManager.InputDeviceListener>()
    private var legacyChannel: EventChannel? = null
    private var methodChannel: MethodChannel? = null
    private var foreground = false
    private var awakeRequested = false

    override fun registerInputDeviceListener(listener: InputManager.InputDeviceListener, handler: Handler?) {
        val manager = getSystemService(INPUT_SERVICE) as? InputManager ?: return
        if (deviceListeners.add(listener)) manager.registerInputDeviceListener(listener, handler)
    }
    override fun registerKeyEventHandler(handler: (KeyEvent) -> Boolean) { keyHandler = handler }
    override fun registerMotionEventHandler(handler: (MotionEvent) -> Boolean) { motionHandler = handler }

    override fun dispatchKeyEvent(event: KeyEvent?): Boolean {
        if (event == null) return false
        if (foreground && keyHandler?.invoke(event) == true) return true
        return super.dispatchKeyEvent(event)
    }
    override fun dispatchGenericMotionEvent(event: MotionEvent?): Boolean {
        if (event == null) return false
        if (foreground && motionHandler?.invoke(event) == true) return true
        return super.dispatchGenericMotionEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 旧三国霸业服务保留握手，实际输入统一走gamepads，不再运行第二个连发器。
        legacyChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "sgby_flutter/controller").also {
            it.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) = Unit
                override fun onCancel(arguments: Any?) = Unit
            })
        }
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sgby_flutter/platform").also {
            it.setMethodCallHandler { call, result ->
                if (call.method == "setScreenAwake") {
                    awakeRequested = call.argument<Boolean>("enabled") == true
                    updateScreenAwake()
                    result.success(null)
                } else result.notImplemented()
            }
        }
    }
    private fun updateScreenAwake() {
        val currentWindow = window ?: return
        if (awakeRequested && foreground && !isFinishing && !isDestroyed) {
            currentWindow.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else currentWindow.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
    }
    override fun onResume() { super.onResume(); foreground = true; updateScreenAwake() }
    override fun onPause() { foreground = false; updateScreenAwake(); super.onPause() }

    /** 可重复释放：Engine分离和Activity销毁均不遗留捕获旧Activity的输入闭包。 */
    private fun releaseBridge() {
        foreground = false
        awakeRequested = false
        updateScreenAwake()
        keyHandler = null
        motionHandler = null
        val manager = getSystemService(INPUT_SERVICE) as? InputManager
        deviceListeners.forEach { manager?.unregisterInputDeviceListener(it) }
        deviceListeners.clear()
        legacyChannel?.setStreamHandler(null)
        methodChannel?.setMethodCallHandler(null)
        legacyChannel = null
        methodChannel = null
    }
    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) { releaseBridge(); super.cleanUpFlutterEngine(flutterEngine) }
    override fun onDestroy() { releaseBridge(); super.onDestroy() }
}
