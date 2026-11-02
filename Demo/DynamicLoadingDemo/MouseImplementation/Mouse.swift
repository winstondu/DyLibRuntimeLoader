import AnimalInterface
import Dynasty

@DyLibExport(Animal.self)
public struct Mouse: Animal {
    public init() {}
    public func speak() -> String { "Squeak!" }
}
