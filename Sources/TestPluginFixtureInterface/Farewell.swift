import DyLibPlugin

public protocol Farewell {
    func farewell() -> String
}

/// Not exported by the fixture plugin; used to exercise
/// `PluginError.interfaceNotExported`.
public struct FarewellContract: PluginContract {
    public typealias Interface = Farewell

    @inlinable public static var interfaceID: InterfaceID { InterfaceID("Farewell") }
    @inlinable public static var compatibilityHash: String { "fnv1a:fixture-farewell" }
}
