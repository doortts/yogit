import Cocoa
import FlutterMacOS

protocol WorkspaceOpening {
  @discardableResult
  func open(_ url: URL) -> Bool
}

extension NSWorkspace: WorkspaceOpening {}

class MainFlutterWindow: NSWindow {
  static var workspace: WorkspaceOpening = NSWorkspace.shared

  private var previewBaseFrame: NSRect?

  static func openFile(path: String) -> Bool {
    workspace.open(URL(fileURLWithPath: path))
  }

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    self.contentMinSize = NSSize(width: 480, height: 560)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    // The toolbar draws its own traffic lights and title, so the native titlebar
    // steps aside. The menu bar keeps Cmd+W and Cmd+Q, and .resizable stays in
    // the mask, so resizing and fullscreen still work.
    self.titlebarAppearsTransparent = true
    self.titleVisibility = .hidden
    self.styleMask.insert(.fullSizeContentView)
    for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
      self.standardWindowButton(button)?.isHidden = true
    }

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
      case "openFile":
        guard
          let arguments = call.arguments as? [String: Any],
          let path = arguments["path"] as? String
        else {
          result(
            FlutterError(
              code: "invalid_path",
              message: "A file path is required.",
              details: nil
            )
          )
          return
        }
        result(MainFlutterWindow.openFile(path: path))
      case "closeWindow":
        self?.performClose(nil)
        result(nil)
      case "minimizeWindow":
        self?.miniaturize(nil)
        result(nil)
      case "toggleZoom":
        self?.zoom(nil)
        result(nil)
      case "isZoomed":
        result(self?.isZoomed ?? false)
      case "startDrag":
        // Without a current event there is no drag to hand to AppKit.
        if let event = NSApp.currentEvent {
          self?.performDrag(with: event)
        }
        result(nil)
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
    if placement == "right" {
      nextFrame = Self.rightPreviewFrame(from: baseFrame, visibleFrame: visibleFrame)
    } else if placement == "left" {
      // A left preview keeps the right edge and grows the window leftward.
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

  static func rightPreviewFrame(from baseFrame: NSRect, visibleFrame: NSRect) -> NSRect {
    let width = min(baseFrame.width + 320, visibleFrame.width)
    return NSRect(
      x: min(max(baseFrame.minX, visibleFrame.minX), visibleFrame.maxX - width),
      y: max(visibleFrame.minY, min(baseFrame.minY, visibleFrame.maxY - baseFrame.height)),
      width: width,
      height: min(baseFrame.height, visibleFrame.height)
    )
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
