import Testing

@testable import DyLibPlugin

private protocol RoundTripValue {
    var label: String { get }
}

private struct RoundTripValueImpl: RoundTripValue {
    let label = "round-trip"
}

private struct RoundTripValueContract: PluginContract {
    typealias Interface = RoundTripValue

    static var interfaceID: InterfaceID { InterfaceID("RoundTripValue") }
    static var compatibilityHash: String { "fnv1a:round-trip-value" }
}

private struct RoundTripModule: PluginModule {
    static func register(in registry: PluginRegistry) {
        registry.export(RoundTripValueContract.self) { _ in RoundTripValueImpl() }
    }
}

private final class StubResolver: PluginInstanceResolving {
    func resolveInstance(
        interfaceID: InterfaceID,
        compatibilityHash: String,
        from id: PluginID?
    ) throws -> Any {
        throw PluginError.interfaceNotExported(interfaceID)
    }
}

struct EntryPointRoundTripTests {
    @Test func descriptorRoundTripsThroughOpaquePointer() throws {
        let pointer = PluginEntryPoint.makeDescriptor(
            id: PluginID("com.test.roundtrip"),
            version: SemanticVersion(2, 1, 0),
            module: RoundTripModule.self)
        let descriptor = Unmanaged<PluginDescriptor>.fromOpaque(pointer).takeRetainedValue()

        #expect(descriptor.manifest.id == PluginID("com.test.roundtrip"))
        #expect(descriptor.manifest.version == SemanticVersion(2, 1, 0))
        #expect(descriptor.manifest.abiVersion == DyLibPluginABI.current)
        #expect(descriptor.manifest.dependencies.isEmpty)
        #expect(descriptor.manifest.exports == [
            InterfaceExport(
                interfaceID: InterfaceID("RoundTripValue"),
                compatibilityHash: "fnv1a:round-trip-value")
        ])

        let factory = try #require(descriptor.factories[InterfaceID("RoundTripValue")])
        let context = PluginContext(pluginID: PluginID("com.test.roundtrip"), resolver: StubResolver())
        let value = factory(context)
        let typed = try #require(value as? RoundTripValue)
        #expect(typed.label == "round-trip")
    }
}
