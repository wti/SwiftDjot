import Cdjot
import Foundation
import Swift

/// Swift interface to the djot parser.
///
/// Call ``parse(_:includeSource:)`` to get ``Parse`` session reference used to
/// get html, AST, or match results until the next ``parse(_:includeSource:)`` call.
///
/// This is not thread-safe; use only from one thread.
///
/// This creates and holds a copy of the string passed to the parser until the next parse or deinit,
/// since the parser holds on to the buffer.
///
/// Warning: This is ALPHA quality with bugs likely.
public class Djot {
  /// initial parse id
  private static let PARSE_ID_START = 1000
  public static let DEMO_OK = 1

  /// Djot source version
  /// - Returns: String version of djot - no guarantees as to format
  public static func version() -> String {
    let name = "djot"
    let url = "https://github.com/jgm/djot.lua.git"
    let branch = "main"
    let commit = "5970f1cff2fe6b5905ec1cdeab795d5b5b3b8b97"
    return "\(name) \(url) \(branch)@\(commit)"
  }

  /// Print demo/proof that the underlying API is working, without any Swift conversions.
  /// Return ``DEMO_OK`` (1) on SUCCESS and 0 on failure (opposite of normal)
  public static func demo() -> Int {
    Int(djot_demo())
  }

  // Lua state in Djot lives as long as we do
  private typealias LuaStatePtr = OpaquePointer
  private let luaState: LuaStatePtr

  /// Identify this parser
  private let id = UUID()

  // Current parse() call
  private var parseId = PARSE_ID_START

  // Store string copies passed to parser until next parse or deinit.
  private var strings = [UnsafeMutablePointer<CChar>]()

  /// Initialize underlying djot data structures
  public init() {
    luaState = djot_open()
  }

  /// Release memory for underlying djot data structures and any buffer string copies we passed to it.
  deinit {
    deallocateStrings(strings.count)
    djot_close(luaState)
  }

  /// Check if this parse is valid (i.e., was ok originally, is associated with this Djot, and no other parse has started).
  /// - Parameter parse: Parse from this instance of Djot
  /// - Returns: true when the input parse is still the active one
  public func isValid(_ parse: Parse) -> Bool {
    parse.isValid(id, parseId)
  }

  /// Parse document string and return events  per `djot_parse_and_render_events`.
  /// - Parameter doc: djot String to parse
  /// - Returns: Result with Tuple of (``Parse``, event: String) or ``DjotErr``
  public func parseEvents(_ doc: String, copyDoc: Bool = true) -> Result<
    (Parse, String), DjotErr
  > {
    let oldStringCount = strings.count
    // Allocate string because djot holds onto it for duration of the parser
    guard let cstr = allocStrForDjot(doc) else {
      return .failure(.docStrCopy)
    }

    parseId += 1  // not thread-safe
    deallocateStrings(oldStringCount)
    guard let cstr = djot_parse_and_render_events(luaState, cstr) else {
      return .failure(
        .parseEvents(findErrorFromDjot("Unknown parseEvent error"))
      )
    }
    // Parse ok if it didn't fail.
    // Even if unable to read this result, might read others
    let parse = Parse(id, parseId, ok: true, inputCount: doc.count)

    let stringErr = CBridge.cToSwiftStr(cstr)
    switch stringErr {
    case let .success(result): return .success((parse, result))
    case let .failure(error): return .failure(.resultStrCopy(error))
    }
  }

  /// Parse document string per `djot_parse`, returning ``Parse`` used in result-gathering calls.
  /// - Parameters:
  ///   - doc: String in djot form (warning: encoding guarantees TBD)
  ///   - includeSource: Bool true to track source offsets
  /// - Returns: Result with ``Parse`` status or ``DjotErr``
  public func parse(_ doc: String, includeSource: Bool = false) -> Result<
    Parse, DjotErr
  > {
    let oldStringCount = strings.count
    // Allocate string because djot holds onto it for duration of the parser
    guard let cstr = allocStrForDjot(doc) else {
      return .failure(.docStrCopy)
    }

    parseId += 1
    deallocateStrings(oldStringCount)
    let result = djot_parse(luaState, cstr, includeSource)
    let validResult = 1  // unlike most unixy results
    if validResult != result {
      // TODO: djot api says to seek error on nil result; also seek on parse fail?
      let error = findErrorFromDjot("Unknown parse fail")
      return .failure(.parse(Int(result), error))
    }
    return .success(Parse(id, parseId, ok: true, inputCount: doc.count))
  }

  /// Get AST as json String for ``Parse`` if still valid
  /// - Parameter parse: valid ``Parse``
  /// - Returns: Result with String ast status or ``DjotErr``
  public func astJson(_ parse: Parse) -> Result<String, DjotErr> {
    guard parse.isValid(id, parseId) else { return .failure(.invalidParse) }
    guard let cstr = djot_render_ast_json(luaState) else {
      let error = findErrorFromDjot("Unknown error rendering AST as JSON")
      return .failure(.astAsJson(error))
    }
    return adaptCbridgeResultToDjotResult(CBridge.cToSwiftStr(cstr))
  }

  /// Get HTML corresponding to djot input of ``Parse``
  /// - Parameter parse: valid ``Parse``
  /// - Returns: Result with String in HTML form corresponding to djot inputor ``DjotErr``
  public func html(_ parse: Parse) -> Result<String, DjotErr> {
    guard parse.isValid(id, parseId) else { return .failure(.invalidParse) }
    guard let cstr = djot_render_html(luaState) else {
      let error = findErrorFromDjot("Unknown error rendering HTML")
      return .failure(.html(error))
    }
    return adaptCbridgeResultToDjotResult(CBridge.cToSwiftStr(cstr))
  }

  private func adaptCbridgeResultToDjotResult(
    _ stringErr: Result<String, CBridgeErr>
  ) -> Result<String, DjotErr> {
    switch stringErr {
    case let .success(result): return .success(result)
    case let .failure(error): return .failure(.resultStrCopy(error))
    }
  }

  private func findErrorFromDjot(_ defaultError: String) -> Result<
    String, CBridgeErr
  > {
    djot_report_error(luaState)
    guard let errString = djot_get_error(luaState) else {
      return .success(defaultError)
    }
    return CBridge.cToSwiftStr(errString)
  }

  private func allocStrForDjot(_ s: String) -> UnsafeMutablePointer<CChar>? {
    if let dup = strdup(s) {
      strings.append(dup)
      return dup
    }
    return nil
  }

  private func deallocateStrings(_ count: Int) {
    let max = strings.count > count ? count : strings.count
    let min = 0 > max ? 0 : max
    for i in 0..<min {
      strings[i].deallocate()
    }
    if 0 < min {
      strings.removeFirst(min)
    }
  }

  /// Errors returned by ``Djot`` operations.
  /// Error strings are exactly as reported by the underlying djot C library (except for programmer error).
  public enum DjotErr: Error {
    /// Client passed expired ``Djot.Parse``
    case invalidParse
    /// Failed making a copy of the input string before parsing
    case docStrCopy
    /// Failed during `djot_parse(..)`
    case parse(_ code: Int, _ error: Result<String, CBridgeErr>)
    /// Failed during `djot_parse_and_render_events(..)`
    case parseEvents(_ error: Result<String, CBridgeErr>)
    /// Failed during `djot_render_ast_json(..)`
    case astAsJson(_ error: Result<String, CBridgeErr>)
    /// Failed during `djot_render_html(..)`
    case html(_ error: Result<String, CBridgeErr>)
    /// djot command succeeded, but failed to copy resulting string
    case resultStrCopy(_ error: CBridgeErr)
    /// programming logic failure (bug - please report)
    case programmer(_ error: String)

    public var index: Int {
      switch self {
      case .invalidParse: return 0
      case .docStrCopy: return 1
      case .parse(_, _): return 2
      case .parseEvents(_): return 3
      case .astAsJson(_): return 4
      case .html(_): return 5
      case .resultStrCopy(_): return 6
      case .programmer(_): return 7
      }
    }

    /// True when failure came from underlying djot implementation
    public var djotFailed: Bool {
      switch self {
      case .parse(_, _): return true
      case .parseEvents(_): return true
      case .astAsJson(_): return true
      case .html(_): return true
      default: return false
      }
    }
  }

  /// The djot parse session status, esp. to obtain results in post-parse calls.
  /// A parse can only be used on the ``Djot`` instance that produced it,
  /// and it becomes invalid when the next parse starts.
  public struct Parse {
    public let ok: Bool
    private let id: UUID
    private let parseId: Int
    fileprivate let inputCount: Int
    public init(_ id: UUID, _ parseId: Int, ok: Bool, inputCount: Int) {
      self.id = id
      self.ok = ok
      self.parseId = parseId
      self.inputCount = inputCount
    }

    /// true if parse completed normally on this instance and no other parse has started.
    fileprivate func isValid(_ id: UUID, _ parseId: Int) -> Bool {
      ok && id == self.id && parseId == self.parseId
    }
  }
}

/// Errors from bridging C types to swift
public enum CBridgeErr: Error {
  /// Invalid unicode character at index
  case encodingError(String, String.Index)
}

/// Converting data between C and Swift
public enum CBridge {
  public static let invalidUnicodeChar: Character = "\u{FFFD}"

  /// Check for ``invalidUnicodeChar`` injected by ``String.init(cString:)`` when
  /// the input character array has invalid unicode sequences.
  /// - Parameter s: String to inspect
  /// - Returns: index of first ``invalidUnicodeChar``
  public static func unicodeInvalidAt(_ s: String) -> String.Index? {
    s.firstIndex { invalidUnicodeChar == $0 }
  }

  /// Read charPtr as C-string into Swift String and flag invalid encoding in result.
  /// - Parameters:
  ///   - charPtr: UnsafeMutablePointer<CChar>
  /// - Returns: Result<String, CBridgeErr>
  public static func cToSwiftStr(
    _ charPtr: UnsafePointer<CChar>
  ) -> Result<String, CBridgeErr> {
    let result = String(cString: charPtr)

    // String(cString) API docs say it copies from the buffer, so we could deallocate
    // charPtr.deallocate()
    // but get error: pointer being freed was not allocated (by us, presumably)
    // so results are likely freed by djot

    if let index = unicodeInvalidAt(result) {
      return .failure(.encodingError(result, index))
    }
    return .success(result)
  }
}
