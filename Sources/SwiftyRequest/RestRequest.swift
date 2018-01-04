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

/// Object containing everything needed to build HTTP requests and execute them
public class RestRequest: NSObject  {
    
    // Check if there exists a self-signed certificate and whether it's a secure connection
    private let isSecure: Bool
    private let isSelfSigned: Bool
    
    /// A default `URLSession` instance
    private var session: URLSession {
        var session = URLSession(configuration: URLSessionConfiguration.default)
        if isSecure && isSelfSigned {
            let config = URLSessionConfiguration.default
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        }
        return session
    }
    
    // The HTTP Request
    private var request: URLRequest
    
    /// `CircuitBreaker` instance for this `RestRequest`
    public var circuitBreaker: CircuitBreaker<(Data?, HTTPURLResponse?, Error?) -> Void, Void, String>?
    
    /// Parameters for a `CircuitBreaker` instance.
    /// When set, a new circuitBreaker instance is created
    public var circuitParameters: CircuitParameters<String>? = nil {
        didSet {
            if let params = circuitParameters {
                circuitBreaker = CircuitBreaker(timeout: params.timeout,
                                                resetTimeout: params.resetTimeout,
                                                maxFailures: params.maxFailures,
                                                rollingWindow: params.rollingWindow,
                                                bulkhead: params.bulkhead,
                                                contextCommand: handleInvocation,
                                                fallback: params.fallback)
            }
        }
    }
    
    // MARK: HTTP Request Paramters
    /// URL `String` used to store a url containing replacable template values
    private var urlTemplate: String?
    
    /// The string representation of HTTP request url
    private var url: String
    
    /// The HTTP request method: defaults to Get
    public var method: HTTPMethod {
        get {
            return HTTPMethod(fromRawValue: request.httpMethod ?? "unknown")
        }
        set {
            request.httpMethod = newValue.rawValue
        }
    }
    
    /// HTTP Credentials
    public var credentials: Credentials? {
        didSet {
            // set the request's authentication credentials
            if let credentials = credentials {
                switch credentials {
                case .apiKey: break
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
    
    /// HTTP Header Parameters
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
    
    /// HTTP Accept Type Header: defaults to application/json
    public var acceptType: String? {
        get {
            return request.value(forHTTPHeaderField: "Accept")
        }
        set {
            request.setValue(newValue, forHTTPHeaderField: "Accept")
        }
    }
    
    /// HTTP Content Type Header: defaults to application/json
    public var contentType: String? {
        get {
            return request.value(forHTTPHeaderField: "Content-Type")
        }
        set {
            request.setValue(newValue, forHTTPHeaderField: "Content-Type")
        }
    }
    
    /// HTTP User-Agent Header
    public var productInfo: String? {
        get {
            return request.value(forHTTPHeaderField: "User-Agent")
        }
        set {
            request.setValue(newValue?.generateUserAgent(), forHTTPHeaderField: "User-Agent")
        }
    }
    
    /// HTTP Message Body
    public var messageBody: Data? {
        get {
            return request.httpBody
        }
        set {
            request.httpBody = newValue
        }
    }
    
    /// HTTP Request Query Items
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
            if let currentURL = request.url, var urlComponents = URLComponents(url: currentURL, resolvingAgainstBaseURL: false) {
                return urlComponents.queryItems
            }
            return nil
        }
    }
    
    /// Initialize a `RestRequest` instance
    ///
    /// - Parameters:
    ///   - url: URL string to use for network request
    public init(method: HTTPMethod = .get, url: String, containsSelfSignedCert: Bool? = false) {
        
        self.isSecure = url.contains("https")
        self.isSelfSigned = containsSelfSignedCert ?? false
        
        // Instantiate basic mutable request
        let urlComponents = URLComponents(string: url) ?? URLComponents(string: "")!
        let urlObject = urlComponents.url ?? URL(string: "n/a")!
        self.request = URLRequest(url: urlObject)
        
        // Set inital fields
        self.url = url
        
        super.init()
        
        self.method = method
        self.acceptType = "application/json"
        self.contentType = "application/json"
        
        // We accept URLs with templated values which `URLComponents` does not treat as valid
        if URLComponents(string: url) == nil {
            self.urlTemplate = url
        }
    }
    
    // MARK: Response methods
    /// Request response method that either invokes `CircuitBreaker` or executes the HTTP request
    ///
    /// - Parameter completionHandler: Callback used on completion of operation
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
    
    /// Request response method with the expected result of a `Data` object
    ///
    /// - Parameters:
    ///   - templateParams: URL templating parameters used for substituion if possible
    ///   - queryItems: array containing `URLQueryItem` objects that will be appended to the request's URL
    ///   - completionHandler: Callback used on completion of operation
    public func responseData(templateParams: [String: String]? = nil,
                             queryItems: [URLQueryItem]? = nil,
                             completionHandler: @escaping (RestResponse<Data>) -> Void) {
        
        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<Data>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result)
            completionHandler(dataResponse)
            return
        }
        
        self.queryItems = queryItems
        
        response { data, response, error in
            
            if let error = error {
                let result = Result<Data>.failure(error)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result)
                completionHandler(dataResponse)
                return
            }
            
            guard let data = data else {
                let result = Result<Data>.failure(RestError.noData)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result)
                completionHandler(dataResponse)
                return
            }
            let result = Result.success(data)
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result)
            completionHandler(dataResponse)
        }
    }
    
    /// Request response method with the expected result of the object, `T` specified
    ///
    /// - Parameters:
    ///   - responseToError: Error callback closure in case of request failure
    ///   - path: Array of Json keys leading to desired Json
    ///   - templateParams: URL templating parameters used for substituion if possible
    ///   - queryItems: array containing `URLQueryItem` objects that will be appended to the request's URL
    ///   - completionHandler: Callback used on completion of operation
    public func responseObject<T: JSONDecodable>(
        responseToError: ((HTTPURLResponse?, Data?) -> Error?)? = nil,
        path: [JSONPathType]? = nil,
        templateParams: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        completionHandler: @escaping (RestResponse<T>) -> Void) {
        
        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<T>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result)
            completionHandler(dataResponse)
            return
        }
        
        self.queryItems = queryItems
        
        response { data, response, error in
            
            if let error = error {
                let result = Result<T>.failure(error)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result)
                completionHandler(dataResponse)
                return
            }
            
            if let responseToError = responseToError,
                let error = responseToError(response, data) {
                let result = Result<T>.failure(error)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result)
                completionHandler(dataResponse)
                return
            }
            
            // ensure data is not nil
            guard let data = data else {
                let result = Result<T>.failure(RestError.noData)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result)
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
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result)
            completionHandler(dataResponse)
        }
    }
    
    /// Request response method with the expected result of an array of type `T` specified
    ///
    /// - Parameters:
    ///   - responseToError: Error callback closure in case of request failure
    ///   - path: Array of Json keys leading to desired Json
    ///   - templateParams: URL templating parameters used for substituion if possible
    ///   - queryItems: array containing `URLQueryItem` objects that will be appended to the request's URL
    ///   - completionHandler: Callback used on completion of operation
    public func responseObject<T: Decodable>(
        responseToError: ((HTTPURLResponse?, Data?) -> Error?)? = nil,
        templateParams: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        completionHandler: @escaping (RestResponse<T>) -> Void) {
        
        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<T>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result)
            completionHandler(dataResponse)
            return
        }
        
        response { data, response, error in
            
            if let error = error ?? responseToError?(response,data) {
                let result = Result<T>.failure(error)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result)
                completionHandler(dataResponse)
                return
            }
            
            // ensure data is not nil
            guard let data = data else {
                let result = Result<T>.failure(RestError.noData)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result)
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
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result)
            completionHandler(dataResponse)
        }
    }
    
    /// Request response method with the expected result of an array of type `T` specified
    ///
    /// - Parameters:
    ///   - responseToError: Error callback closure in case of request failure
    ///   - path: Array of Json keys leading to desired Json
    ///   - templateParams: URL templating parameters used for substituion if possible
    ///   - queryItems: array containing `URLQueryItem` objects that will be appended to the request's URL
    ///   - completionHandler: Callback used on completion of operation
    public func responseArray<T: JSONDecodable>(
        responseToError: ((HTTPURLResponse?, Data?) -> Error?)? = nil,
        path: [JSONPathType]? = nil,
        templateParams: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        completionHandler: @escaping (RestResponse<[T]>) -> Void) {
        
        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<[T]>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result)
            completionHandler(dataResponse)
            return
        }
        
        self.queryItems = queryItems
        
        response { data, response, error in
            
            if let error = error {
                let result = Result<[T]>.failure(error)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result)
                completionHandler(dataResponse)
                return
            }
            
            if let responseToError = responseToError,
                let error = responseToError(response, data) {
                let result = Result<[T]>.failure(error)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result)
                completionHandler(dataResponse)
                return
            }
            
            // ensure data is not nil
            guard let data = data else {
                let result = Result<[T]>.failure(RestError.noData)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result)
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
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result)
            completionHandler(dataResponse)
        }
    }
    
    /// Request response method with the expected result of a `String`
    ///
    /// - Parameters:
    ///   - responseToError: Error callback closure in case of request failure
    ///   - templateParams: URL templating parameters used for substituion if possible
    ///   - queryItems: array containing `URLQueryItem` objects that will be appended to the request's URL
    ///   - completionHandler: Callback used on completion of operation
    public func responseString(
        responseToError: ((HTTPURLResponse?, Data?) -> Error?)? = nil,
        templateParams: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        completionHandler: @escaping (RestResponse<String>) -> Void) {
        
        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<String>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result)
            completionHandler(dataResponse)
            return
        }
        
        self.queryItems = queryItems
        
        response { data, response, error in
            
            if let error = error {
                let result = Result<String>.failure(error)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result)
                completionHandler(dataResponse)
                return
            }
            
            if let responseToError = responseToError,
                let error = responseToError(response, data) {
                let result = Result<String>.failure(error)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result)
                completionHandler(dataResponse)
                return
            }
            
            // ensure data is not nil
            guard let data = data else {
                let result = Result<String>.failure(RestError.noData)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result)
                completionHandler(dataResponse)
                return
            }
            
            // parse data as a string
            guard let string = String(data: data, encoding: .utf8) else {
                let result = Result<String>.failure(RestError.serializationError)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result)
                completionHandler(dataResponse)
                return
            }
            
            // execute callback
            let result = Result.success(string)
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result)
            completionHandler(dataResponse)
        }
    }
    
    /// Request response method to use when there is no expected result
    ///
    /// - Parameters:
    ///   - responseToError: Error callback closure in case of request failure
    ///   - templateParams: URL templating parameters used for substituion if possible
    ///   - queryItems: array containing `URLQueryItem` objects that will be appended to the request's URL
    ///   - completionHandler: Callback used on completion of operation
    public func responseVoid(
        responseToError: ((HTTPURLResponse?, Data?) -> Error?)? = nil,
        templateParams: [String: String]? = nil,
        queryItems: [URLQueryItem]? = nil,
        completionHandler: @escaping (RestResponse<Void>) -> Void) {
        
        if  let error = performSubstitutions(params: templateParams) {
            let result = Result<Void>.failure(error)
            let dataResponse = RestResponse(request: request, response: nil, data: nil, result: result)
            completionHandler(dataResponse)
            return
        }
        
        self.queryItems = queryItems
        
        response { data, response, error in
            
            if let error = error {
                let result = Result<Void>.failure(error)
                let dataResponse = RestResponse(request: self.request, response: response, data: nil, result: result)
                completionHandler(dataResponse)
                return
            }
            
            if let responseToError = responseToError, let error = responseToError(response, data) {
                let result = Result<Void>.failure(error)
                let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result)
                completionHandler(dataResponse)
                return
            }
            
            // execute callback
            let result = Result<Void>.success(())
            let dataResponse = RestResponse(request: self.request, response: response, data: data, result: result)
            completionHandler(dataResponse)
        }
    }
    
    /// Utility method to download a file from a remote origin
    ///
    /// - Parameters:
    ///   - destination: URL destination to save the file to
    ///   - completionHandler: Callback used on completion of operation
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
    
    /// Method used by `CircuitBreaker` as the contextCommand
    ///
    /// - Parameter invocation: `Invocation` contains a command argument, Void return type, and a String fallback arguement
    private func handleInvocation(invocation: Invocation<(Data?, HTTPURLResponse?, Error?) -> Void, Void, String>) {
        let task = session.dataTask(with: request) { (data, response, error) in
            if error != nil {
                invocation.notifyFailure()
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
        let urlString = urlTemplate ?? url
        
        guard let urlComponents = urlString.expand(params: params) else {
            return RestError.invalidSubstitution
        }
        
        self.request.url = urlComponents.url
        
        return nil
    }
}

/// Encapsulates properties needed to initialize a `CircuitBreaker` object within the `RestRequest` init.
/// `A` is the type of the fallback's parameter
public struct CircuitParameters<A> {
    
    /// The circuit timeout: defaults to 1000
    let timeout: Int
    
    /// The circuit timeout: defaults to 60000
    let resetTimeout: Int
    
    /// Max failures allowed: defaults to 5
    let maxFailures: Int
    
    /// Rolling Window: defaults to 10000
    let rollingWindow: Int
    
    /// Bulkhead: defaults to 0
    let bulkhead: Int
    
    /// The error fallback callback
    let fallback: (BreakerError, A) -> Void
    
    /// Initialize a `CircuitPrameters` instance
    init(timeout: Int = 2000, resetTimeout: Int = 60000, maxFailures: Int = 5, rollingWindow: Int = 10000, bulkhead: Int = 0, fallback: @escaping (BreakerError, A) -> Void) {
        self.timeout = timeout
        self.resetTimeout = resetTimeout
        self.maxFailures = maxFailures
        self.rollingWindow = rollingWindow
        self.bulkhead = bulkhead
        self.fallback = fallback
    }
}

/// Contains data associated with a finished network request.
/// With `T` being the type of the response expected to be received
public struct RestResponse<T> {
    
    /// The rest request
    public let request: URLRequest?
    
    /// The response to the request
    public let response: HTTPURLResponse?
    
    /// The Response Data
    public let data: Data?
    
    /// The Reponse Result
    public let result: Result<T>
}

/// Enum to differentiate a success or failure
public enum Result<T> {
    /// a success of generic type `T`
    case success(T)
    
    /// a failure with an `Error` object
    case failure(Error)
}

/// Enum used to specify the type of authentication being used
public enum Credentials {
    /// an API key is being used, no additional data needed
    case apiKey
    
    /// a basic username/password authentication is being used with said value, passed in
    case basicAuthentication(username: String, password: String)
}

/// Enum describing error types that can occur during a rest request and response
public enum RestError: Error, CustomStringConvertible {
    
    /// no data was returned from the network
    case noData
    
    /// data couldn't be parsed correctly
    case serializationError
    
    /// failure to encode data into a certain format
    case encodingError
    
    /// failure in file manipulation
    case fileManagerError
    
    /// the file trying to be accessed is invalid
    case invalidFile
    
    /// the url substitution attempted could not be made
    case invalidSubstitution
    
    /// Error response status
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
    
    /// Computed Property to extract error code
    public var code: Int? {
        switch self {
        case .erroredResponseStatus(let status): return status
        default: return nil
        }
    }
}

// URL Session extension
extension RestRequest: URLSessionDelegate {
    
    /// URL session function to allow trusting certain URLs
    public func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let method = challenge.protectionSpace.authenticationMethod
        let host = challenge.protectionSpace.host
        switch (method, host) {
        case (NSURLAuthenticationMethodServerTrust, self.url):
            #if MAC_OS_X_VERSION_10_6
                let trust = challenge.protectionSpace.serverTrust
                let credential = URLCredential(trust: trust)
                completionHandler(.useCredential, credential)
            #else
                var optionalTrust: SecTrust? = nil
                let certArray = challenge.proposedCredential?.certificates
                let policy = SecPolicyCreateBasicX509()
                let trust = SecTrustCreateWithCertificates(certArray as AnyObject,
                                                           policy,
                                                           &optionalTrust)
                let credential = URLCredential(trust: trust as! SecTrust)
                completionHandler(.useCredential, credential)
            #endif
        default:
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
