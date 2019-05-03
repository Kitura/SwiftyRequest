public struct TestData: Codable {
    let name: String
    let age: Int
    let height: Double
    let address: TestAddress
}

public struct TestAddress: Codable {
    let number: Int
    let street: String
    let city: String
}

public struct FriendData: Codable {
    let friends: [String]
}
