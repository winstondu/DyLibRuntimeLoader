/// The typed key connecting an interface protocol to its plugin providers.
///
/// Do not write conformances by hand: annotate the interface protocol with
/// `@PluginInterface` and use the generated `<Protocol>Contract` type. The
/// generated members are `@inlinable` so each binary freezes the values it
/// was compiled against, which is what makes load-time drift detection work.
public protocol PluginContract {
    associatedtype Interface

    static var interfaceID: InterfaceID { get }

    /// Stable hash of the interface protocol's requirements, computed at
    /// compile time by the `@PluginInterface` macro.
    static var compatibilityHash: String { get }
}

extension PluginContract {
    public static var export: InterfaceExport {
        InterfaceExport(interfaceID: interfaceID, compatibilityHash: compatibilityHash)
    }
}
