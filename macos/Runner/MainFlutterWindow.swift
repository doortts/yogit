import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var previewBaseFrame: NSRect?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentMinSize = NSSize(width: 960, height: 560)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let channel = FlutterMethodChannel(
      name: "yogit/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "setPreview":
        guard let placement = call.arguments as? String else {
          result(FlutterMethodNotImplemented)
          return
        }
        self?.setPreview(placement)
        result(nil)
      case "pickRepository":
        result(MainFlutterWindow.pickRepository())
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  /// The native directory chooser, or nil when the user cancels.
  private static func pickRepository() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "Open"
    return panel.runModal() == .OK ? panel.url?.path : nil
  }

  private func setPreview(_ placement: String) {
    guard let visibleFrame = (screen ?? NSScreen.main)?.visibleFrame else { return }
    if placement == "closed" {
      if let baseFrame = previewBaseFrame {
        setFrame(clamped(baseFrame, to: visibleFrame), display: true, animate: true)
      }
      previewBaseFrame = nil
      return
    }

    if previewBaseFrame == nil {
      previewBaseFrame = frame
    }
    guard let baseFrame = previewBaseFrame else { return }

    let nextFrame: NSRect
    if placement == "right" || placement == "left" {
      // Both side placements keep the right edge and grow the window leftward,
      // so the timeline stays where the user last saw it.
      let width = min(baseFrame.width + 320, visibleFrame.width)
      let right = min(baseFrame.maxX, visibleFrame.maxX)
      nextFrame = NSRect(
        x: max(visibleFrame.minX, right - width),
        y: max(visibleFrame.minY, min(baseFrame.minY, visibleFrame.maxY - baseFrame.height)),
        width: width,
        height: min(baseFrame.height, visibleFrame.height)
      )
    } else if placement == "bottom" {
      let height = min(baseFrame.height + 280, visibleFrame.height)
      let top = min(baseFrame.maxY, visibleFrame.maxY)
      nextFrame = NSRect(
        x: max(visibleFrame.minX, min(baseFrame.minX, visibleFrame.maxX - baseFrame.width)),
        y: max(visibleFrame.minY, top - height),
        width: min(baseFrame.width, visibleFrame.width),
        height: height
      )
    } else {
      return
    }
    setFrame(nextFrame, display: true, animate: true)
  }

  private func clamped(_ frame: NSRect, to visibleFrame: NSRect) -> NSRect {
    let width = min(frame.width, visibleFrame.width)
    let height = min(frame.height, visibleFrame.height)
    return NSRect(
      x: min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width),
      y: min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height),
      width: width,
      height: height
    )
  }
}
