import AnimalInterface
import TrickInterface
import DyLibRuntimeLoader

@DyLibConnect(Trick.self, framework: "TrickImplementation")
enum TrickPlugin {}

@DyLibExport(Animal.self)
public struct Dog: Animal {
    public init() {}
    public func speak() -> String { "Woof! (and does a \(TrickPlugin.instance.perform()))" }
}
