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
import Socket
import HeliumLogger
import FileKit
import Foundation

// Enable logging
HeliumLogger.use(.debug)

// Pre-canned test data to be returned as JSON
var testData: TestData = TestData(name: "Paddington", age: 1, height: 106.68, address: TestAddress(number: 32, street: "Windsor Gardens", city: "London"))

userStore[1] = User(id: 1, name: "Dave", date: Date(timeIntervalSince1970: 0))
userStore[2] = User(id: 2, name: "Helen", date: Date(timeIntervalSinceReferenceDate: 0))

// Import SSL
#if os(Linux)
let sslConfig =  SSLConfig(withCACertificateDirectory: nil,
                           usingCertificateFile: FileKit.projectFolder + "/Credentials/cert.pem",
                           withKeyFile: FileKit.projectFolder + "/Credentials/key.pem",
                           usingSelfSignedCerts: true)
#else
let sslConfig =  SSLConfig(withChainFilePath: FileKit.projectFolder + "/Credentials/cert.pfx",
                           withPassword: "password",
                           usingSelfSignedCerts: true)
#endif

// Create routers that will be used for insecure and secure requests
let router = Router()
let sslRouter = Router()

// MARK: GET request tests

// Handle HTTP GET requests to /
router.get("/") {
    request, response, next in
    response.send("Hello, World!")
    next()
}

// Returns a JSON representation of a TestData object
sslRouter.get("/ssl/json") { (respondWith: (TestData?, RequestError?) -> Void) in
    respondWith(testData, nil)
}

// Returns a JSON representation of an array of TestData objects
sslRouter.get("/ssl/jsonArray") { (respondWith: ([TestData]?, RequestError?) -> Void) in
    respondWith([testData, testData], nil)
}

// Returns a JSON representation of a TestData object, customized by two
// path parameters.
sslRouter.get("/ssl/json/:name/:city") {
    request, response, next in
    guard let name = request.parameters["name"], let city = request.parameters["city"] else {
        return try response.status(.badRequest).end()
    }
    try response.send(json: TestData(name: name, age: 1, height: 106.68, address: TestAddress(number: 32, street: "Windsor Gardens", city: city))).end()
}

// MARK: JSON echo tests

// Echo POSTs that contain a JSON payload
router.post("/echoJSON", middleware: BodyParser())
router.post("/echoJSON", handler: echoJSONHandler)
sslRouter.post("/ssl/echoJSON", middleware: BodyParser())
sslRouter.post("/ssl/echoJSON", handler: echoJSONHandler)

router.post("/echoJSONArray", handler: echoJSONArrayHandler)

// MARK: Query parameters tests

// Tests multiple query parameter values for the same key
sslRouter.get("/ssl/friends") {
    request, response, next in
    let params = request.queryParametersMultiValues["friend"] ?? []
    let friends = FriendData(friends: params)
    try response.send(json: friends).end()
}

// MARK: Cookies

router.get("/cookies/:number", handler: cookieHandler)
sslRouter.get("/ssl/cookies/:number", handler: cookieHandler)

// MARK: Basic Authentication

sslRouter.get("/ssl/basic/user", handler: basicAuthHandler)

// MARK: JWT Authentication

sslRouter.post("/ssl/jwt/generateJWT", handler: generateJWTHandler)
sslRouter.get("/ssl/jwt/user", handler: jwtAuthHandler)

// MARK: Backend for testing README example

router.get("/users/:id") { (id: Int, respondWith: (User?, RequestError?) -> Void) in
    respondWith(userStore[id], nil)
}

// MARK: Timeout tests

router.get("/timeout") { request, response, next in
    guard let param = request.queryParameters["delay"], let delay = Int(param) else {
        return try response.status(.badRequest).end()
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(delay)) {
        response.status(.OK)
        next()
    }
}

// A socket that listens but never accepts connections
let sleepyServerSocket = try Socket.create(family: .inet)
try sleepyServerSocket.listen(on: 8081, maxBacklogSize: 1, allowPortReuse: false)

// MARK: Start server

// Add an HTTP server and connect it to the router
Kitura.addHTTPServer(onPort: 8080, with: router)
Kitura.addHTTPServer(onPort: 8443, with: sslRouter, withSSL: sslConfig)

// Start the Kitura runloop (this call never returns)
Kitura.run()
