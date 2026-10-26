package com.xiongjian.bbk_flutter

import android.os.Handler
import android.os.Looper
import android.view.InputDevice
import android.view.MotionEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs

/**
 * Flutter平台薄桥，只提供摇杆输入和前台常亮，不持有或执行游戏规则。
 *
 * 事件通道、Handler和窗口状态均由当前Activity拥有，全部在主线程更新；退出、
 * 失去前台或FlutterEngine分离时停止重复输入并释放通道，避免旧Activity被保留。
 */
class MainActivity : FlutterActivity() {
    private val inputHandler = Handler(Looper.getMainLooper())
    private var eventChannel: EventChannel? = null
    private var methodChannel: MethodChannel? = null
    private var eventSink: EventChannel.EventSink? = null
    private var activeDirections: Set<String> = emptySet()
    private var foreground = false
    private var awakeRequested = false

    /** 长按摇杆的重复输入由单个回调驱动，不能为每次MotionEvent叠加Timer。 */
    private val repeatInput = object : Runnable {
        override fun run() {
            if (!foreground || isFinishing || isDestroyed || eventSink == null) {
                stopRepeating()
                return
            }
            activeDirections.forEach { direction -> eventSink?.success(direction) }
            if (activeDirections.isNotEmpty()) inputHandler.postDelayed(this, 120L)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, "sgby_flutter/controller").also { channel ->
            channel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    stopRepeating()
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    stopRepeating()
                    eventSink = null
                }
            })
        }
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "sgby_flutter/platform").also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method == "setScreenAwake") {
                    awakeRequested = call.argument<Boolean>("enabled") == true
                    updateScreenAwake()
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
        }
    }

    /**
     * Android摇杆MotionEvent不会自动转换成Flutter键盘事件，在此转换为方向消息。
     * 实体按钮和方向键继续交给Flutter键盘通道，避免同一次按键被重复发送。
     */
    override fun onGenericMotionEvent(event: MotionEvent?): Boolean {
        val source = event?.source ?: return false
        if (source and InputDevice.SOURCE_JOYSTICK != InputDevice.SOURCE_JOYSTICK ||
            event.actionMasked != MotionEvent.ACTION_MOVE || eventSink == null || !foreground
        ) return super.onGenericMotionEvent(event)

        fun axis(hat: Int, stick: Int): Float {
            val value = event.getAxisValue(hat)
            return if (abs(value) >= 0.5f) value else event.getAxisValue(stick)
        }
        val x = axis(MotionEvent.AXIS_HAT_X, MotionEvent.AXIS_X)
        val y = axis(MotionEvent.AXIS_HAT_Y, MotionEvent.AXIS_Y)
        val directions = linkedSetOf<String>()
        if (x < -0.5f) directions.add("left")
        if (x > 0.5f) directions.add("right")
        if (y < -0.5f) directions.add("up")
        if (y > 0.5f) directions.add("down")
        if (directions != activeDirections) {
            stopRepeating()
            activeDirections = directions
            directions.forEach { direction -> eventSink?.success(direction) }
            if (directions.isNotEmpty()) inputHandler.postDelayed(repeatInput, 400L)
        }
        return true
    }

    private fun updateScreenAwake() {
        val currentWindow = window ?: return
        if (awakeRequested && foreground && !isFinishing && !isDestroyed) {
            currentWindow.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            currentWindow.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    private fun stopRepeating() {
        inputHandler.removeCallbacks(repeatInput)
        activeDirections = emptySet()
    }

    override fun onResume() {
        super.onResume()
        foreground = true
        updateScreenAwake()
    }

    override fun onPause() {
        foreground = false
        stopRepeating()
        updateScreenAwake()
        super.onPause()
    }

    private fun releaseBridge() {
        foreground = false
        awakeRequested = false
        stopRepeating()
        updateScreenAwake()
        eventSink = null
        eventChannel?.setStreamHandler(null)
        methodChannel?.setMethodCallHandler(null)
        eventChannel = null
        methodChannel = null
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        releaseBridge()
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        releaseBridge()
        super.onDestroy()
    }
}
