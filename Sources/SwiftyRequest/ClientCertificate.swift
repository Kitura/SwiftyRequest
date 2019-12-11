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

import Foundation
import AsyncHTTPClient
import NIOSSL

/// Represents an error while reading the data for a certificate or private key.
public struct CertificateError: Error, CustomStringConvertible, Equatable {
    private enum _CertificateError {
        case invalidPEMString, fileNotFound
    }
    private let internalError: _CertificateError

    /// A description of this error.
    public let description: String

    /// The given PEM string was invalid.
    public static let invalidPEMString = CertificateError(internalError: .invalidPEMString, description: "Invalid PEM string")
    /// The specified PEM file could not be found.
    public static let fileNotFound = CertificateError(internalError: .fileNotFound, description: "Specified PEM file was not found")

    public static func == (lhs: CertificateError, rhs: CertificateError) -> Bool {
        return lhs.internalError == rhs.internalError
    }
}

/// Represents a client certificate that should be provided as part of a RestRequest.
/// The certificate and its corresponding private key will be read from PEM formatted data.
/// If the private key is encrypted with a passphrase, the passphrase should also be supplied.
public struct ClientCertificate {
    public let certificate: NIOSSLCertificate
    public let privateKey: NIOSSLPrivateKey

    /// Initialize a `ClientCertificate` from an existing `NIOSSLCertificate` and `NIOSSLPrivateKey`.
    /// Use this method if you need complete control over how the certificate and key data is read in.
    /// - Parameter certificate: The client certificate.
    /// - Parameter privateKey: The private key for the certificate. If the data for the key is encrypted, then an appropriate passphrase callback must be configured.
    public init(certificate: NIOSSLCertificate, privateKey: NIOSSLPrivateKey) {
        self.certificate = certificate
        self.privateKey = privateKey
    }

    /// Initialize a `ClientCertificate` from a file in PEM format. The file should contain both the certificate
    /// and its private key.
    /// If the key is encrypted, then its passphrase should also be supplied.
    /// - Parameter pemFile: The fully-qualified filename of the PEM file containing the certificate and private key.
    /// - Parameter passphrase: The passphrase for the private key, or nil if the key is not encrypted.
    /// - throws: If the file is not found, or is not in the expected PEM format.
    public init(pemFile: String, passphrase: String? = nil) throws {
        guard FileManager.default.isReadableFile(atPath: pemFile) else {
            throw CertificateError.fileNotFound
        }
        let fileURL = URL.init(fileURLWithPath: pemFile)
        let data = try Data(contentsOf: fileURL)
        try self.init(pemData: data, passphrase: passphrase)
    }

    /// Initialize a `ClientCertificate` from a `String` in PEM format. The string should contain both the
    /// certificate and its private key.
    /// If the key is encrypted, then its passphrase should also be supplied.
    /// - Parameter pemString: A string containing the certificate and private key in PEM format.
    /// - Parameter passphrase: The passphrase for the private key, or nil if the key is not encrypted.
    /// - throws: If the string is not in the expected PEM format.
    public init(pemString: String, passphrase: String? = nil) throws {
        guard let data = pemString.data(using: .utf8) else {
            throw CertificateError.invalidPEMString
        }
        try self.init(pemData: data, passphrase: passphrase)
    }

    /// Initialize a `ClientCertificate` from `Data` in PEM format. The data should contain both the certificate
    /// and its private key.
    /// If the key is encrypted, then its passphrase should also be supplied.
    /// - Parameter pemData: The data containing the certificate and private key in PEM format.
    /// - Parameter passphrase: The passphrase for the private key, or nil if the key is not encrypted.
    /// - throws: If the data is not in the expected PEM format.
    public init(pemData: Data, passphrase: String? = nil) throws {
        let pemBytes: [UInt8] = pemData.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> [UInt8] in
            let bytes = pointer.bindMemory(to: UInt8.self)
            return [UInt8](bytes)
        }
        try self.init(pemBytes: pemBytes, passphrase: passphrase)
    }

    /// Initialize a `ClientCertificate` from a `[UInt8]` containing PEM format data. The data should contain
    /// both the certificate and its private key.
    /// If the key is encrypted, then its passphrase should also be supplied.
    /// - Parameter pemBytes: The data containing the certificate and private key in PEM format.
    /// - Parameter passphrase: The passphrase for the private key, or nil if the key is not encrypted.
    /// - throws: If the data is not in the expected PEM format.
    public init(pemBytes: [UInt8], passphrase: String? = nil) throws {
        // Extract the certificate from PEM data
        self.certificate = try NIOSSLCertificate(bytes: pemBytes, format: .pem)
        // Extract private key from pem data. If the private key is encrypted
        // with a password, NIO will call back to obtain the password.
        let passphraseBytes: [UInt8]? = passphrase?.data(using: .utf8)?.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) -> [UInt8] in
            let bytes = pointer.bindMemory(to: UInt8.self)
            return [UInt8](bytes)
        }
        let pwdCallback: NIOSSLPassphraseCallback = { callback in
            callback(passphraseBytes ?? [])
        }
        self.privateKey = try NIOSSLPrivateKey(bytes: pemBytes, format: .pem, passphraseCallback: pwdCallback)
    }

}
