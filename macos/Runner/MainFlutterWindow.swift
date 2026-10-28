import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// 窗口持有后台工作标记，避免遮挡后的 App Nap；此选项仍允许系统正常休眠。
  private var gameActivity: NSObjectProtocol?
  private var windowChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
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
    windowChannel?.setMethodCallHandler(nil)
    if let activity = gameActivity {
      ProcessInfo.processInfo.endActivity(activity)
    }
  }
}
