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
    public static let noData = RestError(internalError: .noData, _description: "No Data", response: nil)
    
    /// Data couldn't be parsed correctly.
    public static let serializationError = RestError(internalError: .serializationError, _description: "Serialization Error", response: nil)
    
    /// Failure to encode data into a certain format.
    public static let encodingError = RestError(internalError: .encodingError, _description: "Encoding Error", response: nil)
    
    /// Failure to encode data into a certain format.
    public static let decodingError = RestError(internalError: .decodingError, _description: "Decoding Error", response: nil)
    
    /// Failure in file manipulation.
    public static let fileManagerError = RestError(internalError: .fileManagerError, _description: "File Manager Error", response: nil)
    
    /// The file trying to be accessed is invalid.
    public static let invalidFile = RestError(internalError: .invalidFile, _description: "Invalid File", response: nil)
    
    /// The url substitution attempted could not be made.
    public static let invalidSubstitution = RestError(internalError: .invalidSubstitution, _description: "Invalid Data", response: nil)

    /// The requested resource could not be downloaded.
    public static let downloadError = RestError(internalError: .downloadError, _description: "Failed to download file", response: nil)
    
    /// The url provided was not valid.
    public static func invalidURL(description: String = "Invalid URL") -> RestError {
        return RestError(internalError: .invalidURL, _description: description, response: nil)
    }

    /// No data was returned from the network.
    public static func noData(response: HTTPClient.Response) -> RestError {
        return RestError(internalError: .noData, _description: "No Data", response: response)
    } 
    
    /// No data was returned from the network.
    public static func decodingError(error: Error, response: HTTPClient.Response) -> RestError {
        return RestError(internalError: .decodingError, _description: "Decoding failed with error: \(error.localizedDescription)", response: response)
    }

    /// Data couldn't be parsed correctly.
    public static func serializationError(response: HTTPClient.Response) -> RestError {
        return RestError(internalError: .serializationError, _description: "Serialization Error", response: response)
    }
    
    /// Data couldn't be parsed correctly.
    public static func errorStatusCode(response: HTTPClient.Response) -> RestError {
        return RestError(internalError: .errorStatusCode, _description: "Got response with Status code outside of 200 range", response: response)
    }
    
    private let internalError: InternalError
    
    private enum InternalError {
        case noData, serializationError, encodingError, decodingError, fileManagerError, invalidFile, invalidSubstitution, downloadError, errorStatusCode, invalidURL
    }

    private let _description: String

    /// Error Description
    public var description: String {
        if let response = response {
             return "\(_description) - status: \(response.status)"
         } else {
             return _description
         }
    }
    
    /// A human readable description of the error.
    public var localizedDescription: String {
        return description
    }
    
    /// The HTTP response that caused the error.
    public let response: HTTPClient.Response?
    
    
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
