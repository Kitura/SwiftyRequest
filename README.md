<p align="center">
    <a href="http://kitura.io/">
        <img src="https://raw.githubusercontent.com/IBM-Swift/Kitura/master/Sources/Kitura/resources/kitura-bird.svg?sanitize=true" height="100" alt="Kitura">
    </a>
</p>

<p align="center">
    <a href="https://ibm-swift.github.io/SwiftyRequest/index.html">
    <img src="https://img.shields.io/badge/apidoc-SwiftyRequest-1FBCE4.svg?style=flat" alt="APIDoc">
    </a>
    <a href="https://travis-ci.org/IBM-Swift/SwiftyRequest">
    <img src="https://travis-ci.org/IBM-Swift/SwiftyRequest.svg?branch=master" alt="Build Status - Master">
    </a>
    <img src="https://img.shields.io/badge/os-macOS-green.svg?style=flat" alt="macOS">
    <img src="https://img.shields.io/badge/os-linux-green.svg?style=flat" alt="Linux">
    <img src="https://img.shields.io/badge/license-Apache2-blue.svg?style=flat" alt="Apache 2">
    <a href="http://swift-at-ibm-slack.mybluemix.net/">
    <img src="http://swift-at-ibm-slack.mybluemix.net/badge.svg" alt="Slack Status">
    </a>
</p>

# SwiftyRequest

`SwiftyRequest` is an HTTP networking library built for Swift.

`SwiftyRequest` uses `URLSession` for the underlying transport. `URLSession` on Linux is not yet completely implemented so you may find that this library is less reliable on Linux than Darwin (reference issues [#24](https://github.com/IBM-Swift/SwiftyRequest/issues/24) and [#25](https://github.com/IBM-Swift/SwiftyRequest/issues/25), the second of these references a [Foundation PR](https://github.com/apple/swift-corelibs-foundation/pull/1629)).

## Contents
* [Features](#features)
* [Installation](#installation)
* [Usage](#usage)
* [CircuitBreaker Integration](#circuitbreaker-integration)
* [Response Methods](#response-methods)

## Features
- Several response methods (e.g. Data, Object, Array, String, etc.) to eliminate boilerplate code in your application.
- JSON encoding and decoding.
- Integration with the [CircuitBreaker](https://github.com/IBM-Swift/CircuitBreaker) library.
- Authentication tokens.
- Multipart form data.

## Swift version

This repository supports Swift 4.0.3 and later.

## Installation
To leverage the `SwiftyRequest` package in your Swift application, you should specify a dependency for it in your `Package.swift` file:

### Add dependencies

Add `SwiftyRequest` to the dependencies within your application's `Package.swift` file. Substitute `"x.x.x"` with the latest `SwiftyRequest` [release](https://github.com/IBM-Swift/SwiftyRequest/releases).

```swift
.package(url: "https://github.com/IBM-Swift/SwiftyRequest.git", from: "x.x.x")
```
Add `SwiftyRequest` to your target's dependencies:

```Swift
.target(name: "example", dependencies: ["SwiftyRequest"]),
```

## Usage

### Make Requests
To make outbound HTTP calls using `SwiftyRequest`, create a `RestRequest` instance. The `method` parameter is optional (it defaults to `GET`), the `url` parameter is required.

Example usage of `RestRequest`:

```swift
import SwiftyRequest

let request = RestRequest(method: .get, url: "http://myApiCall/hello")
request.credentials = .apiKey
```

You can customize the following parameters in the HTTP request:
- `headerParameters` : The HTTP header fields which form the header section of the request message.
- `credentials` : The HTTP authentication credentials for the request.
- `acceptType` : The HTTP `Accept` header, defaults to `application/json`.
- `messageBody` : The HTTP message body of the request.
- `productInfo` : The HTTP `User-Agent` header.
- `circuitParameters` : A `CircuitParameters` object which includes a reference to a fallback function that will be invoked when the circuit is failing fast (see [CircuitBreaker Integration](#circuitbreaker-integration)).
- `contentType` : The HTTP `Content-Type header`, defaults to `application/json`.
- `method` : The HTTP method specified in the request, defaults to `.get`.


### Invoke Response
In this example, `responseToError` is simply an error handling function.
The `response` object we get back is of type `RestResponse<String>` so we can perform a switch on the `response.result` to determine if the network call was successful.

```swift
request.responseString(responseToError: responseToError) { response in
    switch response.result {
    case .success(let result):
        print("Success")
    case .failure(let error):
        print("Failure")
    }
}
```

### Invoke Response with Template Parameters

In this example, we invoke a response method with two template parameters to be used to replace the `{state}` and `{city}` values in the `url`. This allows us to create multiple response invocations with the same `RestRequest` object, but possibly using different url values.

```swift
let request = RestRequest(url: "http://api.weather.com/api/123456/conditions/q/{state}/{city}.json")
request.credentials = .apiKey

request.responseData(templateParams: ["state": "TX", "city": "Austin"]) { response in
	// Handle response
}
```

### Invoke Response with Query Parameters

In this example, we invoke a response method with a query parameter to be appended onto the `url` behind the scenes so that the `RestRequest` gets executed with the following url: `http://api.weather.com/api/123456/conditions/q/CA/San_Francisco.json?hour=9`.  If there are query items already specified in the request URL they will be replaced.

```swift
let request = RestRequest(url: "http://api.weather.com/api/123456/conditions/q/CA/San_Francisco.json")
request.credentials = .apiKey

request.responseData(queryItems: [URLQueryItem(name: "hour", value: "9")]) { response in
	// Handle response
}
```

## CircuitBreaker Integration

`SwiftyRequest` now has additional built-in functionality for leveraging the [CircuitBreaker](https://github.com/IBM-Swift/CircuitBreaker) library to increase your application's stability. To make use of this functionality, you just need to provide a `CircuitParameters` object to the `RestRequest` initializer. A `CircuitParameters` object will include a reference to a fallback function that will be invoked when the circuit is failing fast.

### Fallback
Here is an example of a fallback closure:

```swift
let fallback = { (error: BreakerError, msg: String) in
    print("Fallback closure invoked... circuit must be open.")
}
```

### CircuitParameters
We initialize the `CircuitParameters` object and create a `RestRequest` instance. The only required value you need to set for `CircuitParameters` is the `fallback` (everything else has default values).

```swift
let circuitParameters = CircuitParameters(timeout: 2000,
                                          maxFailures: 2,
                                          fallback: breakFallback)

let request = RestRequest(method: .get, url: "http://myApiCall/hello")
request.credentials = .apiKey,
request.circuitParameters = circuitParameters
```

At this point, you can use any of the response methods mentioned in the section below.

## Response Methods
There are various response methods you can use based on the result type you want, here they are:

- `responseData` returns a `Data` object.
- `responseObject<T: Codable>` returns a Codable object of type `T`.
- `responseObject<T: JSONDecodable>` returns an object of type `T`.
- `responseArray<T: JSONDecodable>` returns an array of type `T`.
- `responseString` returns a `String`.
- `responseVoid` returns `Void`.

## API documentation

For more information visit our [API reference](http://ibm-swift.github.io/SwiftyRequest/).

## Community

We love to talk server-side Swift, and Kitura. Join our [Slack](http://swift-at-ibm-slack.mybluemix.net/) to meet the team!

## License

This library is licensed under Apache 2.0. Full license text is available in [LICENSE](https://github.com/IBM-Swift/SwiftyRequest/blob/master/LICENSE).
