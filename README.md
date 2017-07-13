# RestKit
![macOS](https://img.shields.io/badge/os-macOS-green.svg?style=flat)
![Linux](https://img.shields.io/badge/os-linux-green.svg?style=flat)

RestKit is an HTTP networking library built for Swift.

## Contents
* [Features](#features)
* [Installation](#installation)
* [Usage](#usage)
* [CircuitBreaker Integration](#circuitbreaker-integration)
* [Response Methods](#response-methods)

## Features
- Several response methods (e.g. Data, Object, Array, String, etc.) to eliminate boilerplate code in your application.
- JSON encoding and decoding.
- Integration with [CircuitBreaker](https://github.com/IBM-Swift/CircuitBreaker) library.
- Authentication token.
- Multipart form data.

## Swift version
The latest version of RestKit works with the `3.1.1` version of the Swift binaries. You can download this version of the Swift binaries by following this [link](https://swift.org/download/#releases).

## Installation
To leverage the RestKit package in your Swift application, you should specify a dependency for it in your `Package.swift` file:

```swift
 import PackageDescription

 let package = Package(
     name: "MySwiftProject",

     ...

     dependencies: [
         .Package(url: "https://github.ibm.com/MIL/RestKit.git", majorVersion: 0),

         ...

     ])
```

## Usage

### Make Requests
To make outbound HTTP calls using RestKit, you create a `RestRequest` instance. Required constructor parameters are `method`, `url`, and `credentials`, but there are many more you can use, such as:

- `headerParameters`
- `acceptType`
- `contentType`
- `queryItems`
- `messageBody`
- `circuitParameters`

Example usage of `RestRequest`:

```swift
import RestKit

let request = RestRequest(method: .get,
                          url: "http://myApiCall/hello",
                          credentials: .apiKey)
```

### Invoke Response
In this example, `dataToError` is simply an error handling function.
The `response` object we get back is of type `RestResponse<String>` so we can perform a switch on the `response.result` to determine if the network call was successful.

```swift
request.responseString(dataToError: dataToError) { response in
    switch response.result {
    case .success(let result):
        print("Success")
    case .failure(let error):
        print("Failure")
    }
}
```

## CircuitBreaker Integration

RestKit now has additional built-in functionality for leveraging the [CircuitBreaker](https://github.com/IBM-Swift/CircuitBreaker) library to increase your application's stability. To make use of this functionality, you just need to provide a `CircuitParameters` object to the `RestRequest` initializer. A `CircuitParameters` object will include a reference to a fallback function that will be invoked when the circuit is failing fast.

### Fallback
Here is an example of a fallback closure:

```swift
let fallback = { (error: BreakerError, msg: String) in
    print("Fallback closure invoked... circuit must be open.")
}
```

### CircuitParameters
We just initialize the `CircuitParameters` object and create a `RestRequest` instance. The only required value you need to set for `CircuitParameters` is the `fallback` (everything else has default values).

```swift
let circuitParameters = CircuitParameters(timeout: 2000,
                                          maxFailures: 2,
                                          fallback: breakFallback)

let request = RestRequest(method: .get,
                          url: "http://myApiCall/hello",
                          credentials: .apiKey,
                          circuitParameters: circuitParameters)
```

At this point, you can use any of the response methods mentioned in the section below.

## Response Methods
There are various response methods you can use based on what result type you want, here they are:

- `responseData` returns a `Data` object.
- `responseObject<T: JSONDecodable>` returns an object of type `T`.
- `responseArray<T: JSONDecodable>` returns an array of type `T`.
- `responseString` returns a `String`.
- `responseVoid` returns `Void`.

## License
This Swift package is licensed under Apache 2.0. Full license text is available in [LICENSE](LICENSE).
