/**
* Copyright IBM Corporation 2017-2019
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
import NIOHTTP1

/// An enum to describe the HTTP method (Get, Post, Put, Delete, etc) of an HTTP
/// request. In general they match the actual HTTP methods by the same name.
public enum HTTPMethod: String {
    /// The HTTP method for an HTTP GET request
    case get = "GET"

    /// The HTTP method for an HTTP POST request
    case post = "POST"

    /// The HTTP method for an HTTP PUT request
    case put = "PUT"

    /// The HTTP method for an HTTP HEAD request
    case head = "HEAD"

    /// The HTTP method for an HTTP DELETE request
    case delete = "DELETE"

    /// The HTTP method for an HTTP OPTIONS request
    case options = "OPTIONS"

    /// The HTTP method for an HTTP TRACE request
    case trace = "TRACE"

    /// The HTTP method for an HTTP COPY request
    case copy = "COPY"

    /// The HTTP method for an HTTP LOCK request
    case lock = "LOCK"

    /// The HTTP method for an HTTP MKCOL request
    case mkCol = "MKCOL"

    /// The HTTP method for an HTTP MOVE request
    case move = "MOVE"

    /// The HTTP method for an HTTP PURGE request
    case purge = "PURGE"

    /// The HTTP method for an HTTP PROPFIND request
    case propFind = "PROPFIND"

    /// The HTTP method for an HTTP PROPPATCH request
    case propPatch = "PROPPATCH"

    /// The HTTP method for an HTTP UNLOCK request
    case unlock = "UNLOCK"

    /// The HTTP method for an HTTP REPORT request
    case report = "REPORT"

    /// The HTTP method for an HTTP MKACTIVITY request
    case mkActivity = "MKACTIVITY"

    /// The HTTP method for an HTTP CHECKOUT request
    case checkout = "CHECKOUT"

    /// The HTTP method for an HTTP MERGE request
    case merge = "MERGE"

    /// The HTTP method for an HTTP MSEARCH request
    case mSearch = "MSEARCH"

    /// The HTTP method for an HTTP NOTIFY request
    case notify = "NOTIFY"

    /// The HTTP method for an HTTP SUBSCRIBE request
    case subscribe = "SUBSCRIBE"

    /// The HTTP method for an HTTP UNSUBSCRIBE request
    case unsubscribe = "UNSUBSCRIBE"

    /// The HTTP method for an HTTP PATCH request
    case patch = "PATCH"

    /// The HTTP method for an HTTP SEARCH request
    case search = "SEARCH"

    /// The HTTP method for an HTTP CONNECT request
    case connect = "CONNECT"

    case acl = "ACL"
    case bind = "BIND"
    case unbind = "UNBIND"
    case rebind = "REBIND"
    case link = "LINK"
    case unlink = "UNLINK"
    case source = "SOURCE"
    case mkCalendar = "MKCALENDAR"

    /// Created when creating instances of this enum from a string that doesn't match any of the other
    /// values.
    case unknown = "UNKNOWN"

    /// Convert a string to a `HTTPMethod` instance.
    ///
    /// - Parameter fromRawValue: The string form of an HTTP method to convert to an `HTTPMethod` enum.
    init(fromRawValue: String) {
        self = HTTPMethod(rawValue: fromRawValue) ?? .unknown
    }
}

// MARK: CustomStringConvertible extension
extension HTTPMethod: CustomStringConvertible {
    /// String format of an `HTTPMethod` instance.
    public var description: String {
        return self.rawValue
    }
}

// Map SwiftyRequest's HTTPMethod to NIO's HTTPMethod. This is to preserve the
// existing SwiftyRequest v2 API where possible.
extension HTTPMethod {
    var httpClientMethod: NIOHTTP1.HTTPMethod {
        switch self {
        case .acl: return .ACL
        case .checkout: return .CHECKOUT
        case .connect: return .CONNECT
        case .copy: return .COPY
        case .delete: return .DELETE
        case .get: return .GET
        case .head: return .HEAD
        case .lock: return .LOCK
        case .merge: return .MERGE
        case .mkActivity: return .MKACTIVITY
        case .mkCol: return .MKCOL
        case .move: return .MOVE
        case .mSearch: return .MSEARCH
        case .notify: return .NOTIFY
        case .options: return .OPTIONS
        case .put: return .PUT
        case .post: return .POST
        case .patch: return .PATCH
        case .propFind: return .PROPFIND
        case .propPatch: return .PROPPATCH
        case .purge: return .PURGE
        case .report: return .REPORT
        case .search: return .SEARCH
        case .subscribe: return .SUBSCRIBE
        case .trace: return .TRACE
        case .unlock: return .UNLOCK
        case .unsubscribe: return .UNSUBSCRIBE
        case .unknown: return .RAW(value: "UNKNOWN")
        case .bind: return .BIND
        case .unbind: return .UNBIND
        case .rebind: return .REBIND
        case .link: return .LINK
        case .unlink: return .UNLINK
        case .source: return .SOURCE
        case .mkCalendar: return .MKCALENDAR
        }
    }

    init(_ httpClientMethod: NIOHTTP1.HTTPMethod) {
        switch httpClientMethod {
        case .GET: self = .get
        case .PUT: self = .put
        case .ACL: self = .acl
        case .HEAD: self = .head
        case .POST: self = .post
        case .COPY: self = .copy
        case .LOCK: self = .lock
        case .MOVE: self = .move
        case .BIND: self = .bind
        case .LINK: self = .link
        case .PATCH: self = .patch
        case .TRACE: self = .trace
        case .MKCOL: self = .mkCol
        case .MERGE: self = .merge
        case .PURGE: self = .purge
        case .NOTIFY: self = .notify
        case .SEARCH: self = .search
        case .UNLOCK: self = .unlock
        case .REBIND: self = .rebind
        case .UNBIND: self = .unbind
        case .REPORT: self = .report
        case .DELETE: self = .delete
        case .UNLINK: self = .unlink
        case .CONNECT: self = .connect
        case .MSEARCH: self = .mSearch
        case .OPTIONS: self = .options
        case .PROPFIND: self = .propFind
        case .CHECKOUT: self = .checkout
        case .PROPPATCH: self = .propPatch
        case .SUBSCRIBE: self = .subscribe
        case .MKCALENDAR: self = .mkCalendar
        case .MKACTIVITY: self = .mkActivity
        case .UNSUBSCRIBE: self = .unsubscribe
        case .SOURCE: self = .source
        case .RAW(let value):
            self = HTTPMethod(fromRawValue: value)
        }
    }
}
