/*
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
*/
import Kitura
import Foundation
import SwiftJWT

var userStore: [String: User] = [:]

func basicAuthHandler(profile: MyBasicAuth, id: Int, respondWith: (User?, RequestError?) -> Void) {
    guard let user = userStore[id.value] else {
        respondWith(nil, .notFound)
        return
    }
    respondWith(user, nil)
}

func generateJWTHandler(user: JWTUser?, respondWith: (AccessToken?, RequestError?) -> Void) {
    guard let user = user else {
        respondWith(nil, .badRequest)
        return
    }
    var jwt = JWT(claims: ClaimsStandardJWT(iss: "Kitura", sub: user.name))
    guard let key = "<PrivateKey>".data(using: .utf8),
        let signedJWT = try? jwt.sign(using: .hs256(key: key))
        else {
            return respondWith(nil, .internalServerError)
    }
    respondWith(AccessToken(accessToken: signedJWT), nil)
}

func jwtAuthHandler(typeSafeJWT: MyJWTAuth<ClaimsStandardJWT>, respondWith: (JWTUser?, RequestError?) -> Void) {
    guard let userName = typeSafeJWT.jwt.claims.sub else {
        return respondWith(nil, .internalServerError)
    }
    respondWith(JWTUser(name: userName), nil)
}
