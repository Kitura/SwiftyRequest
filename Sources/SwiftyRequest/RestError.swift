/**
 * Copyright IBM Corporation 2019
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

import NIO
import NIOHTTP1
import AsyncHTTPClient

/// Enum describing error types that can occur during a rest request and response.
public struct RestError: Error, CustomStringConvertible, Equatable {
    
    /// No data was returned from the network.
    public static let noData = RestError(.noData, description: "No Data")
    
    /// Data couldn't be parsed correctly.
    public static let serializationError = RestError(.serializationError, description: "Serialization Error")
    
    /// Failure to encode data into a certain format.
    public static let encodingError = RestError(.encodingError, description: "Encoding Error")
    
    /// Failure to encode data into a certain format.
    public static let decodingError = RestError(.decodingError, description: "Decoding Error")
    
    /// Failure in file manipulation.
    public static let fileManagerError = RestError(.fileManagerError, description: "File Manager Error")
    
    /// The file trying to be accessed is invalid.
    public static let invalidFile = RestError(.invalidFile, description: "Invalid File")
    
    /// The url substitution attempted could not be made.
    public static let invalidSubstitution = RestError(.invalidSubstitution, description: "Invalid Data")

    /// The requested resource could not be downloaded.
    public static let downloadError = RestError(.downloadError, description: "Failed to download file")

    /// The url provided was not valid.
    public static let invalidURL = RestError(.invalidURL, description: "Invalid URL")

    /// The result was not a success status code in the 200 range.
    public static let errorStatusCode = RestError(.errorStatusCode, description: "Response status outside of 200 range")

    /// An HTTPClient error occurred before invoking the request. See the `error` property for the underlying error.
    public static let httpClientError = RestError(.otherError, description: "HTTPClientError")

    /// Another error occurred before invoking the request. See the `error` property for the underlying error.
    public static let otherError = RestError(.otherError, description: "Other Error")

    /// The url provided was not valid.
    static func invalidURL(_ url: String) -> RestError {
        return RestError(.invalidURL, description: "'\(url)' is not a valid URL")
    }

    /// No data was returned from the network.
    static func noData(response: HTTPClient.Response) -> RestError {
        return RestError(.noData, description: "No Data", response: response)
    } 
    
    /// No data was returned from the network.
    static func decodingError(error: Error, response: HTTPClient.Response) -> RestError {
        return RestError(.decodingError, description: "Decoding failed with error: \(error.localizedDescription)", response: response, error: error)
    }

    /// Data couldn't be parsed correctly.
    static func serializationError(response: HTTPClient.Response) -> RestError {
        return RestError(.serializationError, description: "Serialization Error", response: response)
    }
    
    /// The result was not a success status code in the 200 range.
    static func errorStatusCode(response: HTTPClient.Response) -> RestError {
        return RestError(.errorStatusCode, description: "HTTP response code: \(response.status.code)", response: response)
    }

    /// An HTTPClient error occurred before invoking the request. See the `error` property for the underlying error.
    static func httpClientError(_ error: HTTPClientError) -> RestError {
        return RestError(.httpClientError, description: "An HTTP client error occurred", error: error)
    }

    /// Another error occurred before invoking the request. See the `error` property for the underlying error.
    static func otherError(_ error: Error) -> RestError {
        return RestError(.otherError, description: "An error occurred", error: error)
    }
    
    private let internalError: InternalError
    
    private enum InternalError {
        case noData, serializationError, encodingError, decodingError, fileManagerError, invalidFile, invalidSubstitution, downloadError, errorStatusCode, invalidURL, httpClientError, otherError
    }

    private let _description: String

    /// Error Description
    public var description: String {
        if let response = response {
             return "\(_description) - status: \(response.status)"
        }
        if let error = error {
            return "\(_description) - underlying error: \(error)"
        }
        return _description
    }
    
    /// A human readable description of the error.
    public var localizedDescription: String {
        return description
    }
    
    /// The HTTP response that caused the error.
    public let response: HTTPClient.Response?

    /// The underlying error, if an error occurred before a request could be made.
    public let error: Error?

    private init(_ internalError: InternalError, description: String, response: HTTPClient.Response? = nil, error: Error? = nil) {
        self.internalError = internalError
        self._description = description
        self.response = response
        self.error = error
    }

    /// Function to check if two RestError instances are equal. Required for Equatable protocol.
    public static func == (lhs: RestError, rhs: RestError) -> Bool {
        return lhs.internalError == rhs.internalError
    }
    
    /// Function to enable pattern matching against generic Errors.
    public static func ~= (lhs: RestError, rhs: Error) -> Bool {
        guard let rhs = rhs as? RestError else {
            return false
        }
        return lhs == rhs
    }
}
