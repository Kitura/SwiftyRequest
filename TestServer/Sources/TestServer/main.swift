import Kitura
import HeliumLogger
import FileKit
import Foundation

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

// Enable logging
HeliumLogger.use(.info)

// Pre-canned test data to be returned as JSON
var testData: TestData = TestData(name: "Paddington", age: 1, height: 106.68, address: TestAddress(number: 32, street: "Windsor Gardens", city: "London"))

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

// Create a new router that will be used for insecure requests
let router = Router()

// Handle HTTP GET requests to /
router.get("/") {
    request, response, next in
    response.send("Hello, World!")
    next()
}

// Echo POSTs to /echoJSON that contain a JSON payload
router.post("/echoJSON", middleware: BodyParser())
router.post("/echoJSON") {
    request, response, next in
    if let data = request.body?.asJSON {
        try response.send(json: data).end()
    } else {
        try response.status(.badRequest).end()
    }
}
router.get("/cookies/:number", handler: cookieHandler)

// Create a router that will be used for SSL requests
let sslRouter = Router()

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

// Echo POSTs to /ssl/echoJSON that contain a JSON payload
sslRouter.post("/ssl/echoJSON", middleware: BodyParser())
sslRouter.post("/ssl/echoJSON") {
    request, response, next in
    if let data = request.body?.asJSON {
        try response.send(json: data).end()
    } else {
        try response.status(.badRequest).end()
    }
}

sslRouter.get("/ssl/friends") {
    request, response, next in
    let params = request.queryParametersMultiValues["friend"] ?? []
    let friends = FriendData(friends: params)
    try response.send(json: friends).end()
}

sslRouter.get("/ssl/cookies/:number", handler: cookieHandler)

// Add an HTTP server and connect it to the router
Kitura.addHTTPServer(onPort: 8080, with: router)
Kitura.addHTTPServer(onPort: 8443, with: sslRouter, withSSL: sslConfig)

// Start the Kitura runloop (this call never returns)
Kitura.run()
