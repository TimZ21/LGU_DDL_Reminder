import Foundation
#if canImport(XCTest)
import XCTest
#endif

@main
struct CoreTestRunner {
    static func main() {
        #if canImport(XCTest)
        XCTMain([testCase(DeadlineCoreTests.allTests)])
        #else
        for (name, body) in DeadlineCoreTests.allTests {
            let before = PortableTestLog.failureCount
            do { try body(DeadlineCoreTests())() }
            catch { PortableTestLog.fail(error.localizedDescription, file: #filePath, line: #line) }
            print("\(before == PortableTestLog.failureCount ? "PASS" : "FAIL"): \(name)")
        }
        print("\(DeadlineCoreTests.allTests.count) tests, \(PortableTestLog.failureCount) failures")
        if PortableTestLog.failureCount > 0 { exit(1) }
        #endif
    }
}
