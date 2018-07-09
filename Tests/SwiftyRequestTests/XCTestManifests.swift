import XCTest

extension CodableExtensionsTests {
    static let __allTests = [
        ("testDecodeAdditionalProperties", testDecodeAdditionalProperties),
        ("testDecodeCustom", testDecodeCustom),
        ("testDecodeMetadata", testDecodeMetadata),
        ("testDecodeOptional", testDecodeOptional),
        ("testDecodeOptionalEmpty", testDecodeOptionalEmpty),
        ("testDecodeOptionalNil", testDecodeOptionalNil),
        ("testDecodeSimpleModel", testDecodeSimpleModel),
        ("testEncodeAdditionalProperties", testEncodeAdditionalProperties),
        ("testEncodeCustom", testEncodeCustom),
        ("testEncodeMetadata", testEncodeMetadata),
        ("testEncodeNil", testEncodeNil),
        ("testEncodeOptional", testEncodeOptional),
        ("testEncodeOptionalEmpty", testEncodeOptionalEmpty),
        ("testEncodeOptionalNil", testEncodeOptionalNil),
    ]
}

extension JSONTests {
    static let __allTests = [
        ("testDecodeArray", testDecodeArray),
        ("testDecodeArrayOfObjects", testDecodeArrayOfObjects),
        ("testDecodeBool", testDecodeBool),
        ("testDecodeDeeplyNested", testDecodeDeeplyNested),
        ("testDecodeDouble", testDecodeDouble),
        ("testDecodeEmptyObject", testDecodeEmptyObject),
        ("testDecodeInt", testDecodeInt),
        ("testDecodeNested", testDecodeNested),
        ("testDecodeNestedArrays", testDecodeNestedArrays),
        ("testDecodeNull", testDecodeNull),
        ("testDecodeObject", testDecodeObject),
        ("testDecodeString", testDecodeString),
        ("testDecodeTopLevelArray", testDecodeTopLevelArray),
        ("testEncodeArray", testEncodeArray),
        ("testEncodeArrayOfObjects", testEncodeArrayOfObjects),
        ("testEncodeBool", testEncodeBool),
        ("testEncodeDeeplyNested", testEncodeDeeplyNested),
        ("testEncodeDouble", testEncodeDouble),
        ("testEncodeEmptyObject", testEncodeEmptyObject),
        ("testEncodeInt", testEncodeInt),
        ("testEncodeNested", testEncodeNested),
        ("testEncodeNestedArrays", testEncodeNestedArrays),
        ("testEncodeNull", testEncodeNull),
        ("testEncodeObject", testEncodeObject),
        ("testEncodeString", testEncodeString),
        ("testEncodeTopLevelArray", testEncodeTopLevelArray),
        ("testEquality", testEquality),
    ]
}

extension SwiftyRequestTests {
    static let __allTests = [
        ("testEchoData", testEchoData),
        ("testResponseData", testResponseData),
        ("testResponseObject", testResponseObject),
        ("testQueryObject", testQueryObject),
        ("testResponseArray", testResponseArray),
        ("testResponseString", testResponseString),
        ("testResponseVoid", testResponseVoid),
        ("testFileDownload", testFileDownload),
        ("testRequestUserAgent", testRequestUserAgent),
        ("testCircuitBreakResponseString", testCircuitBreakResponseString),
        ("testCircuitBreakFailure", testCircuitBreakFailure),
        ("testURLTemplateDataCall", testURLTemplateDataCall),
        ("testURLTemplateNoParams", testURLTemplateNoParams),
        ("testURLTemplateNoTemplateValues", testURLTemplateNoTemplateValues),
        ("testQueryParamUpdating", testQueryParamUpdating),
        ("testQueryParamUpdatingObject", testQueryParamUpdatingObject),
        ("testQueryTemplateParams", testQueryTemplateParams),
        ("testQueryTemplateParamsObject", testQueryTemplateParamsObject),
    ]
}

#if !os(macOS)
public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(CodableExtensionsTests.__allTests),
        testCase(JSONTests.__allTests),
        testCase(SwiftyRequestTests.__allTests),
    ]
}
#endif
