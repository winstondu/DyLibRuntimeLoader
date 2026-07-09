/// Handed to a plugin's lifecycle hooks and factories so it can resolve
/// interfaces exported by its dependencies (already activated, thanks to
/// dependency-ordered activation).
public struct PluginContext: Sendable {
    public let pluginID: PluginID
    let resolver: any PluginInstanceResolving

    init(pluginID: PluginID, resolver: any PluginInstanceResolving) {
        self.pluginID = pluginID
        self.resolver = resolver
    }

    public func instance<C: PluginContract>(of contract: C.Type) throws -> C.Interface {
        let value = try resolver.resolveInstance(
            interfaceID: C.interfaceID,
            compatibilityHash: C.compatibilityHash,
            from: nil)
        guard let typed = value as? C.Interface else {
            throw PluginError.typeMismatch(
                expected: String(reflecting: C.Interface.self),
                actual: String(reflecting: type(of: value)))
        }
        return typed
    }
}
