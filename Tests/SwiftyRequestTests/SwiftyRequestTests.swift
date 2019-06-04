import XCTest
import CircuitBreaker
@testable import SwiftyRequest

#if swift(>=4.1)
  #if canImport(FoundationNetworking)
    import FoundationNetworking
  #endif
#endif

/// URLs for the local test server that these tests use. The TLS certificate
/// provided by this server is a self-signed certificate that will not be
/// trusted by default.
///
/// Note: For testing locally, you must first start the server: build and
/// run the project under TestServer/
///
/// Note also: For testing locally under Linux, you must arrange for the
/// self-signed certificate to be trusted, as Foundation does not yet support
/// trusting self-signed certificates. An example of how to do this can be
/// found under linux/before_tests.sh
let echoURL = "http://localhost:8080/echoJSON"
let echoURLSecure = "https://localhost:8443/ssl/echoJSON"
let jsonURL = "https://localhost:8443/ssl/json"
let jsonArrayURL = "https://localhost:8443/ssl/jsonArray"
let templatedJsonURL = "https://localhost:8443/ssl/json/{name}/{city}/"
let friendsURL = "https://localhost:8443/ssl/friends"
let insecureUrl = "http://localhost:8080/"

/// URL for a well-known server that provides a valid TLS certificate.
let sslValidCertificateURL = "https://swift.org"

// MARK: Helper structs

// The following structs duplicate the types contained within the TestServer
// project that is used as a backend for these tests.
public struct TestData: Codable {
    let name: String
    let age: Int
    let height: Double
    let address: TestAddress
}

public struct TestAddress: Codable {
    let number: Int
    let street: String
    let city: String
}

public struct FriendData: Codable {
    let friends: [String]
}


class SwiftyRequestTests: XCTestCase {

    static var allTests = [
        ("testInsecureConnection", testInsecureConnection),
        ("testEchoData", testEchoData),
        ("testGetValidCert", testGetValidCert),
        //("testGetClientCert", testGetClientCert),
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
        ("testMultipleCookies",testMultipleCookies),
        ("testCookie",testCookie),
        ("testNoCookies",testNoCookies)
    ]

    // Enable logging output for tests
    override func setUp() {
        PrintLogger.use(colored: true)
    }

    // MARK: Helper methods


    let failureFallback = { (error: BreakerError, msg: String) in
        // If this fallback is accessed, we consider it a failure
        if error.description == "BreakerError : An error occurred in an open state. Failing fast." {} else {
            XCTFail("Test opened the circuit and we are in the failure fallback.")
            return
        }
    }

    // MARK: SwiftyRequest Tests

    func testMultipleCookies() {
        let expectation = self.expectation(description: "testtestMultipleCookies")
        let request = RestRequest(method: .get, url:"http://localhost:8080/cookies/2")
        request.credentials = .apiKey
        request.responseData { response in
            switch response.result {
            case .success :
                let cookies = response.cookies?.sorted{ $0.name < $1.name }
                XCTAssertEqual(cookies?.count, 2)
                for no in [0,1] {
                    XCTAssertEqual(cookies?[no].name, "name\(no)")
                    XCTAssertEqual(cookies?[no].value, "value\(no)")
                }
            case .failure(let error):
                XCTFail("Failed to get cookies with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func testCookie() {
        let expectation = self.expectation(description: "testCookie")
        let request = RestRequest(method: .get, url:"http://localhost:8080/cookies/1")
        request.credentials = .apiKey
        request.responseData { response in
            switch response.result {
            case .success :
                let cookies = response.cookies
                XCTAssertEqual(cookies?.count, 1)
                XCTAssertEqual(cookies?[0].name, "name0")
                XCTAssertEqual(cookies?[0].value, "value0")
            case .failure(let error):
                XCTFail("Failed to get cookies with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func testNoCookies() {
        let expectation = self.expectation(description: "testNoCookies")
        let request = RestRequest(method: .get, url:"http://localhost:8080/cookies/0")
        request.credentials = .apiKey
        request.responseData { response in
            switch response.result {
            case .success :
                let cookies = response.cookies
                XCTAssertNil(cookies, "No cookies expected in response but found \(cookies!.count) cookies.")
            case .failure(let error):
                XCTFail("Failed to get data response with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func testInsecureConnection() {
        let expectation = self.expectation(description: "Insecure Connection test")
        
        guard let request = try? RestRequest(method: .GET, url: insecureUrl) else {
            return XCTFail("Invalid URL")
        }
        
        request.response { result in
            switch result {
            case .success(_):
                expectation.fulfill()
            case .failure(let error):
                XCTFail("Could not receive request: \(error)")
            }
        }
        
        waitForExpectations(timeout: 20)
    }
    
    func testEchoData() {
        let expectation = self.expectation(description: "Data Echoed Back")

        let origJson: [String: Any] = ["Hello": "World"]

        guard let data = try? JSONSerialization.data(withJSONObject: origJson, options: []) else {
            XCTFail("Could not encode json")
            return
        }

        guard let request = try? RestRequest(method: .POST, url: echoURL) else {
            return XCTFail("Invalid URL")
        }
        request.messageBody = data

        request.responseData { response in
            switch response {
            case .success(let retval):
                guard let decoded = try? JSONSerialization.jsonObject(with: retval.body, options: []),
                      let json = decoded as? [String: Any] else {
                        XCTFail("Could not decode json")
                        return
                }
                XCTAssertEqual("World", json["Hello"] as? String)
            case .failure(let error):
                XCTFail("Failed to get data response: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 20)
    }

    func testGetValidCert() {
        let expectation = self.expectation(description: "Connection successful")

        guard let request = try? RestRequest(method: .GET, url: sslValidCertificateURL) else {
            return XCTFail("Invalid URL")
        }

        request.responseData { response in
            switch response {
            case .success(let retval):
                XCTAssert(retval.body.count != 0)
            case .failure(let error):
                XCTFail("Failed to get data response: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 20)
    }

//    // TODO: What does this test actually test?
//    // It appears to attach a client certificate
//    // but this is not used / checked anywhere.
//    func testGetClientCert() {
//        #if os(macOS)
//        let expectation = self.expectation(description: "Data Echoed Back")
//        let testClientCertificate = ClientCertificate(name: "server.csr", path: "Tests/SwiftyRequestTests/Certificates")
//        
//        let request = RestRequest(method: .get, url: jsonURL, containsSelfSignedCert: true, clientCertificate: testClientCertificate)
//        
//        request.responseData { response in
//            switch response.result {
//            case .success(let retval):
//                XCTAssert(retval.count != 0)
//            case .failure(let error):
//                XCTFail("Failed to get data response: \(error)")
//            }
//            expectation.fulfill()
//        }
//        
//        waitForExpectations(timeout: 20)
//        #endif
//    }

    func testResponseData() {
        let expectation = self.expectation(description: "responseData SwiftyRequest test")

        guard let request = try? RestRequest(url: jsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        

        request.responseData { response in
            switch response {
            case .success(let retval):
                XCTAssertGreaterThan(retval.body.count, 0)
            case .failure(let error):
                XCTFail("Failed to get JSON response data with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }

    // Tests that a JSONDecodable response can be received
    func testResponseObject() {

        let expectation = self.expectation(description: "responseObject SwiftyRequest test")

        guard let request = try? RestRequest(url: jsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        
        request.acceptType = "application/json"

        request.responseDictionary() { response in
            switch response {
            case .success(let retval):
                XCTAssertGreaterThan(retval.body.count, 0)
            case .failure(let error):
                XCTFail("Failed to get JSON response object with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }

    // Test that URL query parameters are successfully transmitted.
    func testQueryObject() {
        
        let expectation = self.expectation(description: "responseObject SwiftyRequest test")
        
        guard let request = try? RestRequest(url: friendsURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        
        
        request.acceptType = "application/json"
        
        let queryItems = [URLQueryItem(name: "friend", value: "brian"), URLQueryItem(name: "friend", value: "george"), URLQueryItem(name: "friend", value: "melissa+tempe"), URLQueryItem(name: "friend", value: "mika")]
        
        let completionHandler = { (response: Result<RestResponse<FriendData>, Error>) in
            switch response {
            case .success(let retval):
                XCTAssertEqual(retval.body.friends.count, 4)
            case .failure(let error):
                XCTFail("Failed to get friends response object with error: \(error)")
            }
            expectation.fulfill()
        }
        
        request.responseObject(queryItems: queryItems, completionHandler: completionHandler)
        
        waitForExpectations(timeout: 10)
        
    }

    // Tests that a Codable object can be received.
    func testDecodableResponseObject() {
        let expectation = self.expectation(description: "responseObject SwiftyRequest test")

        guard let request = try? RestRequest(url: jsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        
        request.acceptType = "application/json"

        request.responseObject() { (response: Result<RestResponse<TestData>, Error>) in
            switch response {
            case .success(let retval):
                XCTAssertEqual(retval.body.name, "Paddington")
            case .failure(let error):
                XCTFail("Failed to get JSON response object with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    // Test that an array of JSONDecodable responses can be received.
    func testResponseArray() {

        let expectation = self.expectation(description: "responseArray SwiftyRequest test")

        guard let request = try? RestRequest(url: jsonArrayURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        

        request.responseArray() { response in
            switch response {
            case .success(let retval):
                XCTAssertGreaterThan(retval.body.count, 0)
                XCTAssertEqual((retval.body[0] as? [String: Any])?["name"] as? String, "Paddington")
            case .failure(let error):
                XCTFail("Failed to get JSON response array with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }

    func assertCharsetUTF8<T>(response: RestResponse<T>) {
        guard let text = response.headers["Content-Type"].first,
            let regex = try? NSRegularExpression(pattern: "(?<=charset=).*?(?=$|;|\\s)", options: [.caseInsensitive]),
            let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
            let range = Range(match.range, in: text) else {
                XCTFail("Test no longer valid using URL: \(response.host). The charset field was not provided.")
                return
        }

        let str = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespaces))
        if String(str).lowercased() != "utf-8" {
          XCTFail("Test no longer valid using URL: \(response.host). The charset field was not provided.")
        }
    }

    func testResponseString() {

        let expectation = self.expectation(description: "responseString SwiftyRequest test")

        /// Standard
        guard let request1 = try? RestRequest(url:jsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }

        request1.responseString() { response in
            switch response {
            case .success(let result):
                XCTAssertGreaterThan(result.body.count, 0)
            case .failure(let error):
                XCTFail("Failed to get JSON response String with error: \(error)")
            }

            /// Known example of charset=ISO-8859-1
            guard let request2 = try? RestRequest(url: "https://swift.org/") else {
                return XCTFail("Invalid URL")
            }
            request2.responseString() { response in
                switch response {
                case .success(let result):
                    self.assertCharsetUTF8(response: result)
                    XCTAssertGreaterThan(result.body.count, 0)
                case .failure(let error):
                    XCTFail("Failed to get Google response String with error: \(error)")
                }
                expectation.fulfill()
            }

        }

        waitForExpectations(timeout: 10)

    }

    func testResponseVoid() {

        let expectation = self.expectation(description: "responseVoid SwiftyRequest test")

        guard let request = try? RestRequest(url: jsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        

        request.responseVoid() { response in
            switch response {
            case .failure(let error):
                XCTFail("Failed to get JSON response Void with error: \(error)")
            default: ()
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }

    func testFileDownload() {

        let expectation = self.expectation(description: "download file SwiftyRequest test")

        let url = "https://raw.githubusercontent.com/IBM-Swift/SwiftyRequest/c7cfc669a5872831e816d9f9c6fec06bc638222b/Tests/SwiftyRequestTests/test_file.json"

        guard let request = try? RestRequest(url: url) else {
            return XCTFail("Invalid URL")
        }
        

        let bundleURL = URL(fileURLWithPath: "/tmp")
        let destinationURL = bundleURL.appendingPathComponent("tempFile.html")

        request.download(to: destinationURL) { response in
            switch response {
            case .success(let result):
                XCTAssertEqual(result.status.code, 200)
            case .failure(let error):
                XCTFail("Failed download with error: \(error)")
            }

            do {
                // Clean up downloaded file
                let fm = FileManager.default
                try fm.removeItem(at: destinationURL)
            } catch {
                XCTFail("Failed to remove downloaded file with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func testRequestUserAgent() {

        guard let request = try? RestRequest(url: jsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        
        request.productInfo = "swiftyrequest-sdk/0.2.0"
        XCTAssertEqual(request.productInfo, "swiftyrequest-sdk/0.2.0".generateUserAgent())

    }

    // MARK: Circuit breaker integration tests

    func testCircuitBreakResponseString() {

        let expectation = self.expectation(description: "CircuitBreaker success test")

        let circuitParameters = CircuitParameters(fallback: failureFallback)

        guard let request = try? RestRequest(url: jsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        
        request.circuitParameters = circuitParameters

        request.responseString() { response in
            switch response {
            case .success(let result):
                XCTAssertGreaterThan(result.body.count, 0)
            case .failure(let error):
                XCTFail("Failed to get JSON response String with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }

    func testCircuitBreakFailure() {

        let expectation = self.expectation(description: "CircuitBreaker max failure test")
        let name = "circuitName"
        let timeout = 500
        let resetTimeout = 3000
        let maxFailures = 2
        var count = 0
        var fallbackCalled = false

        guard let request = try? RestRequest(url: "http://localhost:12345/blah") else {
            return XCTFail("Invalid URL")
        }

        let breakFallback = { (error: BreakerError, msg: String) in
            /// After maxFailures, the circuit should be open
            if count == maxFailures {
                fallbackCalled = true
                XCTAssert(request.circuitBreaker?.breakerState == .open)
            }
        }

        let circuitParameters = CircuitParameters(name: name, timeout: timeout, resetTimeout: resetTimeout, maxFailures: maxFailures, fallback: breakFallback)

        request.circuitParameters = circuitParameters

        let completionHandler = { (response: (Result<RestResponse<String>, Error>)) in

            if fallbackCalled {
                expectation.fulfill()
            } else {
                count += 1
                XCTAssertLessThanOrEqual(count, maxFailures)
            }
        }

        // Make multiple requests and ensure the correct callbacks are activated
        request.responseString() { response in
            completionHandler(response)

            request.responseString(completionHandler: { response in
                completionHandler(response)

                request.responseString(completionHandler: completionHandler)
                sleep(UInt32(resetTimeout/1000) + 1)
                request.responseString(completionHandler: completionHandler)
            })
        }

        waitForExpectations(timeout: Double(resetTimeout) / 1000 + 10)

    }

    // MARK: Substitution Tests

    func testURLTemplateDataCall() {

        let expectation = self.expectation(description: "URL templating and substitution test")

        let circuitParameters = CircuitParameters(fallback: failureFallback)

        guard let request = try? RestRequest(url: templatedJsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        request.circuitParameters = circuitParameters

        let completionHandlerThree = { (response: (Result<RestResponse<Data>, Error>)) in

            switch response {
            case .success(_):
                XCTFail("Request should have failed with only using one parameter for 2 template spots.")
            case .failure(let error):
                XCTAssertEqual(error as? RestError, RestError.invalidSubstitution)
            }
            expectation.fulfill()
        }

        let completionHandlerTwo = { (response: (Result<RestResponse<Data>, Error>)) in

            switch response {
            case .success(let result):
                XCTAssertGreaterThan(result.body.count, 0)
                let str = String(data: result.body, encoding: String.Encoding.utf8)
                XCTAssertNotNil(str)
                XCTAssertGreaterThan(str!.count, 0)
                // Excluding city from templateParams should cause error
                request.responseData(templateParams: ["name": "Bananaman"], completionHandler: completionHandlerThree)
            case .failure(let error):
                XCTFail("Failed to get JSON response String with error: \(error)")
                expectation.fulfill()
            }
        }

        let completionHandlerOne = { (response: (Result<RestResponse<Data>, Error>)) in
            switch response {
            case .success(let result):
                XCTAssertGreaterThan(result.body.count, 0)
                let str = String(data: result.body, encoding: String.Encoding.utf8)
                XCTAssertNotNil(str)
                XCTAssertGreaterThan(str!.count, 0)

                request.responseData(templateParams: ["name": "Bananaman", "city": "Bananaville"], completionHandler: completionHandlerTwo)
            case .failure(let error):
                XCTFail("Failed to get JSON response String with error: \(error)")
                expectation.fulfill()
            }
        }

        // Test starts here and goes up (this is to avoid excessive nesting of async code)
        // Test basic substitution and multiple substitutions
        request.responseData(templateParams: ["name": "IronMan", "city": "LosAngeles"], completionHandler: completionHandlerOne)

        waitForExpectations(timeout: 10)

    }

    func testURLTemplateNoParams() {

        let expectation = self.expectation(description: "URL substitution test with no substitution params")

        /// With updated CircuitBreaker. This fallback will be called even though the circuit is still closed
        let failureFallback = { (error: BreakerError, msg: String) in
          XCTAssertEqual(error.reason, "unsupported URL")
        }

        let circuitParameters = CircuitParameters(fallback: failureFallback)

        guard let request = try? RestRequest(url: templatedJsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        
        request.circuitParameters = circuitParameters

        request.responseData { response in
            switch response {
            case .success(_):
                XCTFail("Request should have failed with no parameters passed into a templated URL")
            case .failure(let error):
                XCTAssertEqual(error as? RestError, RestError.invalidSubstitution)
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }

    func testURLTemplateNoTemplateValues() {

        let expectation = self.expectation(description: "URL substitution test with no template values to replace, API call should still succeed")

        let circuitParameters = CircuitParameters(fallback: failureFallback)

        guard let request = try? RestRequest(url: jsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        
        request.circuitParameters = circuitParameters

        request.responseData(templateParams: ["name": "Bananaman", "city": "Bananaville"]) { response in
            switch response {
            case .success(let retVal):
                XCTAssertGreaterThan(retVal.body.count, 0)
            case .failure(let error):
                XCTFail("Failed to get JSON response data with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }

    // MARK: Query parameter tests

    func testQueryParamUpdating() {

        let expectation = self.expectation(description: "Test setting, modifying, and removing URL query parameters")

        let circuitParameters = CircuitParameters(timeout: 3000, fallback: failureFallback)
        let initialQueryItems = [URLQueryItem(name: "friend", value: "bill")]

        guard let request = try? RestRequest(url: friendsURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        
        request.circuitParameters = circuitParameters

        // verify query has many parameters
        let completionHandlerFour = { (response: (Result<RestResponse<Data>, Error>)) in
            switch response {
            case .success(let result):
                XCTAssertGreaterThan(result.body.count, 0)
                XCTAssertNotNil(result.request.url.query)
                if let queryItems = result.request.url.query {
                    XCTAssertEqual(queryItems, "friend=brian&friend=george&friend=melissa%2Btempe&friend=mika")
                }
            case .failure(let error):
                XCTFail("Failed to get weather response data with error: \(error)")
            }
            expectation.fulfill()
        }

        // verify query was set to nil
        let completionHandlerThree = { (response: (Result<RestResponse<Data>, Error>)) in
            switch response {
            case .success(let result):
                XCTAssertGreaterThan(result.body.count, 0)
                XCTAssertNil(result.request.url.query)
                let queryItems = [URLQueryItem(name: "friend", value: "brian"), URLQueryItem(name: "friend", value: "george"), URLQueryItem(name: "friend", value: "melissa+tempe"), URLQueryItem(name: "friend", value: "mika")]
                request.responseData(queryItems: queryItems, completionHandler: completionHandlerFour)
            case .failure(let error):
                XCTFail("Failed to get weather response data with error: \(error)")
            }
        }

        // verify query value changed and was encoded properly
        let completionHandlerTwo = { (response: (Result<RestResponse<Data>, Error>)) in
            switch response {
            case .success(let result):
                XCTAssertGreaterThan(result.body.count, 0)
                XCTAssertNotNil(result.request.url.query)
                if let queryItems = result.request.url.query {
                    XCTAssertEqual(queryItems, "friend=darren%2Bfink")
                }
                // Explicitly remove query items before next request
                request.queryItems = nil
                request.responseData(completionHandler: completionHandlerThree)
            case .failure(let error):
                XCTFail("Failed to get weather response data with error: \(error)")
            }
        }

        // verfiy query value could be set
        let completionHandlerOne = { (response: (Result<RestResponse<Data>, Error>)) in
            switch response {
            case .success(let retVal):
                XCTAssertGreaterThan(retVal.body.count, 0)
                XCTAssertNotNil(retVal.request.url.query)
                if let queryItems = retVal.request.url.query {
                    XCTAssertEqual(queryItems, "friend=bill")
                }

                request.responseData(queryItems: [URLQueryItem(name: "friend", value: "darren+fink")], completionHandler: completionHandlerTwo)
            case .failure(let error):
                XCTFail("Failed to get weather response data with error: \(error)")
            }
        }

        // Set the query items for subsequent requests
        request.queryItems = initialQueryItems

        // Do not explicitly pass `queryItems` - current configuration should be picked up
        request.responseData(completionHandler: completionHandlerOne)

        waitForExpectations(timeout: 10)

    }
    
    func testQueryParamUpdatingObject() {
        
        let expectation = self.expectation(description: "Test setting, modifying, and removing URL query parameters")
        
        let circuitParameters = CircuitParameters(timeout: 3000, fallback: failureFallback)
        let initialQueryItems = [URLQueryItem(name: "friend", value: "bill")]
        
        guard let request = try? RestRequest(url: friendsURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        request.circuitParameters = circuitParameters
        
        // verify query has many parameters
        let completionHandlerFour = { (response: (Result<RestResponse<FriendData>, Error>)) in
            switch response {
            case .success(let result):
                XCTAssertEqual(result.body.friends.count, 4)
            case .failure(let error):
                XCTFail("Failed to get friends response data with error: \(error)")
            }
            expectation.fulfill()
        }
        
        // verify query was set to nil
        let completionHandlerThree = { (response: (Result<RestResponse<FriendData>, Error>)) in
            switch response {
            case .success(let result):
                XCTAssertEqual(result.body.friends.count, 0)
                let queryItems = [URLQueryItem(name: "friend", value: "brian"), URLQueryItem(name: "friend", value: "george"), URLQueryItem(name: "friend", value: "melissa+tempe"), URLQueryItem(name: "friend", value: "mika")]
                request.responseObject(queryItems: queryItems, completionHandler: completionHandlerFour)
            case .failure(let error):
                XCTFail("Failed to get friends response data with error: \(error)")
                expectation.fulfill()
            }
        }
        
        // verify query value changed and was encoded properly
        let completionHandlerTwo = { (response: (Result<RestResponse<FriendData>, Error>)) in
            switch response {
            case .success(let result):
                XCTAssertEqual(result.body.friends.count, 1)
                // Explicitly remove query items before next request
                request.queryItems = nil
                request.responseObject(completionHandler: completionHandlerThree)
            case .failure(let error):
                XCTFail("Failed to get friends response data with error: \(error)")
                expectation.fulfill()
            }
        }
        
        // verfiy query value could be set
        let completionHandlerOne = { (response: (Result<RestResponse<FriendData>, Error>)) in
            switch response {
            case .success(let retVal):
                XCTAssertEqual(retVal.body.friends.count, 1)
                request.responseObject(queryItems: [URLQueryItem(name: "friend", value: "darren+fink")], completionHandler: completionHandlerTwo)
            case .failure(let error):
                XCTFail("Failed to get friends response data with error: \(error)")
                expectation.fulfill()
            }
        }
        
        // Set the query items for subsequent requests
        request.queryItems = initialQueryItems

        // Do not explicitly pass `queryItems` - current configuration should be picked up
        request.responseObject(completionHandler: completionHandlerOne)
        
        waitForExpectations(timeout: 10)
        
    }

    func testQueryTemplateParams() {

        let expectation = self.expectation(description: "Testing URL template and query parameters used together")

        let circuitParameters = CircuitParameters(fallback: failureFallback)

        guard let request = try? RestRequest(url: templatedJsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        
        request.circuitParameters = circuitParameters

        request.responseData(templateParams: ["name": "Bananaman", "city": "Bananaville"], queryItems: [URLQueryItem(name: "friend", value: "bill")]) { response in
            switch response {
            case .success(let retVal):
                XCTAssertGreaterThan(retVal.body.count, 0)
            case .failure(let error):
                XCTFail("Failed to get JSON response data with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }
    
    func testQueryTemplateParamsObject() {
        
        let expectation = self.expectation(description: "Testing URL template and query parameters used together")
        
        let circuitParameters = CircuitParameters(fallback: failureFallback)
        
        guard let request = try? RestRequest(url: templatedJsonURL, containsSelfSignedCert: true) else {
            return XCTFail("Invalid URL")
        }
        
        request.circuitParameters = circuitParameters
        
        let templateParams: [String: String] = ["name": "Bananaman", "city": "Bananaville"]
        
        let queryItems = [URLQueryItem(name: "friend", value: "bill")]
        
        let completionHandler = { (response: (Result<RestResponse<TestData>, Error>)) in
            switch response {
            case .success(let retVal):
                XCTAssertEqual(retVal.body.name, "Bananaman")
            case .failure(let error):
                XCTFail("Failed to get JSON response data with error: \(error)")
            }
            expectation.fulfill()
        }
        
        request.responseObject(templateParams: templateParams, queryItems: queryItems, completionHandler: completionHandler)
 
        waitForExpectations(timeout: 10)
        
    }

}
