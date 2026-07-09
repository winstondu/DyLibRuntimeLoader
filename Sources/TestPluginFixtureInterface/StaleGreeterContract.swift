import DyLibPlugin

/// Simulates a host built against a newer revision of `Greeter` than the
/// fixture plugin: same interface identifier, different compatibility hash,
/// so resolution must fail with `PluginError.interfaceIncompatible`.
public struct StaleGreeterContract: PluginContract {
    public typealias Interface = Greeter

    @inlinable public static var interfaceID: InterfaceID { InterfaceID("Greeter") }
    @inlinable public static var compatibilityHash: String { "fnv1a:stale" }
}
