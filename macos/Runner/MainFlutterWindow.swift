import Cocoa
import FlutterMacOS
import OpenGL.GL

class MainFlutterWindow: NSWindow {
  // AppKit moves the window between Spaces asynchronously. Report completion
  // after that move so the new player doesn't see the outgoing Space go hidden.
  private func setTheaterFullscreen(_ enabled: Bool, result: @escaping FlutterResult) {
    guard styleMask.contains(.fullScreen) != enabled else {
      result(true)
      return
    }
    let notification = enabled ? NSWindow.didEnterFullScreenNotification : NSWindow.didExitFullScreenNotification
    var observer: NSObjectProtocol?
    func finish() {
      guard let token = observer else { return }
      NotificationCenter.default.removeObserver(token)
      observer = nil
      result(self.styleMask.contains(.fullScreen) == enabled)
    }
    observer = NotificationCenter.default.addObserver(forName: notification, object: self, queue: .main) { _ in finish() }
    toggleFullScreen(nil)
    // AppKit can decline a request without posting the completion notification.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish() }
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let video = FlutterMethodChannel(name: "sableen/video", binaryMessenger: flutterViewController.engine.binaryMessenger)
    video.setMethodCallHandler { [weak self] call, result in
      if call.method == "setFullscreen", let enabled = call.arguments as? Bool {
        guard let window = self else { result(false); return }
        window.setTheaterFullscreen(enabled, result: result)
        return
      }
      guard call.method == "supportsAcceleratedTexture" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let attributes: [CGLPixelFormatAttribute] = [
        kCGLPFAOpenGLProfile, CGLPixelFormatAttribute(kCGLOGLPVersion_3_2_Core.rawValue),
        kCGLPFAAccelerated, kCGLPFADoubleBuffer, kCGLPFAColorSize, CGLPixelFormatAttribute(rawValue: 64),
        kCGLPFAColorFloat, kCGLPFABackingStore, kCGLPFAAllowOfflineRenderers,
        kCGLPFASupportsAutomaticGraphicsSwitching, CGLPixelFormatAttribute(rawValue: 0)
      ]
      var format: CGLPixelFormatObj?
      var count: GLint = 0
      CGLChoosePixelFormat(attributes, &format, &count)
      guard let format = format else { result(false); return }
      CGLReleasePixelFormat(format)
      result(count > 0)
    }

    super.awakeFromNib()
  }
}
