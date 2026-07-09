import DyLibPlugin
import ToolkitInterface

@PluginMain(id: "com.demo.toolkit", version: "1.0.0")
struct AnimalToolkitPlugin: PluginModule {
    static func register(in registry: PluginRegistry) {
        registry.export(SoundEffectsContract.self) { _ in EchoSoundEffects() }
    }
}
