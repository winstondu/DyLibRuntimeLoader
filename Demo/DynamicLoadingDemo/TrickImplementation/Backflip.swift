import TrickInterface
import DyLibRuntimeLoader

@DyLibExport(Trick.self)
public struct Backflip: Trick {
    public init() {}
    public func perform() -> String { "backflip" }
}
