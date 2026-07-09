import ToolkitInterface

struct EchoSoundEffects: SoundEffects {
    func decorate(_ sound: String) -> String {
        "\(sound) \(sound.lowercased())..."
    }
}
