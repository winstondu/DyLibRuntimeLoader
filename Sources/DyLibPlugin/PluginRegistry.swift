/// Collects a plugin module's interface exports during `register(in:)`.
///
/// Not thread-safe by design: the runtime uses a fresh instance for the
/// single, synchronous `register(in:)` call at probe time.
public final class PluginRegistry {
    private(set) var factories: [InterfaceID: @Sendable (PluginContext) -> Any] = [:]
    private(set) var exports: [InterfaceExport] = []

    public init() {}

    /// Exports a factory for a contract. The compiler enforces that the
    /// factory returns the contract's interface type, so a plugin cannot
    /// register a mistyped implementation.
    public func export<C: PluginContract>(
        _ contract: C.Type,
        factory: @escaping @Sendable (PluginContext) -> C.Interface
    ) {
        let export = InterfaceExport(
            interfaceID: C.interfaceID,
            compatibilityHash: C.compatibilityHash)
        exports.removeAll { $0.interfaceID == C.interfaceID }
        exports.append(export)
        factories[C.interfaceID] = { context in factory(context) }
    }
}
