// Command Line Tools do not include XCTest. These assertions run the same test
// methods without downloading a test framework; Xcode/SwiftPM use XCTest normally.
#if !canImport(XCTest)
import Foundation

class XCTestCase {}
enum PortableTestLog {
    static var failureCount = 0
    static func fail(_ message: String, file: StaticString, line: UInt) {
        failureCount += 1; print("FAIL \(file):\(line): \(message)")
    }
}
func XCTAssertTrue(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try !value() { PortableTestLog.fail("expected true", file: file, line: line) } }
    catch { PortableTestLog.fail(error.localizedDescription, file: file, line: line) }
}
func XCTAssertFalse(_ value: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) {
    do { if try value() { PortableTestLog.fail("expected false", file: file, line: line) } }
    catch { PortableTestLog.fail(error.localizedDescription, file: file, line: line) }
}
func XCTAssertEqual<T: Equatable>(_ left: @autoclosure () throws -> T, _ right: @autoclosure () throws -> T,
                                  file: StaticString = #filePath, line: UInt = #line) {
    do {
        let a = try left(); let b = try right()
        if a != b { PortableTestLog.fail("\(a) != \(b)", file: file, line: line) }
    } catch { PortableTestLog.fail(error.localizedDescription, file: file, line: line) }
}
func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try value(); PortableTestLog.fail("expected error", file: file, line: line) } catch {}
}
#endif
