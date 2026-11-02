import AnimalInterface
import Dynasty

@DyLibExport(Animal.self)
public struct Cat: Animal {
    public init() {}
    public func speak() -> String { "Meow" }
}
