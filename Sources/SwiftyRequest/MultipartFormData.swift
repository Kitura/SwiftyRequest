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

/// Object encapsulating a multipart form.
public class MultipartFormData {

    /// String denoting the `Content-Type` of the request header.
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

    /// Initialize a `MultipartFormData` instance.
    public init() {
        self.boundary = "swiftyrequest.boundary.bd0b4c6e3b9c2126"
    }

    /// Append a new body part to the multipart form, where the original data is in a file described by the `fileName` string.
    ///
    /// - Parameter Data: The data of the body part.
    /// - Parameter withName: The name/key of the body part.
    /// - Parameter mimeType: The MIME type of the body part.
    /// - Parameter fileName: The name of the file the data came from.
    /// - Returns: Returns a `Data` object encompassing the combined body parts.
    public func append(_ data: Data, withName: String, mimeType: String? = nil, fileName: String? = nil) {
        let bodyPart = BodyPart(key: withName, data: data, mimeType: mimeType, fileName: fileName)
        bodyParts.append(bodyPart)
    }

    /// Append a new body part to the multipart form, where the original data is in a url described by `fileURL`.
    ///
    /// - Parameter fileURL: The url to extract the data from.
    /// - Parameter withName: The name/key of the body part.
    /// - Parameter mimeType: The MIME type of the body part.
    /// - Returns: Returns a `Data` object encompassing the combined body parts.
    public func append(_ fileURL: URL, withName: String, mimeType: String? = nil) {
        if let data = try? Data.init(contentsOf: fileURL) {
            let bodyPart = BodyPart(key: withName, data: data, mimeType: mimeType, fileName: fileURL.lastPathComponent)
            bodyParts.append(bodyPart)
        }
    }

    /// Combine the multipart form body parts into a single `Data` object.
    ///
    /// - Returns: Returns a `Data` object encompassing the combined body parts.
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

/// Object encapsulating a singular part of a multipart form.
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

    /// Initialize a `BodyPart` instance.
    ///
    /// - Parameters:
    ///   - key: The body part identifier.
    ///   - value: The value of the `BodyPart`.
    public init?(key: String, value: Any) {
        let string = String(describing: value)
        guard let data = string.data(using: .utf8) else {
            return nil
        }

        self.key = key
        self.data = data
    }

    /// Initialize a `BodyPart` instance.
    ///
    /// - Parameters:
    ///   - key: The body part identifier.
    ///   - data: The data of the BodyPart.
    ///   - mimeType: The MIME type.
    ///   - fileType: The data's file name.
    public init(key: String, data: Data, mimeType: String? = nil, fileName: String? = nil) {
        self.key = key
        self.data = data
        self.mimeType = mimeType
        self.fileName = fileName
    }

    /// Construct the content of the `BodyPart`.
    ///
    /// - Returns: Returns a `Data` object consisting of the header and data.
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
