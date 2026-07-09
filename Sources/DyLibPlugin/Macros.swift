/// Generates a `<Protocol>Contract` peer type conforming to `PluginContract`
/// for a public protocol: the typed key both plugin and host use instead of
/// magic strings. The contract's `compatibilityHash` is a stable hash of the
/// protocol's requirements, so interface drift between separately built
/// binaries is caught at load time.
///
/// - Parameter id: Overrides the interface identifier (defaults to the
///   protocol's name). Identifiers must be unique across the app's plugins.
@attached(peer, names: suffixed(Contract))
public macro PluginInterface(id: String? = nil) =
    #externalMacro(module: "DyLibPluginMacros", type: "PluginInterfaceMacro")

/// Marks the plugin module of a plugin binary and generates the exported
/// C entry point (`dylib_plugin_main`) plus the build-time verification
/// marker symbol. Attach to the type conforming to `PluginModule`.
///
/// - Parameters:
///   - id: Globally unique plugin identifier, e.g. `"com.demo.dog"`.
///   - version: The plugin's semantic version, e.g. `"1.0.0"`.
@attached(peer, names: arbitrary)
public macro PluginMain(id: String, version: String) =
    #externalMacro(module: "DyLibPluginMacros", type: "PluginMainMacro")
