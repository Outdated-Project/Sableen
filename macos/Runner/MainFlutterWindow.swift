import Cocoa
import FlutterMacOS
import OpenGL.GL

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let video = FlutterMethodChannel(name: "sableen/video", binaryMessenger: flutterViewController.engine.binaryMessenger)
    video.setMethodCallHandler { call, result in
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
