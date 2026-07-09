public struct PluginManifest: Sendable, Codable {
    public let id: PluginID
    public let version: SemanticVersion
    public let abiVersion: Int
    public let exports: [InterfaceExport]
    public let dependencies: [PluginDependency]

    public init(
        id: PluginID,
        version: SemanticVersion,
        abiVersion: Int,
        exports: [InterfaceExport],
        dependencies: [PluginDependency]
    ) {
        self.id = id
        self.version = version
        self.abiVersion = abiVersion
        self.exports = exports
        self.dependencies = dependencies
    }
}
