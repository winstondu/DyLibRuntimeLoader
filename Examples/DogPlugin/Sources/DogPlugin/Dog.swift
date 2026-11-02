import AnimalInterface
import Dynasty
import Foundation
import TrickInterface

@DyLibExport(Animal.self)
public struct Dog: Animal {
    public init() {}

    public func speak() -> String {
        guard
            let path = ProcessInfo.processInfo.environment["TRICK_PLUGIN_PATH"],
            let trick = try? TrickPluginSpec.load(from: path)
        else { return "Woof!" }
        return "Woof! (and does a \(trick.perform()))"
    }
}
