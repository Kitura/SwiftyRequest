import XCTest
import CircuitBreaker
import NIOSSL
import NIO
import AsyncHTTPClient
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
let echoArrayURL = "http://localhost:8080/echoJSONArray"
let echoURLSecure = "https://localhost:8443/ssl/echoJSON"
let jsonURL = "https://localhost:8443/ssl/json"
let jsonArrayURL = "https://localhost:8443/ssl/jsonArray"
let templatedJsonURL = "https://localhost:8443/ssl/json/{name}/{city}/"
let friendsURL = "https://localhost:8443/ssl/friends"
let insecureUrl = "http://localhost:8080/"
let cookiesURL = "http://localhost:8080/cookies/{numCookies}"

let basicAuthUserURL = "https://localhost:8443/ssl/basic/user/{id}"
let jwtAuthUserURL = "https://localhost:8443/ssl/jwt/user"
let jwtGenerateURL = "https://localhost:8443/ssl/jwt/generateJWT"

/// URL for a well-known server that provides a valid TLS certificate.
let sslValidCertificateURL = "https://swift.org"

class SwiftyRequestTests: XCTestCase {

    static var allTests = [
        ("testInsecureConnection", testInsecureConnection),
        ("testEchoDictionary", testEchoDictionary),
        ("testEchoArray", testEchoArray),
        ("testGetValidCert", testGetValidCert),
        ("testClientCertificate", testClientCertificate),
        ("testClientCertificateFileUnencrypted", testClientCertificateFileUnencrypted),
        ("testClientCertificateMissingPassphrase", testClientCertificateMissingPassphrase),
        ("testResponseData", testResponseData),
        ("testResponseJSONDictionary", testResponseJSONDictionary),
        ("testQueryObject", testQueryObject),
        ("testResponseJSONArray", testResponseJSONArray),
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
        ("testNoCookies",testNoCookies),
        ("testBasicAuthentication", testBasicAuthentication),
        ("testBasicAuthenticationFails", testBasicAuthenticationFails),
        ("testTokenAuthentication", testTokenAuthentication),
        ("testHeaders", testHeaders),
        ("testEventLoopGroup", testEventLoopGroup),
        ("testRequestTimeout", testRequestTimeout),
//        ("testConnectTimeout", testConnectTimeout),
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

    // MARK: Cookies tests

    func testMultipleCookies() {
        let expectation = self.expectation(description: "Test multiple cookies are received")

        let request = RestRequest(method: .get, url: cookiesURL)

        request.response(templateParams: ["numCookies": "2"]) { result in
            switch result {
            case .success(let response):
                let cookies = response.cookies.sorted{ $0.name < $1.name }
                XCTAssertEqual(cookies.count, 2)
                for no in 0..<cookies.count {
                    XCTAssertEqual(cookies[no].name, "name\(no)")
                    XCTAssertEqual(cookies[no].value, "value\(no)")
                }
            case .failure(let error):
                XCTFail("Failed to get cookies with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func testCookie() {
        let expectation = self.expectation(description: "Test a single cookie is received")

        let request = RestRequest(method: .get, url: cookiesURL)

        request.response(templateParams: ["numCookies": "1"]) { result in
            switch result {
            case .success(let response):
                let cookies = response.cookies
                XCTAssertEqual(cookies.count, 1)
                if cookies.count > 0 {
                    XCTAssertEqual(cookies[0].name, "name0")
                    XCTAssertEqual(cookies[0].value, "value0")
                }
            case .failure(let error):
                XCTFail("Failed to get cookies with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func testNoCookies() {
        let expectation = self.expectation(description: "Test no cookies are received")

        let request = RestRequest(method: .get, url: cookiesURL)

        request.response(templateParams: ["numCookies": "0"]) { result in
            switch result {
            case .success(let response):
                let cookies = response.cookies
                XCTAssertEqual(cookies.count, 0, "No cookies expected in response but found \(cookies.count) cookies.")
            case .failure(let error):
                XCTFail("Failed to get data response with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    // MARK: Basic SwiftyRequest Tests

    func testInsecureConnection() {
        let expectation = self.expectation(description: "Insecure Connection test")
        
        let request = RestRequest(method: .get, url: insecureUrl)
        
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

    // Tests that a JSON dictionary can be echoed back and is intact.
    func testEchoDictionary() {
        let expectation = self.expectation(description: "Data Echoed Back")

        let origJson: [String: Any] = ["Hello": "World", "Items": [1, 2, 3]]
        let request = RestRequest(method: .post, url: echoURL)
        request.contentType = "application/json"
        request.acceptType = "application/json"
        request.messageBodyDictionary = origJson

        request.responseDictionary { result in
            switch result {
            case .success(let response):
                XCTAssertEqual("World", response.body["Hello"] as? String)
                guard let items = response.body["Items"] as? [Int] else {
                    return XCTFail()
                }
                XCTAssertEqual(items.first, 1)
                XCTAssertEqual(items.last, 3)
            case .failure(let error):
                XCTFail("Failed to get data response: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 20)
    }

    // Tests that a JSON dictionary can be echoed back and is intact.
    func testEchoArray() {
        let expectation = self.expectation(description: "Data Echoed Back")

        let origJson: [Any] = ["Hello", "Swift", "World"]
        let request = RestRequest(method: .post, url: echoArrayURL)
        request.contentType = "application/json"
        request.acceptType = "application/json"
        request.messageBodyArray = origJson

        request.responseArray { result in
            switch result {
            case .success(let response):
                XCTAssertEqual(response.body.first as? String, "Hello")
                XCTAssertEqual(response.body.last as? String, "World")
            case .failure(let error):
                XCTFail("Failed to get data response: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 20)
    }

    // Tests that an SSL connection can be successfully made to a URL that provides
    // a valid certificate.
    func testGetValidCert() {
        let expectation = self.expectation(description: "Connection successful")

        let request = RestRequest(method: .get, url: sslValidCertificateURL)

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

    // MARK: Client certificate tests

    // Test that we can make a request supplying a client certificate.
    //
    // To test this facility, we make a request to badssl.com's client certificate
    // verification URL. We need a client certificate to do this, and badssl provide
    // one that we can download in PEM format. The PEM contains the certificate and
    // a private key encrypted with the passphrase 'badssl.com'.
    // We download the PEM file, extract the client certificate and private key,
    // then provide these when making our request to 'client.badssl.com'. If the
    // client certificate was successfully supplied, we'll get a successful response.
    func testClientCertificate() {
        let expectation = self.expectation(description: "Successfully supplied Client Certificate")

        // URL that requires a client certificate to be supplied
        let clientURL = "https://client.badssl.com/"
        // Download URL for badssl.com client certificate (we must download this each time, because it will expire and be reissued)
        let certificateURL = "https://badssl.com/certs/badssl.com-client.pem"
        // Password for the private key for the client certificate
        let privateKeyPassword = "badssl.com"

        // Download client certificate from badssl.com
        let pemRequest = RestRequest(method: .get, url: certificateURL)

        pemRequest.responseData { result in
            switch result {
            case .success(let response):
                // Read the response (pem file) and convert to a [UInt8]
                let pemData = response.body
                do {
                    let certificate = try ClientCertificate(pemData: pemData, passphrase: privateKeyPassword)

                    // Make request to badssl.com that expects the client certificate to be supplied
                    let request = RestRequest(method: .get, url: clientURL, clientCertificate: certificate)

                    request.responseString { result in
                        switch result {
                        case .success(let response):
                            XCTAssertEqual(response.status, .ok)
                        case .failure(let error):
                            XCTFail("Failed to make request supplying client certificate: \(error)")
                        }
                        expectation.fulfill()
                    }
                } catch {
                    XCTFail("Error decoding certificate: \(error)")
                    expectation.fulfill()
                }
            case .failure(let error):
                XCTFail("Failed to get certificate data: \(error)")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 20)
    }

    /// Test that we are unable to load a certificate and encrypted private key from a PEM file when
    /// the required passphrase is not specified.
    func testClientCertificateMissingPassphrase() {
        // URL of Tests/SwiftyRequestTests directory
        let testDirectoryURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
        // File containing certificate and unencrypted private key
        let relativePath = "Certificates/badssl.com-client.pem"
        // Absolute file path of PEM file
        let filePath = testDirectoryURL.appendingPathComponent(relativePath).path

        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))
        do {
            // ClientCertificate will throw if the certificate and key cannot be extracted
            // from the given file.
            _ = try ClientCertificate(pemFile: filePath)
            XCTFail("Expected ClientCertificate creation to fail, no passphrase provided")
        } catch let error as NIOSSLError {
            XCTAssertEqual(error, .failedToLoadPrivateKey)
        } catch {
            XCTFail("Error was \(error), expected NIOSSLError.failedToLoadPrivateKey")
        }
    }

    /// Test that we are able to load a certificate and unencrypted private key from a PEM file.
    /// No passphrase is supplied when creating the ClientCertificate.
    /// Note that we do not test that we can make a request using this certificate, as we are
    /// storing it locally and it could have expired.  We simply test that the key can be consumed
    /// by NIOSSL.
    func testClientCertificateFileUnencrypted() {
        // URL of Tests/SwiftyRequestTests directory
        let testDirectoryURL = URL(fileURLWithPath: #file).deletingLastPathComponent()
        // File containing certificate and unencrypted private key
        let relativePath = "Certificates/badssl.com-nopwd.pem"
        // Absolute file path of PEM file
        let filePath = testDirectoryURL.appendingPathComponent(relativePath).path

        XCTAssertTrue(FileManager.default.fileExists(atPath: filePath))
        do {
            // ClientCertificate will throw if the certificate and key cannot be extracted
            // from the given file.
            _ = try ClientCertificate(pemFile: filePath)
        } catch {
            XCTFail("Error decoding PEM file: \(error)")
        }
    }

    // MARK: SwiftyRequest Response tests

    // Tests that Data can successfully be received.
    func testResponseData() {
        let expectation = self.expectation(description: "Data can be received")

        let request = RestRequest(url: jsonURL, insecure: true)

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

    // Tests that a JSON response can be received and decoded to a [String:Any] dictionary.
    func testResponseJSONDictionary() {
        let expectation = self.expectation(description: "JSON can be received and decoded into a [String:Any] dictionary")

        let request = RestRequest(url: jsonURL, insecure: true)
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
        
        let request = RestRequest(url: friendsURL, insecure: true)
        request.acceptType = "application/json"
        
        let queryItems = [URLQueryItem(name: "friend", value: "brian"), URLQueryItem(name: "friend", value: "george"), URLQueryItem(name: "friend", value: "melissa+tempe"), URLQueryItem(name: "friend", value: "mika")]
        
        let completionHandler = { (response: Result<RestResponse<FriendData>, RestError>) in
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
        let expectation = self.expectation(description: "JSON can be received and decoded into a Struct")

        let request = RestRequest(url: jsonURL, insecure: true)
        request.acceptType = "application/json"

        request.responseObject() { (response: Result<RestResponse<TestData>, RestError>) in
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

    // Test that a JSON response can be received and decoded into an [Any].
    func testResponseJSONArray() {
        let expectation = self.expectation(description: "JSON can be received and decoded into an [Any]")

        let request = RestRequest(url: jsonArrayURL, insecure: true)

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

        let request1 = RestRequest(url:jsonURL, insecure: true)

        request1.responseString() { response in
            switch response {
            case .success(let result):
                XCTAssertGreaterThan(result.body.count, 0)
            case .failure(let error):
                XCTFail("Failed to get JSON response String with error: \(error)")
            }

            /// Known example of charset=ISO-8859-1
            let request2 = RestRequest(url: "https://swift.org/")
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

        let request = RestRequest(url: jsonURL, insecure: true)

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

        let request = RestRequest(url: url)

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
        let request = RestRequest(url: jsonURL, insecure: true)
        request.productInfo = "swiftyrequest-sdk/0.2.0"

        XCTAssertEqual(request.productInfo, "swiftyrequest-sdk/0.2.0".generateUserAgent())
    }

    // MARK: Circuit breaker integration tests

    func testCircuitBreakResponseString() {
        let expectation = self.expectation(description: "CircuitBreaker success test")

        let circuitParameters = CircuitParameters(fallback: failureFallback)

        let request = RestRequest(url: jsonURL, insecure: true)
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
        let timeout = 100
        let resetTimeout = 500
        let maxFailures = 2
        var count = 0
        var fallbackCalled = false

        let request = RestRequest(url: "http://localhost:12345/blah")

        let breakFallback = { (error: BreakerError, msg: String) in
            /// After maxFailures, the circuit should be open
            if count == maxFailures {
                fallbackCalled = true
                XCTAssert(request.circuitBreaker?.breakerState == .open)
            }
        }

        let circuitParameters = CircuitParameters(name: name, timeout: timeout, resetTimeout: resetTimeout, maxFailures: maxFailures, fallback: breakFallback)

        request.circuitParameters = circuitParameters

        let completionHandler = { (response: (Result<RestResponse<String>, RestError>)) in

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

        let request = RestRequest(url: templatedJsonURL, insecure: true)
        request.circuitParameters = circuitParameters

        let completionHandlerThree = { (response: (Result<RestResponse<Data>, RestError>)) in

            switch response {
            case .success(_):
                XCTFail("Request should have failed with only using one parameter for 2 template spots.")
            case .failure(let error):
                XCTAssertEqual(error, RestError.invalidSubstitution)
            }
            expectation.fulfill()
        }

        let completionHandlerTwo = { (response: (Result<RestResponse<Data>, RestError>)) in

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

        let completionHandlerOne = { (response: (Result<RestResponse<Data>, RestError>)) in
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

        let request = RestRequest(url: templatedJsonURL, insecure: true)
        request.circuitParameters = circuitParameters

        request.responseData { response in
            switch response {
            case .success(_):
                XCTFail("Request should have failed with no parameters passed into a templated URL")
            case .failure(let error):
                XCTAssertEqual(error, RestError.invalidURL)
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)

    }

    func testURLTemplateNoTemplateValues() {
        let expectation = self.expectation(description: "URL substitution test with no template values to replace, API call should still succeed")

        let circuitParameters = CircuitParameters(fallback: failureFallback)

        let request = RestRequest(url: jsonURL, insecure: true)
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

        let request = RestRequest(url: friendsURL, insecure: true)
        request.circuitParameters = circuitParameters

        // verify query has many parameters
        let completionHandlerFour = { (response: (Result<RestResponse<Data>, RestError>)) in
            switch response {
            case .success(let result):
                XCTAssertGreaterThan(result.body.count, 0)
                XCTAssertNotNil(result.request.url.query)
                if let queryItems = result.request.url.query {
                    XCTAssertEqual(queryItems, "friend=brian&friend=george&friend=melissa%2Btempe&friend=mika")
                }
            case .failure(let error):
                XCTFail("Failed to get friends response data with error: \(error)")
            }
            expectation.fulfill()
        }

        // verify query was set to nil
        let completionHandlerThree = { (response: (Result<RestResponse<Data>, RestError>)) in
            switch response {
            case .success(let result):
                XCTAssertGreaterThan(result.body.count, 0)
                XCTAssertNil(result.request.url.query)
                let queryItems = [URLQueryItem(name: "friend", value: "brian"), URLQueryItem(name: "friend", value: "george"), URLQueryItem(name: "friend", value: "melissa+tempe"), URLQueryItem(name: "friend", value: "mika")]
                request.responseData(queryItems: queryItems, completionHandler: completionHandlerFour)
            case .failure(let error):
                XCTFail("Failed to get friends response data with error: \(error)")
                expectation.fulfill()
            }
        }

        // verify query value changed and was encoded properly
        let completionHandlerTwo = { (response: (Result<RestResponse<Data>, RestError>)) in
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
                XCTFail("Failed to get friends response data with error: \(error)")
                expectation.fulfill()
            }
        }

        // verfiy query value could be set
        let completionHandlerOne = { (response: (Result<RestResponse<Data>, RestError>)) in
            switch response {
            case .success(let retVal):
                XCTAssertGreaterThan(retVal.body.count, 0)
                XCTAssertNotNil(retVal.request.url.query)
                if let queryItems = retVal.request.url.query {
                    XCTAssertEqual(queryItems, "friend=bill")
                }

                request.responseData(queryItems: [URLQueryItem(name: "friend", value: "darren+fink")], completionHandler: completionHandlerTwo)
            case .failure(let error):
                XCTFail("Failed to get friends response data with error: \(error)")
                expectation.fulfill()
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
        
        let request = RestRequest(url: friendsURL, insecure: true)
        request.circuitParameters = circuitParameters
        
        // verify query has many parameters
        let completionHandlerFour = { (response: (Result<RestResponse<FriendData>, RestError>)) in
            switch response {
            case .success(let result):
                XCTAssertEqual(result.body.friends.count, 4)
            case .failure(let error):
                XCTFail("Failed to get friends response data with error: \(error)")
            }
            expectation.fulfill()
        }
        
        // verify query was set to nil
        let completionHandlerThree = { (response: (Result<RestResponse<FriendData>, RestError>)) in
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
        let completionHandlerTwo = { (response: (Result<RestResponse<FriendData>, RestError>)) in
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
        let completionHandlerOne = { (response: (Result<RestResponse<FriendData>, RestError>)) in
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

        let request = RestRequest(url: templatedJsonURL, insecure: true)
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
        
        let request = RestRequest(url: templatedJsonURL, insecure: true)
        request.circuitParameters = circuitParameters
        
        let templateParams: [String: String] = ["name": "Bananaman", "city": "Bananaville"]
        
        let queryItems = [URLQueryItem(name: "friend", value: "bill")]
        
        let completionHandler = { (response: (Result<RestResponse<TestData>, RestError>)) in
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

    // MARK: Authentication tests

    /// Tests that a request on a route that requires basic authentication succeeds when a valid username
    /// and password are supplied.
    func testBasicAuthentication() {
        let expectation = self.expectation(description: "Request supplying basic authentication succeeds")

        let request = RestRequest(url: basicAuthUserURL, insecure: true)
        request.credentials = .basicAuthentication(username: "John", password: "12345")

        request.responseData(templateParams: ["id": "1"]) { result in
            switch result {
            case .success(let response):
                XCTAssertEqual(response.status, .ok)
            case .failure(let error):
                XCTFail("Authenticated request failed with error: \(error)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    /// Tests that a request on a route that requires basic authentication fails, when the supplied username
    /// and password are invalid.
    func testBasicAuthenticationFails() {
        let expectation = self.expectation(description: "Request supplying invalid authentication fails")

        let request = RestRequest(url: basicAuthUserURL, insecure: true)
        request.credentials = .basicAuthentication(username: "Banana", password: "WrongPassword")

        request.responseData(templateParams: ["id": "1"]) { result in
            switch result {
            case .success(_):
                XCTFail("Authenticated request unexpectedly succeeded with bad credentials")
            case .failure(let error):
                guard let response = error.response else {
                    XCTFail("No response returned in RestError")
                    return expectation.fulfill()
                }
                XCTAssertEqual(response.status, .unauthorized)
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 10)
    }

    func testTokenAuthentication() {
        let expectation = self.expectation(description: "Request supplying token authentication succeeds")

        // Request a JWT
        let jwtUser = JWTUser(name: "Dave")
        let jwtRequest = RestRequest(method: .post, url: jwtGenerateURL, insecure: true)
        try! jwtRequest.setBodyObject(jwtUser)

        jwtRequest.responseObject { (result: Result<RestResponse<AccessToken>, RestError>) in
            switch result {
            case .success(let response):
                let jwtString = response.body.accessToken
                // Now supply the JWT as authentication
                let request = RestRequest(method: .get, url: jwtAuthUserURL, insecure: true)
                request.credentials = .bearerAuthentication(token: jwtString)
                request.responseObject { (result: Result<RestResponse<JWTUser>, RestError>) in
                    switch result {
                    case .success(let response):
                        XCTAssertEqual(response.status, .ok)
                        XCTAssertEqual(response.body, jwtUser)
                    case .failure(let error):
                        XCTFail("Authenticated request failed with error: \(error)")
                    }
                    expectation.fulfill()
                }
            case .failure(let error):
                XCTFail("Request to generate JWT failed with error: \(error)")
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 10)
    }

    // MARK: Headers tests

    // Tests that the mapping of SwiftyRequest's [String:String] API for supplying headers
    // to HTTPClient's HTTPHeaders functions correctly.
    // While HTTPHeaders can support multiple values for the same header, SwiftyRequest's
    // API does not. This decision was taken to preserve the existing headers API from the
    // previous version of SwiftyRequest.
    func testHeaders() {
        // Dummy request to test translation of header dictionaries into HTTPHeaders
        let request = RestRequest(url: "http://foo.xyz/")
        // Headers that are set by default
        let defaultHeaders = ["Accept": "application/json", "Content-Type": "application/json"]
        // Headers that we want to add
        let userHeaders = ["a": "A", "b": "B"]

        // Tells Dictionary.merging to overwrite existing keys with the new ones
        let overwriteExisting: (String, String) -> String = { (_, last) in last }

        // Test that headers can be added
        request.headerParameters = userHeaders
        var expectedHeaders = defaultHeaders.merging(userHeaders, uniquingKeysWith: overwriteExisting)
        XCTAssertEqual(request.headerParameters, expectedHeaders)

        // Test that additional headers can be added
        let additionalHeaders = ["c": "C"]
        request.headerParameters = additionalHeaders
        expectedHeaders = expectedHeaders.merging(additionalHeaders, uniquingKeysWith: overwriteExisting)
        XCTAssertEqual(request.headerParameters, expectedHeaders)

        // Test that an existing header can be replaced
        let replacementHeaders = ["a": "Banana"]
        request.headerParameters = replacementHeaders
        expectedHeaders = expectedHeaders.merging(replacementHeaders, uniquingKeysWith: overwriteExisting)
        XCTAssertEqual(request.headerParameters, expectedHeaders)
    }

    // MARK: Test code examples in README

    func testExampleRequest() {
        let expectation = self.expectation(description: "Request supplying token authentication succeeds")

        let request = RestRequest(method: .get, url: "http://localhost:8080/users/{userid}")

        request.responseObject(templateParams: ["userid": "1"]) { (result: Result<RestResponse<User>, RestError>) in
            switch result {
            case .success(let response):
                let user = response.body
                print("Successfully retrieved user \(user.name)")
                XCTAssertEqual(user.id, 1)
            case .failure(let error):
                if let response = error.response {
                    print("Request failed with status: \(response.status)")
                }
                if let responseData = error.responseData {
                    print("Response returned: \(String(data: responseData, encoding: .utf8) ?? "")")
                }
                XCTFail("Request failed")
            }
            expectation.fulfill()
        }
        waitForExpectations(timeout: 10)
    }

    // MARK: Test configuration parameters

    func testEventLoopGroup() {
        let myELG = MultiThreadedEventLoopGroup(numberOfThreads: 2)

        // Clear the global ELG
        RestRequest._testOnly_resetELG()

        // Access default ELG, and verify it cannot then be set
        XCTAssertNotNil(RestRequest.globalELG)
        XCTAssertThrowsError(try RestRequest.setGlobalELG(myELG), "Global ELG should not have been set again")

        // Clear the global ELG
        RestRequest._testOnly_resetELG()

        // Verify that the ELG can be set once and only once
        XCTAssertNoThrow(try RestRequest.setGlobalELG(myELG), "Global ELG could not be set")
        XCTAssertThrowsError(try RestRequest.setGlobalELG(myELG), "Global ELG should not have been set again")
    }

    // MARK: Timeout tests

    /// Makes a request to a route that delays its response for longer than the configured timeout, causing a failure.
    /// Then tests that a request with the same configuration succeeds if the route responds within the timeout.
    func testRequestTimeout() {
        let timeoutExpectation = self.expectation(description: "Request times out")
        let successExpectation = self.expectation(description: "Request succeeds")

        let request = RestRequest(method: .get, url: "http://localhost:8080/timeout", timeout: HTTPClient.Configuration.Timeout(connect: nil, read: .milliseconds(500)))

        let delay1s = URLQueryItem(name: "delay", value: "501")

        request.responseVoid(queryItems: [delay1s]) { result in
            switch result {
            case .success(let response):
                XCTFail("Request should have timed out, but status was \(response.status)")
            case .failure(let error):
                XCTAssertEqual(error, RestError.httpClientError(HTTPClientError.readTimeout))
            }
            timeoutExpectation.fulfill()
        }

        let delayNone = URLQueryItem(name: "delay", value: "100")

        request.responseVoid(queryItems: [delayNone]) { result in
            switch result {
            case .success(let response):
                XCTAssertEqual(response.status, .ok)
            case .failure(let error):
                XCTFail("Request should have succeeded, but produced: \(error)")
            }
            successExpectation.fulfill()
        }

        waitForExpectations(timeout: 3)
    }

/**
 * Note: Disabling this test because it seems unreliable in a CI environment
    /// Connects to a socket that listens but never accepts a connection, and verifies that the client
    /// times out with a failure after a specified connect timeout.
    func testConnectTimeout() {
        let timeoutExpectation = self.expectation(description: "Request times out")
        let timeout: TimeAmount = .milliseconds(500)

        let request = RestRequest(method: .get, url: "http://localhost:8079/", timeout: HTTPClient.Configuration.Timeout(connect: timeout, read: nil))

        request.responseVoid { result in
            switch result {
            case .success(let response):
                XCTFail("Connection should have timed out, but status was \(response.status)")
            case .failure(let error):
                XCTAssertEqual(error, RestError.otherError(NIO.ChannelError.connectTimeout(timeout)))
                if let underlyingError = error.error, case let NIO.ChannelError.connectTimeout(timeAmount) = underlyingError {
                    XCTAssertEqual(timeAmount, timeout, "Timeout amount was incorrect")
                } else {
                    XCTFail("Underlying error was not NIO.ChannelError.connectTimeout, it was: \(error.error ?? error)")
                }
            }
            timeoutExpectation.fulfill()
        }

        waitForExpectations(timeout: 3)
    }
*/
}
