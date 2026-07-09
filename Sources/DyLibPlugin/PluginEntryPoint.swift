/// Runtime support called by the `@PluginMain`-generated entry function.
/// Plugin authors never call this directly.
public enum PluginEntryPoint {
    /// Builds the plugin's descriptor and hands it across the C boundary as
    /// a retained opaque pointer. The host balances the retain with exactly
    /// one `takeRetainedValue()` per dlopen handle.
    public static func makeDescriptor<Module: PluginModule>(
        id: PluginID,
        version: SemanticVersion,
        module: Module.Type
    ) -> UnsafeMutableRawPointer {
        let registry = PluginRegistry()
        Module.register(in: registry)
        let manifest = PluginManifest(
            id: id,
            version: version,
            abiVersion: DyLibPluginABI.current,
            exports: registry.exports,
            dependencies: Module.dependencies)
        let descriptor = PluginDescriptor(manifest: manifest, registry: registry, module: module)
        return Unmanaged.passRetained(descriptor).toOpaque()
    }
}
