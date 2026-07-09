import DyLibPlugin

@PluginInterface
public protocol SoundEffects {
    func decorate(_ sound: String) -> String
}
