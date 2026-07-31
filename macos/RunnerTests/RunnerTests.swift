import Cocoa
import FlutterMacOS
import XCTest
@testable import yogit

final class RecordingWorkspace: WorkspaceOpening {
  var opened: URL?

  func open(_ url: URL) -> Bool {
    opened = url
    return true
  }
}

class RunnerTests: XCTestCase {
  func testRightPreviewGrowsRightUntilItReachesTheScreenEdge() {
    let visibleFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)

    XCTAssertEqual(
      MainFlutterWindow.rightPreviewFrame(
        from: NSRect(x: 100, y: 100, width: 800, height: 600),
        visibleFrame: visibleFrame
      ),
      NSRect(x: 100, y: 100, width: 1120, height: 600)
    )
    XCTAssertEqual(
      MainFlutterWindow.rightPreviewFrame(
        from: NSRect(x: 1000, y: 100, width: 800, height: 600),
        visibleFrame: visibleFrame
      ),
      NSRect(x: 800, y: 100, width: 1120, height: 600)
    )
  }

  func testOpenFileUsesAFileURL() {
    let workspace = RecordingWorkspace()
    MainFlutterWindow.workspace = workspace
    defer { MainFlutterWindow.workspace = NSWorkspace.shared }

    XCTAssertTrue(MainFlutterWindow.openFile(path: "/tmp/a b;name.txt"))
    XCTAssertEqual(workspace.opened?.isFileURL, true)
    XCTAssertEqual(workspace.opened?.path, "/tmp/a b;name.txt")
  }
}
