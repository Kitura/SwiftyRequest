/**
 * Copyright IBM Corporation 2016,2017
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import Foundation
import CircuitBreaker
import LoggerAPI
import AsyncHTTPClient
import NIO
import NIOHTTP1
import NIOSSL

fileprivate class MutableRequest {
    /// Request HTTP method
    var method: HTTPMethod
    /// Remote URL. May contain templated parameters
    var urlString: String
    /// Request custom HTTP Headers, defaults to no headers.
    var headers: HTTPHeaders
    /// Request body, defaults to no body.
    var body: HTTPClient.Body?
    /// Query items that will be added to the request URL.
    var queryItems: [URLQueryItem]?

    init(method: HTTPMethod = .GET, url: String) {
        self.method = method
        self.urlString = url
        self.headers = HTTPHeaders()
        self.body = nil
    }

    /// Creates an (immutable) HTTPClient.Request using this wrapper's current values.
    /// Can optionally perform substitutions on a templated URL.
    func makeRequest(substitutions: [String: String]? = nil) throws -> HTTPClient.Request {
        // Perform substitutions on templated URL, if necessary.
        var url = try performSubstitutions(params: substitutions)
        if let queryItems = self.queryItems {
            url = try resolveQueryItems(url: url, queryItems: queryItems)
        }
        return try HTTPClient.Request(url: url, method: method, headers: headers, body: body)
    }

    // Replace queryitems in URL with new queryItems
    private func resolveQueryItems(url: URL, queryItems: [URLQueryItem]) throws -> URL {
        if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            urlComponents.queryItems = queryItems
            // Must encode "+" to %2B (URLComponents does not do this)
            urlComponents.percentEncodedQuery = urlComponents.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            guard let url = urlComponents.url else {
                throw RestError.invalidURL(description: "'\(urlComponents)' is not a valid URL")
            }
            return url
        } else {
            throw RestError.invalidURL(description: "URLComponents cannot resolve '\(url)'")
        }
    }

    /// Method to perform substitution on `String` URL if it contains templated placeholders
    ///
    /// - Parameter params: optional dictionary of parameters to substitute in
    /// - Returns: returns a `URL` if template substitution was successful, or if the `url` is not templated.
    /// - throws: `RestError.invalidSubstitution` if parameters were provided and the resulting URL was not valid,
    /// - throws: `HTTPClientError.invalidURL` if no parameters were provided and the `urlString` is not a valid URL.
    private func performSubstitutions(params: [String: String]?) throws -> URL {
        guard let params = params, urlString.contains("{") else {
            // No parameters provided, or no parameters required - create a plain URL
            guard let simpleURL = URL(string: self.urlString) else {
                throw RestError.invalidURL(description: "'\(urlString)' is not a valid URL")
            }
            return simpleURL
        }
        // Replace templated elements with provided values
        let expandedUrlString = urlString.expandString(params: params)
        // Confirm that the resulting URL is valid
        guard let expandedURL = URL(string: expandedUrlString) else {
            throw RestError.invalidSubstitution
        }
        return expandedURL
    }

}

/// Object containing everything needed to build and execute HTTP requests.
public class RestRequest {

    deinit {
        try? session.syncShutdown()
    }

    /// A default `HTTPClient` instance.
    private var session: HTTPClient

    // The HTTP Request
    private var mutableRequest: MutableRequest

    /// The currently configured `CircuitBreaker` instance for this `RestRequest`. In order to create a
    /// `CircuitBreaker` you should set the `circuitParameters` property.
    internal(set) public var circuitBreaker: CircuitBreaker<(HTTPClient.Request, (Result<HTTPClient.Response, Error>) -> Void), String>?

    /// Parameters for a `CircuitBreaker` instance.
    /// When these parameters are set, a new `circuitBreaker` instance is created.
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// let circuitParameters = CircuitParameters(timeout: 2000,
    ///                                           maxFailures: 2,
    ///                                           fallback: breakFallback)
    ///
    /// let request = RestRequest(method: .GET, url: "http://myApiCall/hello")
    /// request.circuitParameters = circuitParameters
    /// ```
    public var circuitParameters: CircuitParameters<String>? = nil {
        didSet {
            if let params = circuitParameters {
                circuitBreaker = CircuitBreaker(
                    name: params.name,
                    timeout: params.timeout,
                    resetTimeout: params.resetTimeout,
                    maxFailures: params.maxFailures,
                    rollingWindow: params.rollingWindow,
                    bulkhead: params.bulkhead,
                    // We capture a weak reference to self to prevent a retain cycle from `handleInvocation` -> RestRequest` -> `circuitBreaker` -> `handleInvocation`. To do this we have explicitly declared the handleInvocation function as a closure.
                    command: { [weak self] invocation in
                        let request = invocation.commandArgs.0
                        self?.session.execute(request: request).whenComplete { result in
                            switch result {
                            case .failure(let error):
                                invocation.notifyFailure(error: BreakerError(reason: error.localizedDescription))
                            case .success(_):
                                invocation.notifySuccess()
                            }
                            let callback = invocation.commandArgs.1
                            callback(result)
                        }
                    },
                    fallback: params.fallback)
            }
        }
    }

    // MARK: HTTP Request Parameters

    /// The HTTP method specified in the request, defaults to GET.
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// request.method = .PUT
    /// ```
    public var method: HTTPMethod {
        get {
            return mutableRequest.method
        }
        set {
            mutableRequest.method = newValue
        }
    }

    /// The HTTP authentication credentials for the request.
    ///
    /// ### Usage Example: ###
    /// The example below uses an API key to specify the authentication credentials. You can also use `.bearerAuthentication`
    /// and pass in a base64 encoded String as the token, or `.basicAuthentication` where the username and password values to
    /// authenticate with are passed in.
    ///
    /// ```swift
    /// let request = RestRequest(url: "http://localhost:8080")
    /// request.credentials = .basicAuthentication(username: "Hello", password: "World")
    /// ```
    public var credentials: Credentials? {
        didSet {
            // set the request's authentication credentials
            if let credentials = credentials {
                mutableRequest.headers.replaceOrAdd(name: "Authorization", value: credentials.authheader)
            } else {
                mutableRequest.headers.remove(name: "Authorization")
            }
        }
    }

    /// The HTTP header fields which form the header section of the request message.
    ///
    /// The header fields set using this parameter will be added to the existing headers.
    ///
    /// ### Usage Example: ###
    ///
    /// ```swift
    /// request.headerParameters = HTTPHeaders([("Cookie", "v1")])
    /// ```
    public var headerParameters: HTTPHeaders {
        get {
            return mutableRequest.headers
        }
        set {
            mutableRequest.headers.add(contentsOf: newValue)
        }
    }

    /// The HTTP `Accept` header, i.e. the media type that is acceptable for the response, it defaults to
    /// "application/json".
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// request.acceptType = "text/html"
    /// ```
    public var acceptType: String? {
        get {
            return mutableRequest.headers["Accept"].first
        }
        set {
            if let value = newValue {
                mutableRequest.headers.replaceOrAdd(name: "Accept", value: value)
            } else {
                mutableRequest.headers.remove(name: "Accept")
            }
        }
    }

    /// HTTP `Content-Type` header, i.e. the media type of the body of the request, it defaults to
    /// "application/json".
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// request.contentType = "application/x-www-form-urlencoded"
    /// ```
    public var contentType: String? {
        get {
            return mutableRequest.headers["Content-Type"].first
        }
        set {
            if let value = newValue {
                mutableRequest.headers.replaceOrAdd(name: "Content-Type", value: value)
            } else {
                mutableRequest.headers.remove(name: "Content-Type")
            }
        }
    }

    /// HTTP `User-Agent` header, i.e. the user agent string of the software that is acting on behalf of the user.
    /// If you pass in `<productName>/<productVersion>` the value will be set to
    /// `<productName>/<productVersion> <operatingSystem>/<operatingSystemVersion>`.
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// request.productInfo = "swiftyrequest-sdk/2.0.4"
    /// ```
    public var productInfo: String? {
        get {
            return mutableRequest.headers["User-Agent"].first
        }
        set {
            if let value = newValue {
                mutableRequest.headers.replaceOrAdd(name: "User-Agent", value: value.generateUserAgent())
            } else {
                mutableRequest.headers.remove(name: "User-Agent")
            }
        }
    }

    // Storage for message body
    private var _messageBody: Data?
    
    /// The HTTP message body, i.e. the body of the request.
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// request.messageBody = data
    /// ``
    public var messageBody: Data? {
        get {
            return _messageBody
        }
        set {
            _messageBody = newValue
            if let data = newValue {
                mutableRequest.body = .data(data)
            } else {
                mutableRequest.body = nil
            }
        }
    }

    /// The HTTP query items to specify in the request URL. If there are query items already specified in the request URL they
    /// will be replaced.
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// request.queryItems = [
    ///                        URLQueryItem(name: "flamingo", value: "pink"),
    ///                        URLQueryItem(name: "seagull", value: "white")
    ///                      ]
    /// ```
    public var queryItems: [URLQueryItem]?  {
        set {
            mutableRequest.queryItems = newValue
        }
        get {
            return mutableRequest.queryItems
        }
    }
    

    /// Initialize a `RestRequest` instance.
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// let request = RestRequest(method: .GET, url: "http://myApiCall/hello")
    /// ```
    ///
    /// - Parameters:
    ///   - method: The method specified in the request, defaults to GET.
    ///   - url: URL string to use for the network request.
    ///   - insecure: Pass `True` to accept invalid or self-signed certificates.
    ///   - clientCertificate: Pass in `ClientCertificate` with the certificate name and path to use client certificates for 2-way SSL.
    public init(method: HTTPMethod = .GET, url: String, insecure: Bool = false, clientCertificate: NIOSSLCertificate? = nil) throws {
        self.mutableRequest = MutableRequest(method: method, url: url)
        self.session = RestRequest.createHTTPClient(insecure: insecure, clientCertificate: clientCertificate)

        // Set initial headers
        self.acceptType = "application/json"
        self.contentType = "application/json"

    }

    private static func createHTTPClient(insecure: Bool, clientCertificate: NIOSSLCertificate?) -> HTTPClient {
        let chain: [NIOSSLCertificateSource]
        if let clientCertificate = clientCertificate {
            chain = [.certificate(clientCertificate)]
        } else {
            chain = []
        }
        let tlsConfiguration = TLSConfiguration.forClient(
            certificateVerification: (insecure ? .none : .fullVerification),
            certificateChain: chain)
        let config = HTTPClient.Configuration(tlsConfiguration: tlsConfiguration)
        return HTTPClient(eventLoopGroupProvider: .createNew, configuration: config)
    }

    // MARK: Response methods
    /// Request response method that either invokes `CircuitBreaker` or executes the HTTP request.
    ///
    /// - Parameter completionHandler: Callback used on completion of operation.
    public func response(completionHandler: @escaping (Result<HTTPClient.Response, Error>) -> Void) {
        do {
            let request = try self.mutableRequest.makeRequest()
            response(request: request, completionHandler: completionHandler)
        } catch {
            return completionHandler(.failure(error))
        }

    }
    
    func response(request: HTTPClient.Request, completionHandler: @escaping (Result<HTTPClient.Response, Error>) -> Void) {
        if let breaker = circuitBreaker {
            breaker.run(commandArgs: (request, completionHandler), fallbackArgs: "Circuit is open")
        } else {
            self.session.execute(request: request).whenComplete { result in
                switch result {
                case .success(let response):
                    if response.status.code >= 200 && response.status.code < 300 {
                        return completionHandler(.success(response))
                    } else {
                        return completionHandler(.failure(RestError.errorStatusCode(response: response)))
                    }
                case .failure(let error):
                    return completionHandler(.failure(error))
                }
            }
        }
    }

    // Function to get cookies from HTTPURLResponse headers.
    private func getCookies(from response: HTTPURLResponse?) -> [HTTPCookie]? {
        guard let headers = response?.allHeaderFields else {
            return nil
        }
        var headerFields = [String : String]()
        for (key, value) in headers {
            guard let key = key as? String, let value = value as? String else {
                continue
            }
            headerFields[key] = value
        }
        guard headerFields["Set-Cookie"] != nil else {
            return nil
        }
        let url = response?.url
        let dummyUrl = URL(string:"http://example.com")!
        return HTTPCookie.cookies(withResponseHeaderFields: headerFields, for: url ?? dummyUrl)
    }

    /// Request response method with the expected result of a `Data` object.
    ///
    /// - Parameters:
    ///   - templateParams: URL templating parameters used for substituion if possible.
    ///   - queryItems: Sets the query parameters for this RestRequest, overwriting any existing parameters. Defaults to `nil`, which means that this parameter will be ignored, and `RestRequest.queryItems` will be used instead. Note that if you wish to clear any existing query parameters, then you should set `request.queryItems = nil` before calling this function.
    ///   - completionHandler: Callback used on completion of operation.
    public func responseData(templateParams: [String: String]? = nil,
                             queryItems: [URLQueryItem]? = nil,
                             completionHandler: @escaping (Result<RestResponse<Data>, Error>) -> Void) {

        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            mutableRequest.queryItems = queryItems
        }

        // Create an (immutable) Request from our MutableRequest
        var request: HTTPClient.Request
        do {
            request = try self.mutableRequest.makeRequest(substitutions: templateParams)
        } catch {
            return completionHandler(.failure(error))
        }

        response(request: request) { result in
            switch result {
            case .failure(let error):
                return completionHandler(.failure(error))
            case .success(let response):
                guard let body = response.body,
                    let bodyBytes = body.getBytes(at: 0, length: body.readableBytes)
                else {
                    return completionHandler(.failure(RestError.noData(response: response)))
                }
                return completionHandler(.success(RestResponse(host: response.host,
                                                        status: response.status,
                                                        headers: response.headers,
                                                        request: request,
                                                        body: Data(bodyBytes)))) 
            }
        }
    }

    /// Request response method with the expected result of the object `T` specified.
    ///
    /// - Parameters:
    ///   - templateParams: URL templating parameters used for substitution if possible.
    ///   - queryItems: Sets the query parameters for this RestRequest, overwriting any existing parameters. Defaults to `nil`, which means that this parameter will be ignored, and `RestRequest.queryItems` will be used instead. Note that if you wish to clear any existing query parameters, then you should set `request.queryItems = nil` before calling this function.
    ///   - completionHandler: Callback used on completion of operation.
    public func responseObject<T: Decodable>(templateParams: [String: String]? = nil,
                                             queryItems: [URLQueryItem]? = nil,
                                             completionHandler: @escaping (Result<RestResponse<T>, Error>) -> Void) {

        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            mutableRequest.queryItems = queryItems
        }

        // Create an (immutable) Request from our MutableRequest
        var request: HTTPClient.Request
        do {
            request = try self.mutableRequest.makeRequest(substitutions: templateParams)
        } catch {
            return completionHandler(.failure(error))
        }

        response(request: request) { result in
            switch result {
            case .failure(let error):
                return completionHandler(.failure(error))
            case .success(let response):
                guard let body = response.body,
                    let bodyBytes = body.getBytes(at: 0, length: body.readableBytes)
                else {
                    return completionHandler(.failure(RestError.noData(response: response)))
                }
                do {
                    let object = try JSONDecoder().decode(T.self, from: Data(bodyBytes))
                    return completionHandler(.success(RestResponse(host: response.host,
                                                            status: response.status,
                                                            headers: response.headers,
                                                            request: request,
                                                            body: object))) 
                } catch {
                    return completionHandler(.failure(RestError.decodingError(error: error, response: response)))
                }
            }
        }
    }

    /// Request response method with the expected result of an array of `Any` JSON.
    ///
    /// - Parameters:
    ///   - templateParams: URL templating parameters used for substitution if possible.
    ///   - queryItems: Sets the query parameters for this RestRequest, overwriting any existing parameters. Defaults to `nil`, which means that this parameter will be ignored, and `RestRequest.queryItems` will be used instead. Note that if you wish to clear any existing query parameters, then you should set `request.queryItems = nil` before calling this function.
    ///   - completionHandler: Callback used on completion of operation.
    public func responseArray(templateParams: [String: String]? = nil,
                              queryItems: [URLQueryItem]? = nil,
                              completionHandler: @escaping (Result<RestResponse<[Any]>, Error>) -> Void) {
        
        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            mutableRequest.queryItems = queryItems
        }

        // Create an (immutable) Request from our MutableRequest
        var request: HTTPClient.Request
        do {
            request = try self.mutableRequest.makeRequest(substitutions: templateParams)
        } catch {
            return completionHandler(.failure(error))
        }

        response(request: request) { result in
            switch result {
            case .failure(let error):
                return completionHandler(.failure(error))
            case .success(let response):
                guard let body = response.body,
                    let bodyBytes = body.getBytes(at: 0, length: body.readableBytes)
                else {
                    return completionHandler(.failure(RestError.noData(response: response)))
                }
                guard let object = (try? JSONSerialization.jsonObject(with: Data(bodyBytes))) as? [Any] else {
                    return completionHandler(.failure(RestError.serializationError(response: response)))
                }
                return completionHandler(.success(RestResponse(host: response.host,
                                                               status: response.status,
                                                               headers: response.headers,
                                                               request: request,
                                                               body: object))) 
            }
        }
    }
    
    /// Request response method with the expected result of a `[String: Any]` JSON dictionary.
    ///
    /// - Parameters:
    ///   - templateParams: URL templating parameters used for substitution if possible.
    ///   - queryItems: Sets the query parameters for this RestRequest, overwriting any existing parameters. Defaults to `nil`, which means that this parameter will be ignored, and `RestRequest.queryItems` will be used instead. Note that if you wish to clear any existing query parameters, then you should set `request.queryItems = nil` before calling this function.
    ///   - completionHandler: Callback used on completion of operation.
    public func responseDictionary(templateParams: [String: String]? = nil,
                              queryItems: [URLQueryItem]? = nil,
                              completionHandler: @escaping (Result<RestResponse<[String: Any]>, Error>) -> Void) {
        
        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            mutableRequest.queryItems = queryItems
        }

        // Create an (immutable) Request from our MutableRequest
        var request: HTTPClient.Request
        do {
            request = try self.mutableRequest.makeRequest(substitutions: templateParams)
        } catch {
            return completionHandler(.failure(error))
        }

        response(request: request) { result in
            switch result {
            case .failure(let error):
                return completionHandler(.failure(error))
            case .success(let response):
                guard let body = response.body,
                    let bodyBytes = body.getBytes(at: 0, length: body.readableBytes)
                    else {
                        return completionHandler(.failure(RestError.noData(response: response)))
                }
                guard let object = (try? JSONSerialization.jsonObject(with: Data(bodyBytes))) as? [String: Any] else {
                    return completionHandler(.failure(RestError.serializationError(response: response)))
                }
                return completionHandler(.success(RestResponse(host: response.host,
                                                               status: response.status,
                                                               headers: response.headers,
                                                               request: request,
                                                               body: object))) 
            }
        }
    }


    /// Request response method with the expected result of a `String`.
    ///
    /// - Parameters:
    ///   - templateParams: URL templating parameters used for substituion if possible.
    ///   - queryItems: Sets the query parameters for this RestRequest, overwriting any existing parameters. Defaults to `nil`, which means that this parameter will be ignored, and `RestRequest.queryItems` will be used instead. Note that if you wish to clear any existing query parameters, then you should set `request.queryItems = nil` before calling this function.
    ///   - completionHandler: Callback used on completion of operation.
    public func responseString(templateParams: [String: String]? = nil,
                               queryItems: [URLQueryItem]? = nil,
                               completionHandler: @escaping (Result<RestResponse<String>, Error>) -> Void) {
        
        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            mutableRequest.queryItems = queryItems
        }

        // Create an (immutable) Request from our MutableRequest
        var request: HTTPClient.Request
        do {
            request = try self.mutableRequest.makeRequest(substitutions: templateParams)
        } catch {
            return completionHandler(.failure(error))
        }

        response(request: request) { result in
            switch result {
            case .failure(let error):
                return completionHandler(.failure(error))
            case .success(let response):
                guard let body = response.body,
                    let bodyBytes = body.getBytes(at: 0, length: body.readableBytes)
                    else {
                        return completionHandler(.failure(RestError.noData(response: response)))
                }
                // Retrieve string encoding type
                let encoding = self.getCharacterEncoding(from: response.headers["Content-Type"].first)
                
                guard let object = String(bytes: bodyBytes, encoding: encoding) else {
                    return completionHandler(.failure(RestError.serializationError(response: response)))
                }
                return completionHandler(.success(RestResponse(host: response.host,
                                                               status: response.status,
                                                               headers: response.headers,
                                                               request: request,
                                                               body: object))) 
            }
        }
    }

    /// Request response method to use when there is no expected result.
    ///
    /// - Parameters:
    ///   - templateParams: URL templating parameters used for substituion if possible.
    ///   - queryItems: Sets the query parameters for this RestRequest, overwriting any existing parameters. Defaults to `nil`, which means that this parameter will be ignored, and `RestRequest.queryItems` will be used instead. Note that if you wish to clear any existing query parameters, then you should set `request.queryItems = nil` before calling this function.
    ///   - completionHandler: Callback used on completion of operation.
    public func responseVoid(templateParams: [String: String]? = nil,
                             queryItems: [URLQueryItem]? = nil,
                             completionHandler: @escaping (Result<HTTPClient.Response, Error>) -> Void) {
        
        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            mutableRequest.queryItems = queryItems
        }

        // Create an (immutable) Request from our MutableRequest
        var request: HTTPClient.Request
        do {
            request = try self.mutableRequest.makeRequest(substitutions: templateParams)
        } catch {
            return completionHandler(.failure(error))
        }

        response(request: request) { result in
            switch result {
            case .failure(let error):
                return completionHandler(.failure(error))
            case .success(let response):
                return completionHandler(.success(response)) 
            }
        }
    }

    class DownloadDelegate: HTTPClientResponseDelegate {
        typealias Response = HTTPResponseHead
        
        var count = 0
        let destination: URL
        var responseHead: HTTPResponseHead?
        var error: Error?
        
        init(destination: URL) {
            self.destination = destination
        }
        
        func didSendRequestHead(task: HTTPClient.Task<Response>, _ head: HTTPRequestHead) {
            // this is executed when request is sent, called once
            // Create a file in one doesn't exist
            do {
                try "".write(to: destination, atomically: true, encoding: .utf8)
            } catch {
                self.error = error
            }
        }
        
        func didSendRequestPart(task: HTTPClient.Task<Response>, _ part: IOData) {
            // this is executed when request body part is sent, could be called zero or more times
        }
        
        func didSendRequest(task: HTTPClient.Task<Response>) {
            // this is executed when request is fully sent, called once
        }
        
        func didReceiveHead(task: HTTPClient.Task<Response>, _ head: HTTPResponseHead) -> EventLoopFuture<Void> {
            // this is executed when we receive HTTP Reponse head part of the request (it contains response code and headers), called once
            self.responseHead = head
            return task.eventLoop.makeSucceededFuture(())
        }
        
        func didReceivePart(task: HTTPClient.Task<Response>, _ buffer: ByteBuffer) -> EventLoopFuture<Void> {
            // this is executed when we receive parts of the response body, could be called zero or more times
            do {
                let fileHandle = try FileHandle(forUpdating: destination)
                fileHandle.seekToEndOfFile()
                fileHandle.write(Data(buffer.getBytes(at: 0, length: buffer.readableBytes) ?? []))
                fileHandle.closeFile()
            } catch {
                self.error = error
            }
            return task.eventLoop.makeSucceededFuture(())
        }
        
        func didFinishRequest(task: HTTPClient.Task<HTTPResponseHead>) throws -> HTTPResponseHead {
            // this is called when the request is fully read, called once
            // this is where you return a result or throw any errors you require to propagate to the client
            guard let head = responseHead else {
                throw RestError.downloadError
            }
            if let error = error {
                throw error
            }
            return head
        }
        
        func didReceiveError(task: HTTPClient.Task<HTTPResponseHead>, _ error: Error) {
            // this is called when we receive any network-related error, called once
            self.error = error
        }
    }
    
    /// Utility method to download a file from a remote origin.
    ///
    /// - Parameters:
    ///   - destination: URL destination to save the file to.
    ///   - completionHandler: Callback used on completion of the operation.
    public func download(to destination: URL, completionHandler: @escaping (Result<HTTPResponseHead, Error>) -> Void) {
        let delegate = DownloadDelegate(destination: destination)

        // Create an (immutable) Request from our MutableRequest
        var request: HTTPClient.Request
        do {
            request = try self.mutableRequest.makeRequest()
        } catch {
            return completionHandler(.failure(error))
        }

        session.execute(request: request, delegate: delegate).futureResult.whenComplete({ result in
            completionHandler(result)
        })
    }

    /// Method to identify the charset encoding defined by the Content-Type header
    /// - Defaults set to .utf8
    /// - Parameter contentType: The content-type header string
    /// - Returns: returns the defined or default String.Encoding.Type
    private func getCharacterEncoding(from contentType: String? = nil) -> String.Encoding {
        guard let text = contentType,
              let regex = try? NSRegularExpression(pattern: "(?<=charset=).*?(?=$|;|\\s)", options: [.caseInsensitive]),
              let match = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).last,
              let range = Range(match.range, in: text) else {
            return .utf8
        }

        /// Strip whitespace and quotes
        let charset = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\"").union(.whitespaces))

        switch String(charset).lowercased() {
        case "iso-8859-1": return .isoLatin1
        default: return .utf8
        }
    }
}

/// Encapsulates properties needed to initialize a `CircuitBreaker` object within the `RestRequest` initializer.
/// `A` is the type of the fallback's parameter.
public struct CircuitParameters<A> {

    /// The circuit name: defaults to "circuitName".
    let name: String

    /// The circuit timeout: defaults to 2000.
    public let timeout: Int

    /// The circuit timeout: defaults to 60000.
    public let resetTimeout: Int

    /// Max failures allowed: defaults to 5.
    public let maxFailures: Int

    /// Rolling Window: defaults to 10000.
    public let rollingWindow:Int

    /// Bulkhead: defaults to 0.
    public let bulkhead: Int

    /// The error fallback callback.
    public let fallback: (BreakerError, A) -> Void

    /// Initialize a `CircuitParameters` instance.
    public init(name: String = "circuitName", timeout: Int = 2000, resetTimeout: Int = 60000, maxFailures: Int = 5, rollingWindow: Int = 10000, bulkhead: Int = 0, fallback: @escaping (BreakerError, A) -> Void) {
        self.name = name
        self.timeout = timeout
        self.resetTimeout = resetTimeout
        self.maxFailures = maxFailures
        self.rollingWindow = rollingWindow
        self.bulkhead = bulkhead
        self.fallback = fallback
    }
}

/// Struct used to specify the type of authentication being used.
public struct Credentials {
    
    let authheader: String

    /// Note: The bearer token should be base64 encoded.
    public static func bearerAuthentication(token: String) -> Credentials {
        return Credentials(authheader: "Bearer \(token)")
    }
    

    /// A basic username/password authentication is being used with the values passed in.
    public static func basicAuthentication(username: String, password: String) -> Credentials {
        let authData = Data((username + ":" + password).utf8)
        let authString = authData.base64EncodedString()
        return Credentials(authheader: "Basic \(authString)")
    }
}
