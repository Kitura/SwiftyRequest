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
let sslValidCertificateURL = "https://www.google.com"

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

// Struct to hold arbitrary JSON response
public struct JSONResponse: JSONDecodable {
    public let json: [String: Any]
    public init(json: JSONWrapper) throws {
        self.json = try json.getDictionaryObject()
    }
}

class SwiftyRequestTests: XCTestCase {

    static var allTests = [
        ("testInsecureConnection", testInsecureConnection),
        ("testEchoData", testEchoData),
        ("testGetValidCert", testGetValidCert),
        ("testGetClientCert", testGetClientCert),
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

    private func responseToError(response: HTTPURLResponse?, data: Data?) -> Error? {

        // First check http status code in response
        if let response = response {
            if response.statusCode >= 200 && response.statusCode < 300 {
                return nil
            }
        }

        // ensure data is not nil
        guard let data = data else {
            if let code = response?.statusCode {
                print("Data is nil with response code: \(code)")
                return RestError.noData
            }
            return nil  // SwiftyRequest will generate error for this case
        }

        do {
            let json = try JSONWrapper(data: data)
            let message = try json.getString(at: "error")
            print("Failed with error: \(message)")
            return RestError.serializationError
        } catch {
            return nil
        }
    }

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
                let cookies = response.cookies
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
                XCTAssertNil(cookies, "No cookies expected in response but found \(cookies?.count) cookies.")
            case .failure(let error):
                XCTFail("Failed to get data response with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func testInsecureConnection() {
        let expectation = self.expectation(description: "Insecure Connection test")
        
        let request = RestRequest(method: .get, url: insecureUrl)
        
        request.response { (data, response, error) in
            if error != nil {
                XCTFail("Could not receive request")
            }
            expectation.fulfill()
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

        let request = RestRequest(method: .post, url: echoURL)
        request.messageBody = data

        request.responseData { response in
            switch response.result {
            case .success(let retval):
                guard let decoded = try? JSONSerialization.jsonObject(with: retval, options: []),
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

        let request = RestRequest(method: .get, url: sslValidCertificateURL)

        request.responseData { response in
            switch response.result {
            case .success(let retval):
                XCTAssert(retval.count != 0)
            case .failure(let error):
                XCTFail("Failed to get data response: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 20)
    }

    // TODO: What does this test actually test?
    // It appears to attach a client certificate
    // but this is not used / checked anywhere.
    func testGetClientCert() {
        #if os(macOS)
        let expectation = self.expectation(description: "Data Echoed Back")
        let testClientCertificate = ClientCertificate(name: "server.csr", path: "Tests/SwiftyRequestTests/Certificates")
        
        let request = RestRequest(method: .get, url: jsonURL, containsSelfSignedCert: true, clientCertificate: testClientCertificate)
        
        request.responseData { response in
            switch response.result {
            case .success(let retval):
                XCTAssert(retval.count != 0)
            case .failure(let error):
                XCTFail("Failed to get data response: \(error)")
            }
            expectation.fulfill()
        }
        
        waitForExpectations(timeout: 20)
        #endif
    }

    func testResponseData() {
        let expectation = self.expectation(description: "responseData SwiftyRequest test")

        let request = RestRequest(url: jsonURL, containsSelfSignedCert: true)
        request.credentials = .apiKey

        request.responseData { response in
            switch response.result {
            case .success(let retval):
                XCTAssertGreaterThan(retval.count, 0)
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

        let request = RestRequest(url: jsonURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.acceptType = "application/json"

        request.responseObject(responseToError:  responseToError) { (response: RestResponse<JSONResponse>) in
            switch response.result {
            case .success(let retval):
                XCTAssertGreaterThan(retval.json.count, 0)
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
        
        let request = RestRequest(url: friendsURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.acceptType = "application/json"
        
        let queryItems = [URLQueryItem(name: "friend", value: "brian"), URLQueryItem(name: "friend", value: "george"), URLQueryItem(name: "friend", value: "melissa+tempe"), URLQueryItem(name: "friend", value: "mika")]
        
        let completionHandler = { (response: RestResponse<FriendData>) in
            switch response.result {
            case .success(let retval):
                XCTAssertEqual(retval.friends.count, 4)
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

        let request = RestRequest(url: jsonURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.acceptType = "application/json"

        request.responseObject(responseToError:  responseToError) { (response: RestResponse<TestData>) in
            switch response.result {
            case .success(let retval):
                XCTAssertEqual(retval.name, "Paddington")
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

        let request = RestRequest(url: jsonArrayURL, containsSelfSignedCert: true)
        request.credentials = .apiKey

        request.responseArray(responseToError: responseToError,
                              path: []) { (response: RestResponse<[JSONResponse]>) in
            switch response.result {
            case .success(let retval):
                XCTAssertGreaterThan(retval.count, 0)
                XCTAssertEqual(retval[0].json["name"] as? String, "Paddington")
            case .failure(let error):
                XCTFail("Failed to get JSON response array with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }

    func assertCharsetISO8859(response: HTTPURLResponse?) {
        guard let text = response?.allHeaderFields["Content-Type"] as? String,
            let regex = try? NSRegularExpression(pattern: "(?<=charset=).*?(?=$|;|\\s)", options: [.caseInsensitive]),
            let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
            let range = Range(match.range, in: text) else {
                XCTFail("Test no longer valid using URL: \(response?.url?.absoluteString ?? ""). The charset field was not provided.")
                return
        }

        let str = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespaces))
        if String(str).lowercased() != "iso-8859-1" {
          XCTFail("Test no longer valid using URL: \(response?.url?.absoluteString ?? ""). The charset field was not provided.")
        }
    }

    func testResponseString() {

        let expectation = self.expectation(description: "responseString SwiftyRequest test")

        /// Standard
        let request1 = RestRequest(url:jsonURL, containsSelfSignedCert: true)
        request1.credentials = .apiKey

        request1.responseString(responseToError: responseToError) { response in
            switch response.result {
            case .success(let result):
                XCTAssertGreaterThan(result.count, 0)
            case .failure(let error):
                XCTFail("Failed to get JSON response String with error: \(error)")
            }

            /// Known example of charset=ISO-8859-1
            let request2 = RestRequest(url: "http://google.com/")
            request2.responseString(responseToError: self.responseToError) { response in
                self.assertCharsetISO8859(response: response.response)
                switch response.result {
                case .success(let result):
                    XCTAssertGreaterThan(result.count, 0)
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

        let request = RestRequest(url: jsonURL, containsSelfSignedCert: true)
        request.credentials = .apiKey

        request.responseVoid(responseToError: responseToError) { response in
            switch response.result {
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

        let request = RestRequest(url: url)
        request.credentials = .apiKey

        let bundleURL = URL(fileURLWithPath: "/tmp")
        let destinationURL = bundleURL.appendingPathComponent("tempFile.html")

        request.download(to: destinationURL) { response, error in
            XCTAssertNil(error) // if error not nil, url may point to missing resource
            XCTAssertNotNil(response)
            XCTAssertEqual(response?.statusCode, 200)

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

        let expectation = self.expectation(description: "responseString SwiftyRequest test with userAgent string")

        let request = RestRequest(url: jsonURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.productInfo = "swiftyrequest-sdk/0.2.0"

        request.responseString(responseToError: responseToError) { response in

            XCTAssertNotNil(response.request?.allHTTPHeaderFields)
            if let headers = response.request?.allHTTPHeaderFields {
                XCTAssertNotNil(headers["User-Agent"])
                XCTAssertEqual(headers["User-Agent"], "swiftyrequest-sdk/0.2.0".generateUserAgent())
            }

            switch response.result {
            case .success(let result):
                XCTAssertGreaterThan(result.count, 0)
            case .failure(let error):
                XCTFail("Failed to get JSON response String with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }

    // MARK: Circuit breaker integration tests

    func testCircuitBreakResponseString() {

        let expectation = self.expectation(description: "CircuitBreaker success test")

        let circuitParameters = CircuitParameters(fallback: failureFallback)

        let request = RestRequest(url: jsonURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.circuitParameters = circuitParameters

        request.responseString(responseToError: responseToError) { response in
            switch response.result {
            case .success(let result):
                XCTAssertGreaterThan(result.count, 0)
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
        let timeout = 5000
        let resetTimeout = 3000
        let maxFailures = 2
        var count = 0
        var fallbackCalled = false

        let request = RestRequest(url: "http://localhost:12345/blah")

        let breakFallback = { (error: BreakerError, msg: String) in
            /// After maxFailures, the circuit should be open
            if count == maxFailures {
                fallbackCalled = true
                assert(request.circuitBreaker?.breakerState == .open)
            }
        }

        let circuitParameters = CircuitParameters(name: name, timeout: timeout, resetTimeout: resetTimeout, maxFailures: maxFailures, fallback: breakFallback)

        request.credentials = .apiKey
        request.circuitParameters = circuitParameters

        let completionHandler = { (response: (RestResponse<String>)) in

            if fallbackCalled {
                expectation.fulfill()
            } else {
                count += 1
                XCTAssertLessThanOrEqual(count, maxFailures)
            }
        }

        // Make multiple requests and ensure the correct callbacks are activated
        request.responseString(responseToError: responseToError) { [unowned self] (response: RestResponse<String>) in
            completionHandler(response)

            request.responseString(responseToError: self.responseToError, completionHandler: { [unowned self] (response: RestResponse<String>) in
                completionHandler(response)

                request.responseString(responseToError: self.responseToError, completionHandler: completionHandler)
                sleep(UInt32(resetTimeout/1000) + 1)
                request.responseString(responseToError: self.responseToError, completionHandler: completionHandler)
            })
        }

        waitForExpectations(timeout: Double(resetTimeout) / 1000 + 10)

    }

    // MARK: Substitution Tests

    func testURLTemplateDataCall() {

        let expectation = self.expectation(description: "URL templating and substitution test")

        let circuitParameters = CircuitParameters(fallback: failureFallback)

        let request = RestRequest(url: templatedJsonURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.circuitParameters = circuitParameters

        let completionHandlerThree = { (response: (RestResponse<Data>)) in

            switch response.result {
            case .success(_):
                XCTFail("Request should have failed with only using one parameter for 2 template spots.")
            case .failure(let error):
                XCTAssertEqual(error.localizedDescription, RestError.invalidSubstitution.localizedDescription)
            }
            expectation.fulfill()
        }

        let completionHandlerTwo = { (response: (RestResponse<Data>)) in

            switch response.result {
            case .success(let result):
                XCTAssertGreaterThan(result.count, 0)
                let str = String(data: result, encoding: String.Encoding.utf8)
                XCTAssertNotNil(str)
                XCTAssertGreaterThan(str!.count, 0)
                // Excluding city from templateParams should cause error
                request.responseData(templateParams: ["name": "Bananaman"], completionHandler: completionHandlerThree)
            case .failure(let error):
                XCTFail("Failed to get JSON response String with error: \(error)")
                expectation.fulfill()
            }
        }

        let completionHandlerOne = { (response: (RestResponse<Data>)) in
            switch response.result {
            case .success(let result):
                XCTAssertGreaterThan(result.count, 0)
                let str = String(data: result, encoding: String.Encoding.utf8)
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
        request.responseData(templateParams: ["name": "Iron%20Man", "city": "Los%20Angeles"], completionHandler: completionHandlerOne)

        waitForExpectations(timeout: 10)

    }

    func testURLTemplateNoParams() {

        let expectation = self.expectation(description: "URL substitution test with no substitution params")

        /// With updated CircuitBreaker. This fallback will be called even though the circuit is still closed
        let failureFallback = { (error: BreakerError, msg: String) in
          XCTAssertEqual(error.reason, "unsupported URL")
        }

        let circuitParameters = CircuitParameters(fallback: failureFallback)

        let request = RestRequest(url: templatedJsonURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.circuitParameters = circuitParameters

        request.responseData { response in
            switch response.result {
            case .success(_):
                XCTFail("Request should have failed with no parameters passed into a templated URL")
            case .failure(let error):
                XCTAssertEqual(error.localizedDescription, "unsupported URL")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }

    func testURLTemplateNoTemplateValues() {

        let expectation = self.expectation(description: "URL substitution test with no template values to replace, API call should still succeed")

        let circuitParameters = CircuitParameters(fallback: failureFallback)

        let request = RestRequest(url: jsonURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.circuitParameters = circuitParameters

        request.responseData(templateParams: ["name": "Bananaman", "city": "Bananaville"]) { response in
            switch response.result {
            case .success(let retVal):
                XCTAssertGreaterThan(retVal.count, 0)
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

        let request = RestRequest(url: friendsURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.circuitParameters = circuitParameters

        // verify query has many parameters
        let completionHandlerFour = { (response: (RestResponse<Data>)) in
            switch response.result {
            case .success(let result):
                XCTAssertGreaterThan(result.count, 0)
                XCTAssertNotNil(response.request?.url?.query)
                if let queryItems = response.request?.url?.query {
                    XCTAssertEqual(queryItems, "friend=brian&friend=george&friend=melissa%2Btempe&friend=mika")
                }
            case .failure(let error):
                XCTFail("Failed to get weather response data with error: \(error)")
            }
            expectation.fulfill()
        }

        // verify query was set to nil
        let completionHandlerThree = { (response: (RestResponse<Data>)) in
            switch response.result {
            case .success(let result):
                XCTAssertGreaterThan(result.count, 0)
                XCTAssertNil(response.request?.url?.query)
                let queryItems = [URLQueryItem(name: "friend", value: "brian"), URLQueryItem(name: "friend", value: "george"), URLQueryItem(name: "friend", value: "melissa+tempe"), URLQueryItem(name: "friend", value: "mika")]
                request.responseData(queryItems: queryItems, completionHandler: completionHandlerFour)
            case .failure(let error):
                XCTFail("Failed to get weather response data with error: \(error)")
            }
        }

        // verify query value changed and was encoded properly
        let completionHandlerTwo = { (response: (RestResponse<Data>)) in
            switch response.result {
            case .success(let result):
                XCTAssertGreaterThan(result.count, 0)
                XCTAssertNotNil(response.request?.url?.query)
                if let queryItems = response.request?.url?.query {
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
        let completionHandlerOne = { (response: (RestResponse<Data>)) in
            switch response.result {
            case .success(let retVal):
                XCTAssertGreaterThan(retVal.count, 0)
                XCTAssertNotNil(response.request?.url?.query)
                if let queryItems = response.request?.url?.query {
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
        
        let request = RestRequest(url: friendsURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.circuitParameters = circuitParameters
        
        // verify query has many parameters
        let completionHandlerFour = { (response: (RestResponse<FriendData>)) in
            switch response.result {
            case .success(let result):
                XCTAssertEqual(result.friends.count, 4)
                XCTAssertNotNil(response.request?.url?.query)
                if let queryItems = response.request?.url?.query {
                    XCTAssertEqual(queryItems, "friend=brian&friend=george&friend=melissa%2Btempe&friend=mika")
                }
            case .failure(let error):
                XCTFail("Failed to get friends response data with error: \(error)")
            }
            expectation.fulfill()
        }
        
        // verify query was set to nil
        let completionHandlerThree = { (response: (RestResponse<FriendData>)) in
            switch response.result {
            case .success(let result):
                XCTAssertEqual(result.friends.count, 0)
                XCTAssertNil(response.request?.url?.query)
                let queryItems = [URLQueryItem(name: "friend", value: "brian"), URLQueryItem(name: "friend", value: "george"), URLQueryItem(name: "friend", value: "melissa+tempe"), URLQueryItem(name: "friend", value: "mika")]
                request.responseObject(queryItems: queryItems, completionHandler: completionHandlerFour)
            case .failure(let error):
                XCTFail("Failed to get friends response data with error: \(error)")
                expectation.fulfill()
            }
        }
        
        // verify query value changed and was encoded properly
        let completionHandlerTwo = { (response: (RestResponse<FriendData>)) in
            switch response.result {
            case .success(let result):
                XCTAssertEqual(result.friends.count, 1)
                XCTAssertNotNil(response.request?.url?.query)
                if let queryItems = response.request?.url?.query {
                    XCTAssertEqual(queryItems, "friend=darren%2Bfink")
                }
                // Explicitly remove query items before next request
                request.queryItems = nil
                request.responseObject(completionHandler: completionHandlerThree)
            case .failure(let error):
                XCTFail("Failed to get friends response data with error: \(error)")
                expectation.fulfill()
            }
        }
        
        // verfiy query value could be set
        let completionHandlerOne = { (response: (RestResponse<FriendData>)) in
            switch response.result {
            case .success(let retVal):
                XCTAssertEqual(retVal.friends.count, 1)
                XCTAssertNotNil(response.request?.url?.query)
                if let queryItems = response.request?.url?.query {
                    XCTAssertEqual(queryItems, "friend=bill")
                }
                
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

        let request = RestRequest(url: templatedJsonURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.circuitParameters = circuitParameters

        request.responseData(templateParams: ["name": "Bananaman", "city": "Bananaville"], queryItems: [URLQueryItem(name: "friend", value: "bill")]) { response in
            switch response.result {
            case .success(let retVal):
                XCTAssertGreaterThan(retVal.count, 0)
                XCTAssertNotNil(response.request?.url?.query)
                if let queryItems = response.request?.url?.query {
                    XCTAssertEqual(queryItems, "friend=bill")
                }
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
        
        let request = RestRequest(url: templatedJsonURL, containsSelfSignedCert: true)
        request.credentials = .apiKey
        request.circuitParameters = circuitParameters
        
        let templateParams: [String: String] = ["name": "Bananaman", "city": "Bananaville"]
        
        let queryItems = [URLQueryItem(name: "friend", value: "bill")]
        
        let completionHandler = { (response: (RestResponse<TestData>)) in
            switch response.result {
            case .success(let retVal):
                XCTAssertEqual(retVal.name, "Bananaman")
                XCTAssertNotNil(response.request?.url?.query)
                if let queryItems = response.request?.url?.query {
                    XCTAssertEqual(queryItems, "friend=bill")
                }
            case .failure(let error):
                XCTFail("Failed to get JSON response data with error: \(error)")
            }
            expectation.fulfill()
        }
        
        request.responseObject(templateParams: templateParams, queryItems: queryItems, completionHandler: completionHandler)
 
        waitForExpectations(timeout: 10)
        
    }

}
