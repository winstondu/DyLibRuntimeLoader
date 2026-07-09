/// The object handed across the C boundary from a plugin to the host.
///
/// Deliberately non-generic: generics cannot cross a `@convention(c)`
/// boundary, and reconstituting a generic box with a mismatched parameter is
/// undefined behavior. All typing is recovered host-side with checked casts.
public final class PluginDescriptor: @unchecked Sendable {
    public let manifest: PluginManifest
    let factories: [InterfaceID: @Sendable (PluginContext) -> Any]
    let activate: @Sendable (PluginContext) throws -> Void
    let willDeactivate: @Sendable (PluginContext) -> Void

    public init<Module: PluginModule>(
        manifest: PluginManifest,
        registry: PluginRegistry,
        module: Module.Type
    ) {
        self.manifest = manifest
        self.factories = registry.factories
        self.activate = { try Module.activate(context: $0) }
        self.willDeactivate = { Module.willDeactivate(context: $0) }
    }
}
