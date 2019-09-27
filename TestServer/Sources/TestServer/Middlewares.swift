/*
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
*/
import Kitura
import SwiftJWT
import Foundation

public struct MyBasicAuth: TypeSafeMiddleware {

    let id: String

    static let users = ["John" : "12345", "Mary" : "qwerasdf"]

    public static func handle(request: RouterRequest, response: RouterResponse, completion: @escaping (MyBasicAuth?, RequestError?) -> Void) {
        authenticate(request: request, response: response,
                     onSuccess: { (profile) in
                        completion(profile, nil)
        }, onFailure: { (_,_ ) in
            completion(nil, .unauthorized)
        }, onSkip: { (_,_ ) in
            completion(nil, .unauthorized)
        })
    }
    public static func authenticate(request: RouterRequest, response: RouterResponse, onSuccess: @escaping (MyBasicAuth) -> Void, onFailure: @escaping (HTTPStatusCode?, [String : String]?) -> Void, onSkip: @escaping (HTTPStatusCode?, [String : String]?) -> Void) {

        let userid: String
        let password: String
        if let requestUser = request.urlURL.user, let requestPassword = request.urlURL.password {
            userid = requestUser
            password = requestPassword
        } else {
            guard let authorizationHeader = request.headers["Authorization"]  else {
                return onSkip(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"User\""])
            }

            let authorizationHeaderComponents = authorizationHeader.components(separatedBy: " ")
            guard authorizationHeaderComponents.count == 2,
                authorizationHeaderComponents[0] == "Basic",
                let decodedData = Data(base64Encoded: authorizationHeaderComponents[1], options: Data.Base64DecodingOptions(rawValue: 0)),
                let userAuthorization = String(data: decodedData, encoding: .utf8) else {
                    return onSkip(.unauthorized, ["WWW-Authenticate" : "Basic realm=\"User\""])
            }
            let credentials = userAuthorization.components(separatedBy: ":")
            guard credentials.count >= 2 else {
                return onFailure(.badRequest, nil)
            }
            userid = credentials[0]
            password = credentials[1]
        }

        if let storedPassword = users[userid], storedPassword == password {
            onSuccess(MyBasicAuth(id: userid))
        } else {
            return onFailure(.unauthorized, nil)
        }
    }
}

struct MyJWTAuth<C: Claims>: TypeSafeMiddleware {

    let jwt: JWT<C>

    static func handle(request: RouterRequest, response: RouterResponse, completion: @escaping (MyJWTAuth?, RequestError?) -> Void) {
        let auth = request.headers["Authorization"]
        guard let authParts = auth?.split(separator: " ", maxSplits: 2),
            authParts.count == 2,
            authParts[0] == "Bearer",
            let key = "<PrivateKey>".data(using: .utf8),
            let jwt = try? JWT<C>(jwtString: String(authParts[1]), verifier: .hs256(key: key))
            else {
                return completion(nil, .unauthorized)
        }
        completion(MyJWTAuth(jwt: jwt), nil)
    }
}
