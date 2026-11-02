import TrickInterface
import Dynasty

@DyLibExport(Trick.self)
public struct Backflip: Trick {
    public init() {}
    public func perform() -> String { "backflip" }
}
