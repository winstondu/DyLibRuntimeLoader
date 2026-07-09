/// The single entry type of a plugin binary. Annotate the conforming type
/// with `@PluginMain(id:version:)` to generate the exported C entry point.
public protocol PluginModule {
    /// Other plugins that must be activated before this one.
    static var dependencies: [PluginDependency] { get }

    /// Export interface factories. Called once when the host probes the
    /// plugin; must not construct instances or perform work.
    static func register(in registry: PluginRegistry)

    /// Runs during `PluginManager.activateAll()`, after all dependencies
    /// have been activated.
    static func activate(context: PluginContext) throws

    /// Runs when the host deactivates the plugin. The binary itself stays
    /// mapped; only the registration is removed.
    static func willDeactivate(context: PluginContext)
}

extension PluginModule {
    public static var dependencies: [PluginDependency] { [] }

    public static func activate(context: PluginContext) throws {}

    public static func willDeactivate(context: PluginContext) {}
}
