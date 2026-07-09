import AnimalInterface
import DyLibPlugin
import ToolkitInterface

@PluginMain(id: "com.demo.dog", version: "1.0.0")
struct DogPluginModule: PluginModule {
    static let dependencies: [PluginDependency] = [
        .plugin("com.demo.toolkit", .from(SemanticVersion(1, 0, 0)))
    ]

    static func register(in registry: PluginRegistry) {
        registry.export(AnimalContract.self) { context in
            Dog(soundEffects: try? context.instance(of: SoundEffectsContract.self))
        }
    }
}
