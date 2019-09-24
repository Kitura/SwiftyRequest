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

/// Struct used to specify the type of authentication being used.
public struct Credentials {

    let authheader: String

    /// A bearer token, for example a JWT. This will be sent in an `Authorization: Bearer` header.
    public static func bearerAuthentication(token: String) -> Credentials {
        return Credentials(authheader: "Bearer \(token)")
    }


    /// Basic username/password authentication. This will be used to construct an `Authorization: Basic` header.
    public static func basicAuthentication(username: String, password: String) -> Credentials {
        let authData = Data((username + ":" + password).utf8)
        let authString = authData.base64EncodedString()
        return Credentials(authheader: "Basic \(authString)")
    }
}
