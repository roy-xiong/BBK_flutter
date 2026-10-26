import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// 窗口持有后台工作标记，避免遮挡后的 App Nap；此选项仍允许系统正常休眠。
  private var gameActivity: NSObjectProtocol?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
    gameActivity = ProcessInfo.processInfo.beginActivity(
      options: [.userInitiatedAllowingIdleSystemSleep],
      reason: "BBK 游戏自动战斗与策略结算"
    )
  }

  deinit {
    if let activity = gameActivity {
      ProcessInfo.processInfo.endActivity(activity)
    }
  }
}
