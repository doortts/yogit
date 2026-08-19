import Cocoa
import FlutterMacOS

protocol WorkspaceOpening {
  @discardableResult
  func open(_ url: URL) -> Bool
}

extension NSWorkspace: WorkspaceOpening {}

class MainFlutterWindow: NSWindow {
  static var workspace: WorkspaceOpening = NSWorkspace.shared

  private var channel: FlutterMethodChannel?

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
    self.channel = channel
    self.watchVisibility()
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
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

  /// Whether the window is on screen for the user right now. AppKit is the only
  /// side that knows: Flutter turns its frames off while a window is covered,
  /// and if the engine misses the way back the app keeps its frames off and the
  /// picture freezes. Every notification that can end a covered stretch reports
  /// the window back to Dart, which revives the frames only if they really are
  /// still off.
  private func watchVisibility() {
    let center = NotificationCenter.default
    for name in [
      NSWindow.didChangeOcclusionStateNotification,
      NSWindow.didDeminiaturizeNotification,
      NSWindow.didBecomeKeyNotification,
    ] {
      center.addObserver(forName: name, object: self, queue: .main) {
        [weak self] _ in self?.reportVisibility()
      }
    }
    center.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: NSApp,
      queue: .main
    ) { [weak self] _ in self?.reportVisibility() }
  }

  private func reportVisibility() {
    guard occlusionState.contains(.visible), !isMiniaturized else { return }
    channel?.invokeMethod("windowBecameVisible", arguments: nil)
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
}
