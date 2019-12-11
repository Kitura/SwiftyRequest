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
import CircuitBreaker

/// Encapsulates properties needed to initialize a `CircuitBreaker` object within the `RestRequest` initializer.
/// `A` is the type of the fallback's parameter.  See the CircuitBreaker documentation for a full explanation
/// of these parameters.
public struct CircuitParameters<A> {

    /// The circuit name: defaults to "circuitName".
    let name: String

    /// The circuit timeout in milliseconds: defaults to 2000.
    public let timeout: Int

    /// The circuit timeout in milliseconds: defaults to 60000.
    public let resetTimeout: Int

    /// Max failures allowed: defaults to 5.
    public let maxFailures: Int

    /// Rolling Window in milliseconds: defaults to 10000.
    public let rollingWindow:Int

    /// Bulkhead: defaults to 0.
    public let bulkhead: Int

    /// The error fallback callback.
    public let fallback: (BreakerError, A) -> Void

    /// Initialize a `CircuitParameters` instance.
    public init(name: String = "circuitName", timeout: Int = 2000, resetTimeout: Int = 60000, maxFailures: Int = 5, rollingWindow: Int = 10000, bulkhead: Int = 0, fallback: @escaping (BreakerError, A) -> Void) {
        self.name = name
        self.timeout = timeout
        self.resetTimeout = resetTimeout
        self.maxFailures = maxFailures
        self.rollingWindow = rollingWindow
        self.bulkhead = bulkhead
        self.fallback = fallback
    }
}
