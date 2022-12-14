import XCTest

@testable import SwiftDjot

class DjotTests: XCTestCase {
  public static let quiet = "" == ""  // edit during debugging

  func testDemo() {
    if !Self.quiet {
      XCTAssert(Djot.DEMO_OK == Djot.demo())
    }
  }

  func testHtml() {
    checkHtml("hi")
  }

  func testHtmlEmoji() {
    checkHtml("🦗")
  }

  func checkHtml(_ header: String) {
    let me = Djot()
    let parse = me.parse("# \(header)\n")
    guard let parse = assertOk(parse) else { return }
    let html = me.html(parse)
    guard let html = assertOk(html) else { return }
    let expected = "<sectionid=\"\(header)\"><h1>\(header)</h1></section>"
    check(parse, html, expected)
  }

  func testEvents() {
    let me = Djot()
    let peResult = me.parseEvents("# hi\n")
    guard let result = assertOk(peResult) else { return }

    let (parse, events) = result
    let expected = """
      [["+heading",1,1],["str",3,4],["-heading",4,4]]
      """
    check(parse, events, expected)
  }

  /// CDjot permits running parses in parallel in different instances.
  /// Though the code sets Lua "global" values, they are scoped to the Lua parser instance held by the Djot.
  func testHtmlDuals() {
    let me1 = Djot()
    let parse1 = me1.parse("# hi\n")
    let me2 = Djot()
    let parse2 = me2.parse("# low\n")
    guard let parse1 = assertOk(parse1) else { return }  // failed already
    guard let parse2 = assertOk(parse2) else { return }  // failed already
    let html2 = me2.html(parse2)  // invalidates parse1 IF global
    let html1 = me1.html(parse1)  // using invalidated parse?
    guard let htm1Result = assertOk(html1, "hi") else { return }
    guard let htm2Result = assertOk(html2, "lo") else { return }
    let expected1 = "<sectionid=\"hi\"><h1>hi</h1></section>"
    check(parse1, htm1Result, expected1)
    let expected2 = "<sectionid=\"low\"><h1>low</h1></section>"
    check(parse2, htm2Result, expected2)
  }

  /// Verify that stale parses trigger the corresponding error.
  func testInvalidParse() {
    let me = Djot()
    let parse1 = me.parse("# hi\n")
    guard let parse1 = assertOk(parse1) else { return }
    _ = me.parse("# hi\n")  // invalidates parse1
    let html1 = me.html(parse1)
    switch html1 {
    case .success(_): XCTFail("should have failed")
    case let .failure(err):
      let exp = Djot.DjotErr.invalidParse
      XCTAssertEqual(exp.index, err.index)
    }
  }

  func assertOk<T, E: Error>(
    _ result: Result<T, E>,
    _ label: String? = "Result",
    permitPartial: Bool = false,
    line: UInt = #line
  ) -> T? {
    switch result {
    case let .success(result): return result
    case let .failure(error):
      if let err = error as? CBridgeErr {
        XCTFail(errStr(err, label), line: line)
        return nil
      }
      if let err = error as? Djot.DjotErr {
        XCTFail(errStr(err, label), line: line)
        return nil
      }
      XCTFail("programmer error: not DjotErr or CBridgeErr", line: line)
    }
    return nil
  }

  func check(
    _ parse: Djot.Parse,
    _ actual: String?,
    _ strippedExpected: String,
    _ line: UInt = #line
  ) {
    let label = " - expected \"\(strippedExpected)\""
    guard let actual = actual else {
      XCTFail("no result \(label)", line: line)
      return
    }
    guard parse.ok else {
      XCTFail("not ok \(label)", line: line)
      return
    }
    let strippedActual = strip(actual)
    XCTAssertEqual(
      strippedExpected,
      strippedActual,
      "actual: \"\(actual)\" \(label)",
      line: line
    )
  }

  func strip(_ s: String) -> String {
    s.replacingOccurrences(of: " ", with: "")
      .replacingOccurrences(of: "\n", with: "")
  }
  func errStr(_ e: Djot.DjotErr?, _ suffix: String? = nil) -> String {
    (nil == e ? "nil DjotErr" : "\(e!)") + "\(suffix ?? "")"
  }
  func errStr(_ e: CBridgeErr!, _ suffix: String? = nil) -> String {
    nil == e ? "nil CBridgeErr" : "\(e!)" + "\(suffix ?? "")"
  }
}
