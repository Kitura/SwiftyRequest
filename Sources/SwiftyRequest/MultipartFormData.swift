/**
 * Copyright IBM Corporation 2016-2017
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

/// Object encapsulating a Multipart Form
public class MultipartFormData {

    /// String denoting the Content Type
    public var contentType: String { return "multipart/form-data; boundary=\(boundary)" }

    // add contentLength?
    private let boundary: String
    private var bodyParts = [BodyPart]()

    private var initialBoundary: Data {
        let boundary = "--\(self.boundary)\r\n"
        return boundary.data(using: .utf8, allowLossyConversion: false)!
    }

    private var encapsulatedBoundary: Data {
        let boundary = "\r\n--\(self.boundary)\r\n"
        return boundary.data(using: .utf8, allowLossyConversion: false)!
    }

    private var finalBoundary: Data {
        let boundary = "\r\n--\(self.boundary)--\r\n"
        return boundary.data(using: .utf8, allowLossyConversion: false)!
    }

    /// Initialize a `MultipartFormData` instance
    public init() {
        self.boundary = "swiftyrequest.boundary.bd0b4c6e3b9c2126"
    }

    /// Method to create append a new body part to the multipart form.
    ///
    /// - Parameter Data: the data of the body part
    /// - Parameter withName: the name/key of the body part
    /// - Parameter mimeType: the mime type of the body part
    /// - Parameter fileName: the name of the file the data came from
    /// - Returns: returns a Data Object encompassing the combined body parts
    public func append(_ data: Data, withName: String, mimeType: String? = nil, fileName: String? = nil) {
        let bodyPart = BodyPart(key: withName, data: data, mimeType: mimeType, fileName: fileName)
        bodyParts.append(bodyPart)
    }

    /// Method to create append a new body part to the multipart form.
    ///
    /// - Parameter fileURL: the url with to extract the data from
    /// - Parameter withName: the name/key of the body part
    /// - Parameter mimeType: the mime type of the body part
    /// - Returns: returns a Data Object encompassing the combined body parts
    public func append(_ fileURL: URL, withName: String, mimeType: String? = nil) {
        if let data = try? Data.init(contentsOf: fileURL) {
            let bodyPart = BodyPart(key: withName, data: data, mimeType: mimeType, fileName: fileURL.lastPathComponent)
            bodyParts.append(bodyPart)
        }
    }

    /// Method to combine the Multipart form body parts in to a single Data Object
    ///
    /// - Returns: returns a Data Object encompassing the combined body parts
    public func toData() throws -> Data {
        var data = Data()
        for (index, bodyPart) in bodyParts.enumerated() {
            let bodyBoundary: Data
            if index == 0 {
                bodyBoundary = initialBoundary
            } else if index != 0 {
                bodyBoundary = encapsulatedBoundary
            } else {
                throw RestError.encodingError
            }

            data.append(bodyBoundary)
            data.append(try bodyPart.content())
        }

        data.append(finalBoundary)

        return data
    }
}

/// Object encapsulating a singular part of a Multipart form
public struct BodyPart {

    private(set) var key: String
    private(set) var data: Data
    private(set) var mimeType: String?
    private(set) var fileName: String?

    private var header: String {
        var header = "Content-Disposition: form-data; name=\"\(key)\""
        if let fileName = fileName {
            header += "; filename=\"\(fileName)\""
        }
        if let mimeType = mimeType {
            header += "\r\nContent-Type: \(mimeType)"
        }
        header += "\r\n\r\n"
        return header
    }

    /// Initialize a `BodyPart` instance
    ///
    /// - Parameters:
    ///   - key: the body part identifier
    ///   - value: the value of the BodyPart
    public init?(key: String, value: Any) {
        let string = String(describing: value)
        guard let data = string.data(using: .utf8) else {
            return nil
        }

        self.key = key
        self.data = data
    }

    /// Initialize a `BodyPart` instance
    ///
    /// - Parameters:
    ///   - key: the body part identifier
    ///   - data: the data of the BodyPart
    ///   - mimeType: the mime type
    ///   - fileType: the data's file name
    public init(key: String, data: Data, mimeType: String? = nil, fileName: String? = nil) {
        self.key = key
        self.data = data
        self.mimeType = mimeType
        self.fileName = fileName
    }

    /// Method to construct the content of the BodyPart
    ///
    /// - Returns: returns a Data Object consisting of the header and data
    public func content() throws -> Data {
        var result = Data()
        let headerString = header
        guard let header = headerString.data(using: .utf8) else {
            throw RestError.encodingError
        }
        result.append(header)
        result.append(data)
        return result
    }
}
