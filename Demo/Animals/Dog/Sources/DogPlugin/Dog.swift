import AnimalInterface
import ToolkitInterface

final class Dog: Animal {
    private let soundEffects: SoundEffects?

    init(soundEffects: SoundEffects?) {
        self.soundEffects = soundEffects
    }

    func speak() -> String {
        let sound = "woof"
        guard let soundEffects else { return sound }
        return soundEffects.decorate(sound)
    }
}
