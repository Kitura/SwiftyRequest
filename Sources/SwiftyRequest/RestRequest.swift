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

#if swift(>=4.1)
  #if canImport(FoundationNetworking)
    import FoundationNetworking
  #endif
#endif

/// Object containing everything needed to build and execute HTTP requests.
public class RestRequest: NSObject  {

    deinit {
        #if swift(>=4.1)
        if session != URLSession.shared {
            session.finishTasksAndInvalidate()
        }
        #else
        session.finishTasksAndInvalidate()
        #endif
    }
    
    // Check if there exists a self-signed certificate and whether it's a secure connection
    private let isSecure: Bool
    private let isSelfSigned: Bool
    
    // The client certificate for 2-way SSL
    private let clientCertificate: ClientCertificate?

    /// The `URLSession` instance that will be used to send the requests. Defaults to `URLSession.shared`.
    #if swift(>=4.1)
    public var session: URLSession = URLSession.shared
    #else
    public var session: URLSession = URLSession(configuration: URLSessionConfiguration.default)
    #endif

    // The HTTP Request
    private var request: URLRequest

    /// The currently configured `CircuitBreaker` instance for this `RestRequest`. In order to create a
    /// `CircuitBreaker` you should set the `circuitParameters` property.
    public var circuitBreaker: CircuitBreaker<(Data?, HTTPURLResponse?, Error?) -> Void, String>?

    /// Parameters for a `CircuitBreaker` instance.
    /// When these parameters are set, a new `circuitBreaker` instance is created.
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// let circuitParameters = CircuitParameters(timeout: 2000,
    ///                                           maxFailures: 2,
    ///                                           fallback: breakFallback)
    ///
    /// let request = RestRequest(method: .get, url: "http://myApiCall/hello")
    /// request.credentials = .apiKey,
    /// request.circuitParameters = circuitParameters
    /// ```
    public var circuitParameters: CircuitParameters<String>? = nil {
        didSet {
            if let params = circuitParameters {
                circuitBreaker = CircuitBreaker(name: params.name,
                                                timeout: params.timeout,
                                                resetTimeout: params.resetTimeout,
                                                maxFailures: params.maxFailures,
                                                rollingWindow: params.rollingWindow,
                                                bulkhead: params.bulkhead,
                                                // We capture a weak reference to self to prevent a retain cycle from `handleInvocation` -> RestRequest` -> `circuitBreaker` -> `handleInvocation`. To do this we have explicitly declared the handleInvocation function as a closure.
                                                command: { [weak self] invocation in self?.handleInvocation(invocation: invocation) },
                                                fallback: params.fallback)
            }
        }
    }

    // MARK: HTTP Request Parameters
    /// URL `String` used to store a url containing replaceable template values.
    private var urlTemplate: String?

    /// The string representation of the HTTP request url.
    private var url: String

    /// The HTTP method specified in the request, defaults to GET.
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// request.method = .put
    /// ```
    public var method: HTTPMethod {
        get {
            return HTTPMethod(fromRawValue: request.httpMethod ?? "unknown")
        }
        set {
            request.httpMethod = newValue.rawValue
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
    /// let request = RestRequest(url: apiURL)
    /// request.credentials = .apiKey
    /// ```
    public var credentials: Credentials? {
        didSet {
            // set the request's authentication credentials
            if let credentials = credentials {
                switch credentials {
                case .apiKey: break
                case .bearerAuthentication(let token):
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                case .basicAuthentication(let username, let password):
                    let authData = (username + ":" + password).data(using: .utf8)!
                    let authString = authData.base64EncodedString()
                    request.setValue("Basic \(authString)", forHTTPHeaderField: "Authorization")
                }
            } else {
                request.setValue(nil, forHTTPHeaderField: "Authorization")
            }
        }
    }

    /// The HTTP header fields which form the header section of the request message.
    ///
    /// Header fields are colon-separated key-value pairs in string format.  Existing header fields which are not one of the
    /// four`RestRequest` supported headers ("Authorization", "Accept", "Content-Type" and "User-Agent") will be cleared
    /// (set to nil) then the passed in HTTP parameters will be set (or replaced).
    ///
    /// ### Usage Example: ###
    ///
    /// ```swift
    /// request.headerParameters = ["Cookie" : "v1"]
    /// ```
    public var headerParameters: [String: String] {
        get {
            return request.allHTTPHeaderFields ?? [:]
        }
        set {
            // Remove any header fields external to the RestRequest supported headers
            let s: Set<String> = ["Authorization", "Accept", "Content-Type", "User-Agent"]
            _ = request.allHTTPHeaderFields?.map { key, value in if !s.contains(key) { request.setValue(nil, forHTTPHeaderField: key) } }
            // Add new header parameters
            for (key, value) in newValue {
                request.setValue(value, forHTTPHeaderField: key)
            }
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
            return request.value(forHTTPHeaderField: "Accept")
        }
        set {
            request.setValue(newValue, forHTTPHeaderField: "Accept")
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
            return request.value(forHTTPHeaderField: "Content-Type")
        }
        set {
            request.setValue(newValue, forHTTPHeaderField: "Content-Type")
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
            return request.value(forHTTPHeaderField: "User-Agent")
        }
        set {
            request.setValue(newValue?.generateUserAgent(), forHTTPHeaderField: "User-Agent")
        }
    }

    /// The HTTP message body, i.e. the body of the request.
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// request.messageBody = data
    /// ``
    public var messageBody: Data? {
        get {
            return request.httpBody
        }
        set {
            request.httpBody = newValue
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
            // Replace queryitems on request.url with new queryItems
            if let currentURL = request.url, var urlComponents = URLComponents(url: currentURL, resolvingAgainstBaseURL: false) {
                urlComponents.queryItems = newValue
                // Must encode "+" to %2B (URLComponents does not do this)
                urlComponents.percentEncodedQuery = urlComponents.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
                request.url = urlComponents.url
            }
        }
        get {
            if let currentURL = request.url, let urlComponents = URLComponents(url: currentURL, resolvingAgainstBaseURL: false) {
                return urlComponents.queryItems
            }
            return nil
        }
    }

    /// Initialize a `RestRequest` instance.
    ///
    /// ### Usage Example: ###
    /// ```swift
    /// let request = RestRequest(method: .get, url: "http://myApiCall/hello")
    /// ```
    ///
    /// - Parameters:
    ///   - method: The method specified in the request, defaults to GET.
    ///   - url: URL string to use for the network request.
    ///   - containsSelfSignedCert: Pass `True` to use self signed certificates.
    ///   - clientCertificate: Pass in `ClientCertificate` with the certificate name and path to use client certificates for 2-way SSL.
    public init(method: HTTPMethod = .get, url: String, containsSelfSignedCert: Bool? = false, clientCertificate: ClientCertificate? = nil) {

        self.isSecure = url.hasPrefix("https")
        self.isSelfSigned = containsSelfSignedCert ?? false
        self.clientCertificate = clientCertificate

        // Instantiate basic mutable request
        let urlComponents = URLComponents(string: url) ?? URLComponents(string: "")!
        let urlObject = urlComponents.url ?? URL(string: "n/a")!
        self.request = URLRequest(url: urlObject)

        // Set initial fields
        self.url = url

        super.init()

        if isSecure && isSelfSigned {
            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        }
        
        self.method = method
        self.acceptType = "application/json"
        self.contentType = "application/json"

        // We accept URLs with templated values which `URLComponents` does not treat as valid
        if URLComponents(string: url) == nil {
            self.urlTemplate = url
        }
    }

    // MARK: Response methods
    /// Request response method that either invokes `CircuitBreaker` or executes the HTTP request.
    ///
    /// - Parameter completionHandler: Callback used on completion of operation.
    public func response(completionHandler: @escaping (Data?, HTTPURLResponse?, Error?) -> Void) {
        if let breaker = circuitBreaker {
            breaker.run(commandArgs: completionHandler, fallbackArgs: "Circuit is open")
        } else {
            let task = session.dataTask(with: request) { (data, response, error) in
                guard error == nil, let response = response as? HTTPURLResponse else {
                    completionHandler(nil, nil, error)
                    return
                }

                let code = response.statusCode
                if code >= 200 && code < 300 {
                    completionHandler(data, response, error)
                } else {
                    completionHandler(data,
                                      response,
                                      RestError.erroredResponseStatus(code))
                }
            }
            task.resume()
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
                             completionHandler: @escaping (RestResponse<Data>) -> Void) {

        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<Data>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result, cookies: nil)
            completionHandler(dataResponse)
            return
        }

        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            self.queryItems = queryItems
        }

        response { data, response, error in

            if let error = error {
                let result = Result<Data>.failure(error)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            guard let data = data else {
                let result = Result<Data>.failure(RestError.noData)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }
            let result = Result.success(data)
            let cookies = self.getCookies(from: response)
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
            completionHandler(dataResponse)
        }
    }

    /// Request response method with the expected result of the object `T` specified.
    ///
    /// - Parameters:
    ///   - responseToError: Error callback closure in case of request failure.
    ///   - path: Array of Json keys leading to desired JSON.
    ///   - templateParams: URL templating parameters used for substitution if possible.
    ///   - queryItems: Sets the query parameters for this RestRequest, overwriting any existing parameters. Defaults to `nil`, which means that this parameter will be ignored, and `RestRequest.queryItems` will be used instead. Note that if you wish to clear any existing query parameters, then you should set `request.queryItems = nil` before calling this function.
    ///   - completionHandler: Callback used on completion of operation.
    public func responseObject<T: JSONDecodable>(
        responseToError: ((HTTPURLResponse?, Data?) -> Error?)? = nil,
        path: [JSONPathType]? = nil,
        templateParams: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        completionHandler: @escaping (RestResponse<T>) -> Void) {

        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<T>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result, cookies: nil)
            completionHandler(dataResponse)
            return
        }

        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            self.queryItems = queryItems
        }

        response { data, response, error in

            if let error = error {
                let result = Result<T>.failure(error)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            if let responseToError = responseToError,
                let error = responseToError(response, data) {
                let result = Result<T>.failure(error)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            // ensure data is not nil
            guard let data = data else {
                let result = Result<T>.failure(RestError.noData)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            // parse json object
            let result: Result<T>
            do {
                let json = try JSONWrapper(data: data)
                let object: T
                if let path = path {
                    switch path.count {
                    case 0: object = try json.decode()
                    case 1: object = try json.decode(at: path[0])
                    case 2: object = try json.decode(at: path[0], path[1])
                    case 3: object = try json.decode(at: path[0], path[1], path[2])
                    case 4: object = try json.decode(at: path[0], path[1], path[2], path[3])
                    case 5: object = try json.decode(at: path[0], path[1], path[2], path[3], path[4])
                    default: throw JSONWrapper.Error.keyNotFound(key: "ExhaustedVariadicParameterEncoding")
                    }
                } else {
                    object = try json.decode()
                }
                result = .success(object)
            } catch {
                result = .failure(error)
            }

            // execute callback
            let cookies = self.getCookies(from: response)
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
            completionHandler(dataResponse)
        }
    }

    /// Request response method with the expected result of the object `T` specified.
    ///
    /// - Parameters:
    ///   - responseToError: Error callback closure in case of request failure.
    ///   - templateParams: URL templating parameters used for substitution if possible.
    ///   - queryItems: Sets the query parameters for this RestRequest, overwriting any existing parameters. Defaults to `nil`, which means that this parameter will be ignored, and `RestRequest.queryItems` will be used instead. Note that if you wish to clear any existing query parameters, then you should set `request.queryItems = nil` before calling this function.
    ///   - completionHandler: Callback used on completion of operation.
    public func responseObject<T: Decodable>(
        responseToError: ((HTTPURLResponse?, Data?) -> Error?)? = nil,
        templateParams: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        completionHandler: @escaping (RestResponse<T>) -> Void) {

        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<T>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result, cookies: nil)
            completionHandler(dataResponse)
            return
        }

        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            self.queryItems = queryItems
        }

        response { data, response, error in

            if let error = error ?? responseToError?(response, data) {
                let result = Result<T>.failure(error)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            // ensure data is not nil
            guard let data = data else {
                let result = Result<T>.failure(RestError.noData)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            // parse json object
            let result: Result<T>
            do {
                let object = try JSONDecoder().decode(T.self, from: data)
                result = .success(object)
            } catch {
                result = .failure(error)
            }

            // execute callback
            let cookies = self.getCookies(from: response)
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
            completionHandler(dataResponse)
        }
    }

    /// Request response method with the expected result of an array of type `T` specified.
    ///
    /// - Parameters:
    ///   - responseToError: Error callback closure in case of request failure.
    ///   - path: Array of JSON keys leading to desired JSON.
    ///   - templateParams: URL templating parameters used for substitution if possible.
    ///   - queryItems: Sets the query parameters for this RestRequest, overwriting any existing parameters. Defaults to `nil`, which means that this parameter will be ignored, and `RestRequest.queryItems` will be used instead. Note that if you wish to clear any existing query parameters, then you should set `request.queryItems = nil` before calling this function.
    ///   - completionHandler: Callback used on completion of operation.
    public func responseArray<T: JSONDecodable>(
        responseToError: ((HTTPURLResponse?, Data?) -> Error?)? = nil,
        path: [JSONPathType]? = nil,
        templateParams: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        completionHandler: @escaping (RestResponse<[T]>) -> Void) {

        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<[T]>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result, cookies: nil)
            completionHandler(dataResponse)
            return
        }

        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            self.queryItems = queryItems
        }

        response { data, response, error in

            if let error = error {
                let result = Result<[T]>.failure(error)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            if let responseToError = responseToError,
                let error = responseToError(response, data) {
                let result = Result<[T]>.failure(error)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            // ensure data is not nil
            guard let data = data else {
                let result = Result<[T]>.failure(RestError.noData)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            // parse json object
            let result: Result<[T]>
            do {
                let json = try JSONWrapper(data: data)
                var array: [JSONWrapper]
                if let path = path {
                    switch path.count {
                    case 0: array = try json.getArray()
                    case 1: array = try json.getArray(at: path[0])
                    case 2: array = try json.getArray(at: path[0], path[1])
                    case 3: array = try json.getArray(at: path[0], path[1], path[2])
                    case 4: array = try json.getArray(at: path[0], path[1], path[2], path[3])
                    case 5: array = try json.getArray(at: path[0], path[1], path[2], path[3], path[4])
                    default: throw JSONWrapper.Error.keyNotFound(key: "ExhaustedVariadicParameterEncoding")
                    }
                } else {
                    array = try json.getArray()
                }
                let objects: [T] = try array.map { json in try json.decode() }
                result = .success(objects)
            } catch {
                result = .failure(error)
            }

            // execute callback
            let cookies = self.getCookies(from: response)
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
            completionHandler(dataResponse)
        }
    }

    /// Request response method with the expected result of a `String`.
    ///
    /// - Parameters:
    ///   - responseToError: Error callback closure in case of request failure.
    ///   - templateParams: URL templating parameters used for substituion if possible.
    ///   - queryItems: Sets the query parameters for this RestRequest, overwriting any existing parameters. Defaults to `nil`, which means that this parameter will be ignored, and `RestRequest.queryItems` will be used instead. Note that if you wish to clear any existing query parameters, then you should set `request.queryItems = nil` before calling this function.
    ///   - completionHandler: Callback used on completion of operation.
    public func responseString(
        responseToError: ((HTTPURLResponse?, Data?) -> Error?)? = nil,
        templateParams: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        completionHandler: @escaping (RestResponse<String>) -> Void) {

        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<String>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result, cookies: nil)
            completionHandler(dataResponse)
            return
        }

        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            self.queryItems = queryItems
        }

        response { data, response, error in

            if let error = error {
                let result = Result<String>.failure(error)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            if let responseToError = responseToError,
                let error = responseToError(response, data) {
                let result = Result<String>.failure(error)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            // ensure data is not nil
            guard let data = data else {
                let result = Result<String>.failure(RestError.noData)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            // Retrieve string encoding type
            let encoding = self.getCharacterEncoding(from: response?.allHeaderFields["Content-Type"] as? String)

            // parse data as a string
            guard let string = String(data: data, encoding: encoding) else {
                let result = Result<String>.failure(RestError.serializationError)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            // execute callback
            let result = Result.success(string)
            let cookies = self.getCookies(from: response)
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
            completionHandler(dataResponse)
        }
    }

    /// Request response method to use when there is no expected result.
    ///
    /// - Parameters:
    ///   - responseToError: Error callback closure in case of request failure.
    ///   - templateParams: URL templating parameters used for substituion if possible.
    ///   - queryItems: Sets the query parameters for this RestRequest, overwriting any existing parameters. Defaults to `nil`, which means that this parameter will be ignored, and `RestRequest.queryItems` will be used instead. Note that if you wish to clear any existing query parameters, then you should set `request.queryItems = nil` before calling this function.
    ///   - completionHandler: Callback used on completion of operation.
    public func responseVoid(
        responseToError: ((HTTPURLResponse?, Data?) -> Error?)? = nil,
        templateParams: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        completionHandler: @escaping (RestResponse<Void>) -> Void) {

        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<Void>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result, cookies: nil)
            completionHandler(dataResponse)
            return
        }

        // Replace any existing query items with those provided in the queryItems
        // parameter, if any were given.
        if let queryItems = queryItems {
            self.queryItems = queryItems
        }

        response { data, response, error in

            if let error = error {
                let result = Result<Void>.failure(error)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            if let responseToError = responseToError, let error = responseToError(response, data) {
                let result = Result<Void>.failure(error)
                let cookies = self.getCookies(from: response)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
                completionHandler(dataResponse)
                return
            }

            // execute callback
            let result = Result<Void>.success(())
            let cookies = self.getCookies(from: response)
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result, cookies: cookies)
            completionHandler(dataResponse)
        }
    }

    /// Utility method to download a file from a remote origin.
    ///
    /// - Parameters:
    ///   - destination: URL destination to save the file to.
    ///   - completionHandler: Callback used on completion of the operation.
    public func download(to destination: URL, completionHandler: @escaping (HTTPURLResponse?, Error?) -> Void) {
        let task = session.downloadTask(with: request) { (source, response, error) in
            do {
                guard let source = source else {
                    throw RestError.invalidFile
                }
                let fileManager = FileManager.default
                try fileManager.moveItem(at: source, to: destination)

                completionHandler(response as? HTTPURLResponse, error)

            } catch {
                completionHandler(nil, RestError.fileManagerError)
            }
        }
        task.resume()
    }

    /// Method used by `CircuitBreaker` as the contextCommand.
    ///
    /// - Parameter invocation: `Invocation` contains a command argument, `Void` return type, and a `String` fallback arguement.
    private func handleInvocation(invocation: Invocation<(Data?, HTTPURLResponse?, Error?) -> Void, String>) {
        let task = session.dataTask(with: request) { (data, response, error) in
            if error != nil {
                invocation.notifyFailure(error: BreakerError(reason: error?.localizedDescription))
            } else {
                invocation.notifySuccess()
            }
            let callback = invocation.commandArgs
            callback(data, response as? HTTPURLResponse, error)
        }
        task.resume()

    }

    /// Method to perform substitution on `String` URL if it contains templated placeholders
    ///
    /// - Parameter params: dictionary of parameters to substitute in
    /// - Returns: returns either a `RestError` or nil if there were no problems setting new URL on our `URLRequest` object
    private func performSubstitutions(params: [String: String]?) -> RestError? {

        guard let params = params else {
            return nil
        }

        // Get urlTemplate if available, otherwise just use the request's url
        let urlString = (self.urlTemplate ?? self.url).expandString(params: params)

        // Confirm that the resulting URL is valid
        guard let urlComponents = URLComponents(string: urlString) else {
            return RestError.invalidSubstitution
        }

        // Replace the unexpanded URL with the expanded one.
        self.request.url = urlComponents.url
        self.url = urlString

        return nil
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

/// Contains data associated with a finished network request,
/// with `T` being the type of response we expect to receive.
public struct RestResponse<T> {

    /// The rest request.
    public let request: URLRequest?

    /// The response to the request.
    public let response: HTTPURLResponse?

    /// The Response Data.
    public let data: Data?

    /// The Reponse Result.
    public let result: Result<T>

    /// The cookies from HTTPURLResponse
    public let cookies: [HTTPCookie]?
}

/// Enum to differentiate a success or failure.
public enum Result<T> {
    /// A success of generic type `T`.
    case success(T)

    /// A failure with an `Error` object.
    case failure(Error)
}

/// Enum used to specify the type of authentication being used.
public enum Credentials {
    /// An API key is being used, no additional data needed.
    case apiKey

    /// Note: The bearer token should be base64 encoded.
    case bearerAuthentication(token: String)

    /// A basic username/password authentication is being used with the values passed in.
    case basicAuthentication(username: String, password: String)
}

/// Enum describing error types that can occur during a rest request and response.
public enum RestError: Error, CustomStringConvertible {

    /// No data was returned from the network.
    case noData

    /// Data couldn't be parsed correctly.
    case serializationError

    /// Failure to encode data into a certain format.
    case encodingError

    /// Failure in file manipulation.
    case fileManagerError

    /// The file trying to be accessed is invalid.
    case invalidFile

    /// The url substitution attempted could not be made.
    case invalidSubstitution

    /// Error response status.
    case erroredResponseStatus(Int)

    /// Error Description
    public var description: String {
        switch self {
        case .noData                        : return "No Data"
        case .serializationError            : return "Serialization Error"
        case .encodingError                 : return "Encoding Error"
        case .fileManagerError              : return "File Manager Error"
        case .invalidFile                   : return "Invalid File"
        case .invalidSubstitution           : return "Invalid Data"
        case .erroredResponseStatus(let s)  : return "Error HTTP Response: `\(s)`"
        }
    }

    /// Computed Property to extract the error code.
    public var code: Int? {
        switch self {
        case .erroredResponseStatus(let status): return status
        default: return nil
        }
    }
}

// URL Session extension
extension RestRequest: URLSessionDelegate {

    /// URL session function to allow trusting certain URLs.
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        let host = challenge.protectionSpace.host

        guard let url = URLComponents(string: self.url), let baseHost = url.host else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        
        let warning = "Attempting to establish a secure connection; This is only supported by macOS 10.6 or higher. Resorting to default handling."

        switch (method, host) {
        case (NSURLAuthenticationMethodClientCertificate, baseHost):
            #if os(macOS)
            guard let certificateName = self.clientCertificate?.name, let certificatePath = self.clientCertificate?.path else {
                Log.warning(warning)
                fallthrough
            }
            // Get the bundle path from the Certificates directory for a certificate that matches clientCertificateName's name
            if let path = Bundle.path(forResource: certificateName, ofType: "der", inDirectory: certificatePath) {
                // Read the certificate data from disk
                if let key = NSData(base64Encoded: path) {
                    // Create a secure certificate from the NSData
                    if let certificate = SecCertificateCreateWithData(kCFAllocatorDefault, key) {
                        // Create a secure identity from the certificate
                        var identity: SecIdentity? = nil
                        let _: OSStatus = SecIdentityCreateWithCertificate(nil, certificate, &identity)
                        guard let id = identity else {
                            Log.warning(warning)
                            fallthrough
                        }
                        completionHandler(.useCredential, URLCredential(identity: id, certificates: [certificate], persistence: .forSession))
                    }
                }
            }
            #else
            Log.warning(warning)
            fallthrough
            #endif
        case (NSURLAuthenticationMethodServerTrust, baseHost):
            #if !os(Linux)
            guard #available(iOS 3.0, macOS 10.6, *), let trust = challenge.protectionSpace.serverTrust else {
                Log.warning(warning)
                fallthrough
            }

            let credential = URLCredential(trust: trust)
            completionHandler(.useCredential, credential)

            #else
            Log.warning(warning)
            fallthrough
            #endif
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }

}

/// Represents a reference to a client certificate.
public struct ClientCertificate {
    /// The name for the client certificate.
    public let name: String
    /// The path to the client certificate.
    public let path: String

    /// Initialize a `ClientCertificate` instance.
    public init(name: String, path: String) {
      self.name = name
      self.path = path
    }
}
