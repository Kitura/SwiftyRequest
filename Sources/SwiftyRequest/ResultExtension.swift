/**
 * Copyright IBM Corporation 2018
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

// A Result extension to make it Equatable
// Conditional conformance is only available from Swift 4.1 and up
#if swift(>=4.1)
extension Result: Equatable where T: Equatable {
    
    public static func ==(lhs: Result, rhs: Result) -> Bool {
        switch (lhs, rhs) {
        case (.success(let left), .success(let right)) where left == right:
            return true
        case (.failure, .failure):
            return true
        default:
            return false
        }
    }
}
#endif
