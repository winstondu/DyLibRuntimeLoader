public struct InterfaceExport: Hashable, Sendable, Codable {
    public let interfaceID: InterfaceID
    public let compatibilityHash: String

    public init(interfaceID: InterfaceID, compatibilityHash: String) {
        self.interfaceID = interfaceID
        self.compatibilityHash = compatibilityHash
    }
}
