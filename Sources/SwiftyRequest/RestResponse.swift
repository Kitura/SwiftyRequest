/**
 * Copyright IBM Corporation 2016,2017,2018,2019
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
import NIO
import NIOHTTP1

/// Contains data associated with a finished network request,
/// with `T` being the type of response we expect to receive.
public struct RestResponse<T> {
    
    /// The response host.
    public var host: String
    /// The HTTP status code.
    public var status: HTTPResponseStatus
    /// The HTTP headers.
    public var headers: HTTPHeaders
    /// The HTTP request that was sent to get this response.
    public var request: HTTPClient.Request
    /// The body of the response as the expected type.
    public var body: T
}
