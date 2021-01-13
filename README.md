<p align="center">
    <a href="http://kitura.io/">
        <img src="https://raw.githubusercontent.com/Kitura/Kitura/master/Sources/Kitura/resources/kitura-bird.svg?sanitize=true" height="100" alt="Kitura">
    </a>
</p>

<p align="center">
    <a href="https://kitura.github.io/SwiftyRequest/index.html">
    <img src="https://img.shields.io/badge/apidoc-SwiftyRequest-1FBCE4.svg?style=flat" alt="APIDoc">
    </a>
    <a href="https://travis-ci.org/Kitura/SwiftyRequest">
    <img src="https://travis-ci.org/Kitura/SwiftyRequest.svg?branch=master" alt="Build Status - Master">
    </a>
    <img src="https://img.shields.io/badge/os-macOS-green.svg?style=flat" alt="macOS">
    <img src="https://img.shields.io/badge/os-linux-green.svg?style=flat" alt="Linux">
    <img src="https://img.shields.io/badge/license-Apache2-blue.svg?style=flat" alt="Apache 2">
    <a href="http://swift-at-ibm-slack.mybluemix.net/">
    <img src="http://swift-at-ibm-slack.mybluemix.net/badge.svg" alt="Slack Status">
    </a>
</p>

# SwiftyRequest

`SwiftyRequest` is an HTTP client built for Swift.

The latest release of SwiftyRequest is built upon the Swift-NIO based [`async-http-client`](https://github.com/swift-server/async-http-client).

## Contents
* [Features](#features)
* [Installation](#installation)
* [Usage](#usage)
* [CircuitBreaker Integration](#circuitbreaker-integration)
* [Response Methods](#response-methods)
* [Migrating from SwiftyRequest v2 to v3](#migration-from-v2-to-v3)

## Features
- Several response methods (e.g. Data, Object, Array, String, etc.) to eliminate boilerplate code in your application.
- Direct retrieval of `Codable` types.
- JSON encoding and decoding.
- Integration with the [CircuitBreaker](https://github.com/Kitura/CircuitBreaker) library.
- Authentication tokens.
- Client Certificate support (2-way SSL).
- Multipart form data.

## Swift version

The latest version of SwiftyRequest requires Swift 5 or later.

Swift 4 support is available in the 2.x release of SwiftyRequest.

## Installation
To leverage the `SwiftyRequest` package in your Swift application, you should specify a dependency for it in your `Package.swift` file:

### Add dependencies

Add `SwiftyRequest` to the dependencies within your application's `Package.swift` file. Substitute `"x.x.x"` with the latest `SwiftyRequest` [release](https://github.com/Kitura/SwiftyRequest/releases).

```swift
.package(url: "https://github.com/Kitura/SwiftyRequest.git", from: "x.x.x")
```
Add `SwiftyRequest` to your target's dependencies:

```Swift
.target(name: "example", dependencies: ["SwiftyRequest"]),
```

## Usage

### Make Requests
To make outbound HTTP calls using `SwiftyRequest`, create a `RestRequest` instance. The `method` parameter is optional (it defaults to `.get`), the `url` parameter is required.

Example usage of `RestRequest`:

```swift
import SwiftyRequest

let request = RestRequest(method: .get, url: "http://myApiCall/hello")
request.credentials = .basicAuthentication(username: "John", password: "12345")
```

You can customize the following parameters in the HTTP request:
- `headerParameters` : The HTTP header fields which form the header section of the request message.
- `credentials` : The HTTP authentication credentials for the request.
- `acceptType` : The HTTP `Accept` header, defaults to `application/json`.
- `messageBody` : The HTTP message body of the request.
- `productInfo` : The HTTP `User-Agent` header.
- `circuitParameters` : A `CircuitParameters` object which includes a reference to a fallback function that will be invoked when the circuit is failing fast (see [CircuitBreaker Integration](#circuitbreaker-integration)).
- `contentType` : The HTTP `Content-Type header`, defaults to `application/json`.
- `method` : The HTTP method specified in the request, defaults to `.GET`.
- `queryItems`: Any query parameters to be appended to the URL.

### Invoke Response

The `result` object we get back is of type `Result<RestResponse<String>, Error>` so we can perform a switch to determine if the network call was successful:

```swift
request.responseString { result in
    switch result {
    case .success(let response):
        print("Success")
    case .failure(let error):
        print("Failure")
    }
}
```

### Invoke Response with Template Parameters

URLs can be templated with the `{keyName}` syntax, allowing a single `RestRequest` instance to be reused with different parameters.

In this example, we invoke a response method with two template parameters to be used to replace the `{state}` and `{city}` values in the URL:

```swift
let request = RestRequest(url: "http://api.weather.com/api/123456/conditions/q/{state}/{city}.json")

request.responseData(templateParams: ["state": "TX", "city": "Austin"]) { result in
	// Handle response
}
```

### Invoke Response with Query Parameters

In this example, we invoke a response method with a query parameter to be appended onto the `url` behind the scenes so that the `RestRequest` gets executed with the following url: `http://api.weather.com/api/123456/conditions/q/CA/San_Francisco.json?hour=9`.  Any query items already specified in the request URL will be replaced:

```swift
let request = RestRequest(url: "http://api.weather.com/api/123456/conditions/q/CA/San_Francisco.json")

request.responseData(queryItems: [URLQueryItem(name: "hour", value: "9")]) { result in
	// Handle response
}
```

## CircuitBreaker Integration

`SwiftyRequest` has built-in functionality for leveraging the [CircuitBreaker](https://github.com/Kitura/CircuitBreaker) library to increase your application's stability. To make use of this functionality, assign a `CircuitParameters` object to the `circuitParameters` property. This object will include a reference to a fallback function that will be invoked when the circuit is failing fast.

### Fallback
Here is an example of a fallback closure:

```swift
let breakerFallback = { (error: BreakerError, msg: String) in
    print("Fallback closure invoked... circuit must be open.")
}
```

### CircuitParameters
We initialize the `CircuitParameters` object and create a `RestRequest` instance. The only required value you need to set for `CircuitParameters` is the `fallback` (everything else has default values).

```swift
let circuitParameters = CircuitParameters(timeout: 2000,
                                          maxFailures: 2,
                                          fallback: breakerFallback)

let request = RestRequest(method: .GET, url: "http://myApiCall/hello")
request.circuitParameters = circuitParameters
```

At this point, you can use any of the response methods mentioned in the section below.

## Response Methods

`RestRequest` provides a number of `response` functions that call back with a `Result` containing either a response or an error.

To invoke the request and receive a response, you can use the `response` function. The completion handler will be called back with a result of type `Result<HTTPClient.Response, Error>`.

RestRequest provides additional convenience methods you can use based on the type of the response body you expect:

- `responseData` requires that the response contains a body, and calls back with a `Result<RestResponse<Data>, Error>`.
- `responseObject<T: Decodable>` decodes the response body to the specified type, and calls back with a `Result<RestResponse<T>, Error>`.
- `responseString` decodes the response body to a String, and calls back with a `Result<RestResponse<String>, Error>`.
- `responseDictionary` decodes the response body as JSON, and calls back with a `Result<RestResponse<[String: Any]>, Error>`.
- `responseArray` decodes the response body as a a JSON array, and calls back with a `Result<RestResponse<[Any]>, Error>`.
- `responseVoid` does not expect a response body, and calls back with a `Result<HTTPClient.Response, Error>`.

### Example of handling a response

```swift
let request = RestRequest(method: .get, url: "http://localhost:8080/users/{userid}")

request.responseObject(templateParams: ["userid": "1"]) { (result: Result<RestResponse<User>, RestError>) in
    switch result {
    case .success(let response):
        let user = response.body
        print("Successfully retrieved user \(user.name)")
    case .failure(let error):
        if let response = error.response {
            print("Request failed with status: \(response.status)")
        }
        if let responseData = error.responseData {
            // Handle error response body
        }
    }
}
```

## Migration from v2 to v3

There are a number of changes to the API in SwiftyRequest v3 compared to the v2 release:

- The `RestRequest` initializer parameter  `containsSelfSignedCert` has been renamed `insecure` to better reflect its purpose (turning off SSL certificate verification).  The old name has been deprecated and may be removed in a future release.
- The `completionHandler` callback of `responseData` (et al) has changed from `(RestResponse<Data>) -> Void` to `(Result<RestResponse<Data>, RestError>) -> Void`.  
- The `JSONDecodable` and `JSONEncodable` types have been removed in favour of using `Codable` directly.  The `responseObject` function allows you to receive a Codable object in a response.
- Convenience functions for handling raw JSON have been added.  `responseDictionary` and `responseArray` alow retrieval of JSON as `[String: Any]` and `[Any]` respectively, and sending of raw JSON can be performed by setting the `request.messageBodyDictionary` or `request.messageBodyArray` properties.
- the `RestError` type is now returned explicitly in the `.failure` case.  If the error pertains to a response with a non-success status code, you can access the response with `error.response`.  If the response also contained body data, it can be retrieved via `error.responseData`.

## Client Certificate support (2-way SSL)

Specify a `ClientCertificate` when creating a `RestRequest` to enable a client certificate to be presented upon a secure request (2-way SSL).

The certificate may be provided in PEM format - either from a file, a string or Data, and an optional passphrase.  The PEM data should contain the certificate and its corresponding private key.  If the private key is encrypted, the corresponding passphrase should be specified when constructing the ClientCertificate.

If you need to handle certificates in other formats, you may create a ClientCertificate directly from a `NIOSSLCertificate` and `NIOSSLPrivateKey`.  For more information on these types, see the documentation for the [`async-http-client` project](https://github.com/swift-server/async-http-client).

## API documentation

For more information visit our [API reference](http://kitura.github.io/SwiftyRequest/).

## Community

We love to talk server-side Swift, and Kitura. Join our [Slack](http://swift-at-ibm-slack.mybluemix.net/) to meet the team!

## License

This library is licensed under Apache 2.0. Full license text is available in [LICENSE](https://github.com/Kitura/SwiftyRequest/blob/master/LICENSE).
