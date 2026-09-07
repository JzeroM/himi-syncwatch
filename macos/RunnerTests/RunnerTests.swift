import XCTest
import FlutterMacOS

class RunnerTests: XCTestCase {
  func testExample() throws {
    let pluginRegistry = FlutterPluginRegistry()
    XCTAssertTrue(pluginRegistry !== nil)
  }
}
