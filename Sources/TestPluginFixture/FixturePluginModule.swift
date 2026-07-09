import DyLibPlugin
import TestPluginFixtureInterface

struct FixturePluginModule: PluginModule {
    static func register(in registry: PluginRegistry) {
        registry.export(GreeterContract.self) { _ in FixtureGreeter() }
    }
}
