import DyLibPlugin

public protocol Greeter {
    func greet(name: String) -> String
}

/// Hand-written mirror of the `@PluginInterface` macro expansion so the
/// fixture stays independent of the macro targets and documents exactly what
/// the macro generates.
public struct GreeterContract: PluginContract {
    public typealias Interface = Greeter

    @inlinable public static var interfaceID: InterfaceID { InterfaceID("Greeter") }
    @inlinable public static var compatibilityHash: String { "fnv1a:fixture-greeter" }
}
