import AnimalInterface
import DemoLogging
import TrickInterface
import DyLibRuntimeLoader

@DyLibConnect(Trick.self, framework: "TrickImplementation", logger: DebugLogger.self)
enum TrickPlugin {}

@DyLibExport(Animal.self)
public struct Cat: Animal {
    public init() {}
    public func speak() -> String { "Meow! (and does a \(TrickPlugin.instance.perform()))" }
}
