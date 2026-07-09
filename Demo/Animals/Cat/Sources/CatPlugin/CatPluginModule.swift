import AnimalInterface
import DyLibPlugin

@PluginMain(id: "com.demo.cat", version: "1.0.0")
struct CatPluginModule: PluginModule {
    static func register(in registry: PluginRegistry) {
        registry.export(AnimalContract.self) { _ in Cat() }
    }
}
