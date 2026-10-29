import Cocoa
import FlutterMacOS
import IOKit.hid

class MainFlutterWindow: NSWindow {
  /// 窗口持有后台工作标记，避免遮挡后的 App Nap；此选项仍允许系统正常休眠。
  private var gameActivity: NSObjectProtocol?
  private var windowChannel: FlutterMethodChannel?
  private var hidGamepad: BbkHidGamepadBridge?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    hidGamepad = BbkHidGamepadBridge(messenger: flutterViewController.engine.binaryMessenger)
    let channel = FlutterMethodChannel(
      name: "bbk_flutter/window", binaryMessenger: flutterViewController.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "minimize" else {
        result(FlutterMethodNotImplemented)
        return
      }
      // Flutter平台消息在主线程处理；弱引用不延长窗口及其引擎的生命周期。
      self?.miniaturize(nil)
      result(nil)
    }
    windowChannel = channel

    super.awakeFromNib()
    // NSWindow在用户移动、缩放后自动保存frame；两款游戏共用宿主窗口，跨启动恢复。
    // 必须在Flutter替换contentViewController及初始frame之后读取，避免默认大小覆盖旧值。
    let frameName = NSWindow.FrameAutosaveName("BBKClassicGames2MainWindow")
    setFrameAutosaveName(frameName)
    setFrameUsingName(frameName)

    gameActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep],
      reason: "BBK 游戏自动战斗与策略结算"
    )
  }

  deinit {
    hidGamepad?.dispose()
    windowChannel?.setMethodCallHandler(nil)
    if let activity = gameActivity {
      ProcessInfo.processInfo.endActivity(activity)
    }
  }
}


/// 北通XInput模式的USB后备。仅匹配Xbox360兼容设备，不监听键盘鼠标。
/// IOHID主RunLoop回调在通道取消或窗口销毁时停止，避免悬空回调和设备占用。
private final class BbkHidGamepadBridge: NSObject, FlutterStreamHandler {
  private let channel: FlutterEventChannel
  private var manager: IOHIDManager?
  private var sink: FlutterEventSink?
  private var selected: IOHIDDevice?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterEventChannel(name: "bbk_flutter/hid_gamepad", binaryMessenger: messenger)
    super.init()
    channel.setStreamHandler(self)
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    stop()
    sink = events
    let hid = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    manager = hid
    IOHIDManagerSetDeviceMatching(hid, [kIOHIDVendorIDKey: 0x045e, kIOHIDProductIDKey: 0x028e] as CFDictionary)
    let context = Unmanaged.passUnretained(self).toOpaque()
    IOHIDManagerRegisterDeviceMatchingCallback(hid, { context, _, _, _ in
      guard let context = context else { return }
      Unmanaged<BbkHidGamepadBridge>.fromOpaque(context).takeUnretainedValue().selectDevice()
    }, context)
    IOHIDManagerRegisterDeviceRemovalCallback(hid, { context, _, _, _ in
      guard let context = context else { return }
      Unmanaged<BbkHidGamepadBridge>.fromOpaque(context).takeUnretainedValue().selectDevice()
    }, context)
    IOHIDManagerRegisterInputValueCallback(hid, { context, result, _, value in
      guard let context = context, result == kIOReturnSuccess else { return }
      Unmanaged<BbkHidGamepadBridge>.fromOpaque(context).takeUnretainedValue().receive(value)
    }, context)
    IOHIDManagerScheduleWithRunLoop(hid, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
    let result = IOHIDManagerOpen(hid, IOOptionBits(kIOHIDOptionsTypeNone))
    guard result == kIOReturnSuccess else {
      stop()
      return FlutterError(code: "hid_open", message: "USB手柄暂不可用，仍可使用键盘与屏幕按键。", details: result)
    }
    selectDevice()
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { stop(); return nil }
  private func identifier(_ device: IOHIDDevice) -> String {
    var registryID: UInt64 = 0
    IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID)
    return "hid:\(registryID)"
  }
  /// Apple可能同时暴露Controller和GamePad代理，只选择一份报告，防止双走。
  private func selectDevice() {
    guard let manager = manager else { return }
    let devices = (IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>) ?? []
    let candidates = devices.filter { device in
      let page = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int
      let usage = IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsageKey as CFString) as? Int
      return page == 1 && (usage == 4 || usage == 5)
    }.sorted { identifier($0) < identifier($1) }
    let next = candidates.first { device in
      (IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String)?.hasPrefix("GamePad") == true
    } ?? candidates.first
    if let previous = selected {
      let changed = next.map { identifier($0) != identifier(previous) } ?? true
      if changed { sink?(["id": identifier(previous), "disconnected": true]) }
    }
    selected = next
  }
  private func receive(_ value: IOHIDValue) {
    guard let selected = selected, let sink = sink else { return }
    let element = IOHIDValueGetElement(value)
    let device = IOHIDElementGetDevice(element)
    guard identifier(device) == identifier(selected) else { return }
    let page = IOHIDElementGetUsagePage(element), usage = IOHIDElementGetUsage(element)
    guard page == 9 || (page == 1 && (usage == 0x30 || usage == 0x31 || usage == 0x35)) else { return }
    sink(["id": identifier(device), "page": Int(page), "usage": Int(usage),
      "value": IOHIDValueGetIntegerValue(value), "min": IOHIDElementGetLogicalMin(element),
      "max": IOHIDElementGetLogicalMax(element)])
  }
  private func stop() {
    if let manager = manager {
      IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
      IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }
    manager = nil; selected = nil; sink = nil
  }
  func dispose() { channel.setStreamHandler(nil); stop() }
}
