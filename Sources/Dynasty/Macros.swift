import Foundation

@attached(peer, names: suffixed(PluginSpec), suffixed(LazyProxy))
public macro DyLibInterface(version: Int = 1, proxy: Bool = true) =
    #externalMacro(module: "DynastyMacros", type: "DyLibInterfaceMacro")

@attached(peer, names: prefixed(__dylib_export_))
public macro DyLibExport(_ interface: Any.Type, version: Int = 1) =
    #externalMacro(module: "DynastyMacros", type: "DyLibExportMacro")

@attached(member, names: named(library), named(instance), named(loadIfNeeded), named(isLoaded), named(_dylibLazy))
@attached(extension, conformances: DyLibPluginConnection, names: named(Interface))
public macro DyLibConnect(
    _ interface: Any.Type,
    framework: String,
    dependencies: [Any.Type] = [],
    bundle: Bundle? = nil,
    logger: Any.Type? = nil
) = #externalMacro(module: "DynastyMacros", type: "DyLibConnectMacro")
