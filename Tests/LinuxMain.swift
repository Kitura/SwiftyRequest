import XCTest
@testable import SwiftyRequestTests

XCTMain([
    testCase(SwiftyRequestTests.allTests),
    testCase(CodableExtensionsTests.allTests),
    testCase(JSONTests.allTests)
])
