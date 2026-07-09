/// Internal seam between `PluginContext` and `PluginManager`, kept as a
/// protocol so context values do not retain the concrete manager type and
/// pure tests can substitute a stub resolver.
public protocol PluginInstanceResolving: AnyObject, Sendable {
    func resolveInstance(
        interfaceID: InterfaceID,
        compatibilityHash: String,
        from id: PluginID?
    ) throws -> Any
}
