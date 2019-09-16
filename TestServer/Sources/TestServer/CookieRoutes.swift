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
#if swift(>=4.1)
    #if canImport(FoundationNetworking)
        import FoundationNetworking
    #endif
#endif

func cookieHandler(request: RouterRequest, response: RouterResponse, next: @escaping () -> Void) throws {
    let number = request.parameters["number"].map { Int($0) ?? 0 } ?? 0
    for no in 0..<number {
        var cookieProps: [HTTPCookiePropertyKey: Any]
        cookieProps = [
            HTTPCookiePropertyKey.domain: "localhost",
            HTTPCookiePropertyKey.path: "/",
            HTTPCookiePropertyKey.name: "name\(no)",
            HTTPCookiePropertyKey.value: "value\(no)",
        ]
        let cookie = HTTPCookie(properties: cookieProps)
        response.cookies["name\(no)"] = cookie
    }
    try response.status(.OK).end()
}

