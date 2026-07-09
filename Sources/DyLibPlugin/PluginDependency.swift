public struct PluginDependency: Hashable, Sendable, Codable {
    public let id: PluginID
    public let requirement: VersionRequirement

    public init(_ id: PluginID, _ requirement: VersionRequirement) {
        self.id = id
        self.requirement = requirement
    }

    public static func plugin(_ id: PluginID, _ requirement: VersionRequirement) -> PluginDependency {
        PluginDependency(id, requirement)
    }
}
