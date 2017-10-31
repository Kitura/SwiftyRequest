/**
 * Copyright IBM Corporation 2016
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

// MARK: JSON Paths

/// Designates JSON Path Types
public protocol JSONPathType {

    /// Method to extract a JSON value from a [String: Any]
    func value(in dictionary: [String: Any]) throws -> JSONWrapper

    /// Method to extract a JSON value from a [Any]
    func value(in array: [Any]) throws -> JSONWrapper
}

extension String: JSONPathType {

    /// Method to instantiate a JSON object
    ///
    /// - Parameter dictionary: [String: Any] object to convert to JSON
    /// - Returns: JSON Object
    public func value(in dictionary: [String: Any]) throws -> JSONWrapper {
        guard let json = dictionary[self] else {
            throw JSONWrapper.Error.keyNotFound(key: self)
        }
        return JSONWrapper(json: json)
    }

    /// Method to instantiate a JSON object
    ///
    /// - Parameter dictionary: [Any] object to convert to JSON
    /// - Returns: JSON Object
    public func value(in array: [Any]) throws -> JSONWrapper {
        throw JSONWrapper.Error.unexpectedSubscript(type: String.self)
    }
}

extension Int: JSONPathType {

    /// Method to instantiate a JSON object
    ///
    /// - Parameter dictionary: [String: Any] object to convert to JSON
    /// - Returns: JSON Object
    public func value(in dictionary: [String: Any]) throws -> JSONWrapper {
        throw JSONWrapper.Error.unexpectedSubscript(type: Int.self)
    }

    /// Method to instantiate a JSON object
    ///
    /// - Parameter dictionary: [Any] object to convert to JSON
    /// - Returns: JSON Object
    public func value(in array: [Any]) throws -> JSONWrapper {
        let json = array[self]
        return JSONWrapper(json: json)
    }
}

// MARK: - JSON

/// Object encapsulating a JSON object
public struct JSONWrapper {
    fileprivate let json: Any

    /// Initializes a `JSON` instance from an Any Object
    public init(json: Any) {
        self.json = json
    }

    /// Initializes a `JSON` instance from a string
    public init(string: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw Error.encodingError
        }
        json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
    }

    /// Initialize a `JSON` instance from a Data Object
    public init(data: Data) throws {
        json = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
    }

    /// Initialize a `JSON` instance from a [String: Any]
    public init(dictionary: [String: Any]) {
        json = dictionary
    }

    /// Initialize a `JSON` instance from a [Any]
    public init(array: [Any]) {
        json = array
    }

    /// Method to Serialize a JSON object
    ///
    /// - Returns: Data object for a serialized JSON Object
    public func serialize() throws -> Data {
        return try JSONSerialization.data(withJSONObject: json, options: [])
    }

    /// Method to Serialize a JSON string
    ///
    /// - Returns: String of the serialized JSON Object
    public func serializeString() throws -> String {
        let data = try serialize()
        guard let string = String(data: data, encoding: .utf8) else {
            throw Error.stringSerializationError
        }
        return string
    }

    /// Method to retrieve a JSON value from a JSONPathType
    ///
    /// - Parameter path: JSONPathType
    /// - Returns: The JSON object at that path
    private func value(at path: JSONPathType) throws -> JSONWrapper {
        if let dictionary = json as? [String: Any] {
            return try path.value(in: dictionary)
        }
        if let array = json as? [Any] {
            return try path.value(in: array)
        }
        throw Error.unexpectedSubscript(type: type(of: path))
    }

    /// Method to retrieve a JSON value from a [JSONPathType]
    ///
    /// - Parameter path: [JSONPathType]
    /// - Returns: The JSON object at that path
    private func value(at path: [JSONPathType]) throws -> JSONWrapper {
        var value = self
        for fragment in path {
            value = try value.value(at: fragment)
        }
        return value
    }

    /// Decodes the designated JSONDecodable object at the given JSONPathType
    ///
    /// - Parameter path: [JSONPathType]
    /// - Parameter type: The type to decode
    /// - Returns: The decoded object
    public func decode<Decoded: JSONDecodable>(at path: JSONPathType..., type: Decoded.Type = Decoded.self) throws -> Decoded {
        return try Decoded(json: value(at: path))
    }

    /// Method to Retrieve Double
    /// - Parameter: JSONPathType...
    /// - Returns: Double
    public func getDouble(at path: JSONPathType...) throws -> Double {
        return try Double(json: value(at: path))
    }

    /// Method to Retrieve Double
    /// - Parameter: JSONPathType...
    /// - Returns: Double
    public func getInt(at path: JSONPathType...) throws -> Int {
        return try Int(json: value(at: path))
    }

    /// Method to Retrieve String
    /// - Parameter: JSONPathType...
    /// - Returns: Double
    public func getString(at path: JSONPathType...) throws -> String {
        return try String(json: value(at: path))
    }

    /// Method to Retrieve Bool
    /// - Parameter: JSONPathType...
    /// - Returns: Double
    public func getBool(at path: JSONPathType...) throws -> Bool {
        return try Bool(json: value(at: path))
    }

    /// Method to Retrieve JSON Array
    /// - Parameter: JSONPathType...
    /// - Returns: Double
    public func getArray(at path: JSONPathType...) throws -> [JSONWrapper] {
        let json = try value(at: path)
        guard let array = json.json as? [Any] else {
            throw Error.valueNotConvertible(value: json, to: [JSONWrapper].self)
        }
        return array.map { JSONWrapper(json: $0) }
    }

    /// Decodes the designated [JSONDecodable] object at the given JSONPathType
    ///
    /// - Parameter path: [JSONPathType]
    /// - Parameter type: The type to decode
    /// - Returns: The decoded array object
    public func decodedArray<Decoded: JSONDecodable>(at path: JSONPathType..., type: Decoded.Type = Decoded.self) throws -> [Decoded] {
        let json = try value(at: path)
        guard let array = json.json as? [Any] else {
            throw Error.valueNotConvertible(value: json, to: [Decoded].self)
        }
        return try array.map { try Decoded(json: JSONWrapper(json: $0)) }
    }

    /// Decodes the designated [String: JSONDecodable] object at the given JSONPathType
    ///
    /// - Parameter path: [JSONPathType]
    /// - Parameter type: The value type to decode
    /// - Returns: The decoded [String: Decoded]
    public func decodedDictionary<Decoded: JSONDecodable>(at path: JSONPathType..., type: Decoded.Type = Decoded.self) throws -> [String: Decoded] {
        let json = try value(at: path)
        guard let dictionary = json.json as? [String: Any] else {
            throw Error.valueNotConvertible(value: json, to: [String: Decoded].self)
        }
        var decoded = [String: Decoded](minimumCapacity: dictionary.count)
        for (key, value) in dictionary {
            decoded[key] = try Decoded(json: JSONWrapper(json: value))
        }
        return decoded
    }

    /// Method to Retrieve JSON from JSONPathType
    /// - Parameter: JSONPathType...
    /// - Returns: Any
    public func getJSON(at path: JSONPathType...) throws -> Any {
        return try value(at: path).json
    }

    /// Method to Retrieve [String: JSON] from JSONPathType
    /// - Parameter: JSONPathType...
    /// - Returns: [String: JSON]
    public func getDictionary(at path: JSONPathType...) throws -> [String: JSONWrapper] {
        let json = try value(at: path)
        guard let dictionary = json.json as? [String: Any] else {
            throw Error.valueNotConvertible(value: json, to: [String: JSONWrapper].self)
        }
        return dictionary.map { JSONWrapper(json: $0) }
    }

    /// Method to Retrieve [String: Any] from JSONPathType
    /// - Parameter: JSONPathType...
    /// - Returns: [String: Any]
    public func getDictionaryObject(at path: JSONPathType...) throws -> [String: Any] {
        let json = try value(at: path)
        guard let dictionary = json.json as? [String: Any] else {
            throw Error.valueNotConvertible(value: json, to: [String: JSONWrapper].self)
        }
        return dictionary
    }
}

// MARK: - JSON Errors

extension JSONWrapper {

    /// Enum to describe JSON errors
    public enum Error: Swift.Error {
        /// The designated index was out of bounds
        case indexOutOfBounds(index: Int)

        /// The designated key was not found
        case keyNotFound(key: String)

        /// The subscript was unexpected
        case unexpectedSubscript(type: JSONPathType.Type)

        /// JSONPathType was not convertible to Type
        case valueNotConvertible(value: JSONWrapper, to: Any.Type)

        /// There was an error while encoding
        case encodingError

        /// The data could not be serialized to a string
        case stringSerializationError
    }
}

// MARK: - JSON Protocols

/// Designates a type capable of being decoded from JSON
public protocol JSONDecodable {

    /// Initializes a JSONDecodable instance from JSON
    init(json: JSONWrapper) throws
}

/// Designates a type capable of encoding to JSON
public protocol JSONEncodable {

    /// Method to encode self as JSON
    func toJSON() -> JSONWrapper

    /// Method to encode self to Any JSON object
    func toJSONObject() -> Any
}

extension JSONEncodable {

    /// Default implementation to encode type instances to JSON
    public func toJSON() -> JSONWrapper {
        return JSONWrapper(json: self.toJSONObject())
    }
}

extension Double: JSONDecodable {

    /// Initializes a `Double` from a JSON object
    public init(json: JSONWrapper) throws {
        let any = json.json
        if let double = any as? Double {
            self = double
        } else if let int = any as? Int {
            self = Double(int)
        } else if let string = any as? String, let double = Double(string) {
            self = double
        } else {
            throw JSONWrapper.Error.valueNotConvertible(value: json, to: Double.self)
        }
    }
}

extension Int: JSONDecodable {

    /// Initializes an `Int` from a JSON object
    public init(json: JSONWrapper) throws {
        let any = json.json
        if let int = any as? Int {
            self = int
        } else if let double = any as? Double, double <= Double(Int.max) {
            self = Int(double)
        } else if let string = any as? String, let int = Int(string) {
            self = int
        } else {
            throw JSONWrapper.Error.valueNotConvertible(value: json, to: Int.self)
        }
    }
}

extension Bool: JSONDecodable {

    /// Initializes a `Bool` from a JSON object
    public init(json: JSONWrapper) throws {
        let any = json.json
        if let bool = any as? Bool {
            self = bool
        } else {
            throw JSONWrapper.Error.valueNotConvertible(value: json, to: Bool.self)
        }
    }
}

extension String: JSONDecodable {

    /// Initializes a `String` from a JSON object
    public init(json: JSONWrapper) throws {
        let any = json.json
        if let string = any as? String {
            self = string
        } else if let int = any as? Int {
            self = String(int)
        } else if let bool = any as? Bool {
            self = String(bool)
        } else if let double = any as? Double {
            self = String(double)
        } else {
            throw JSONWrapper.Error.valueNotConvertible(value: json, to: String.self)
        }
    }
}
