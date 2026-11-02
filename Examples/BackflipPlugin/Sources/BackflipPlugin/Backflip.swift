import Dynasty
import TrickInterface

@DyLibExport(Trick.self)
public struct Backflip: Trick {
    public init() {}
    public func perform() -> String { "backflip" }
}
