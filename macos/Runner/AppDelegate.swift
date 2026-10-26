import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  /// 旧系统通过观察应用外观更新 Dock；弱引用回调避免观察器持有应用代理。
  private var appearanceObservation: NSKeyValueObservation?

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    if #available(macOS 26.0, *) {
      // 新系统交给 Icon Composer，保留用户独立选择的图标外观。
      return
    }
    appearanceObservation = NSApplication.shared.observe(
      \.effectiveAppearance, options: [.initial, .new]
    ) { [weak self] _, _ in
      // KVO 回调不假定调用线程，所有 AppKit 更新统一调度到主线程。
      DispatchQueue.main.async { [weak self] in
        self?.refreshLegacyDockIcon()
      }
    }
  }

  /// macOS 15 及更早版本只更新当前应用的 Dock，不修改系统主题与其他应用。
  private func refreshLegacyDockIcon() {
    let application = NSApplication.shared
    let dark = application.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    let name = NSImage.Name(dark ? "DockIconDark" : "DockIconLight")
    guard let image = NSImage(named: name) else { return }
    application.applicationIconImage = image
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
