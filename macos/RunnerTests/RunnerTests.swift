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
  func testOpenFileUsesAFileURL() {
    let workspace = RecordingWorkspace()
    MainFlutterWindow.workspace = workspace
    defer { MainFlutterWindow.workspace = NSWorkspace.shared }

    XCTAssertTrue(MainFlutterWindow.openFile(path: "/tmp/a b;name.txt"))
    XCTAssertEqual(workspace.opened?.isFileURL, true)
    XCTAssertEqual(workspace.opened?.path, "/tmp/a b;name.txt")
  }
}
