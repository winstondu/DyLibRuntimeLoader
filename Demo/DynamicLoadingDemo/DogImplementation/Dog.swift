import AnimalInterface
import DemoLogging
import TrickInterface
import Dynasty

@DyLibConnect(Trick.self, framework: "TrickImplementation", logger: DebugLogger.self)
enum TrickPlugin {}

@DyLibExport(Animal.self)
public struct Dog: Animal {
    public init() {}
    public func speak() -> String { "Woof! (and does a \(TrickPlugin.instance.perform()))" }
}
