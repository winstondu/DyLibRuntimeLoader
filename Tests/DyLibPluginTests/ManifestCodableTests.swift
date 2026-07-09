import DyLibPlugin
import Foundation
import Testing

struct ManifestCodableTests {
    @Test func manifestRoundTripsThroughJSON() throws {
        let manifest = PluginManifest(
            id: PluginID("com.demo.dog"),
            version: SemanticVersion(1, 2, 3),
            abiVersion: DyLibPluginABI.current,
            exports: [
                InterfaceExport(interfaceID: InterfaceID("Animal"), compatibilityHash: "fnv1a:animal"),
                InterfaceExport(interfaceID: InterfaceID("SoundEffects"), compatibilityHash: "fnv1a:sound"),
            ],
            dependencies: [
                .plugin(PluginID("com.demo.toolkit"), .from(SemanticVersion(1, 0, 0))),
                .plugin(PluginID("com.demo.base"), .exact(SemanticVersion(2, 0, 1))),
                .plugin(PluginID("com.demo.util"), .atLeast(SemanticVersion(0, 9, 0))),
            ])

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(PluginManifest.self, from: data)

        #expect(decoded.id == manifest.id)
        #expect(decoded.version == manifest.version)
        #expect(decoded.abiVersion == manifest.abiVersion)
        #expect(decoded.exports == manifest.exports)
        #expect(decoded.dependencies == manifest.dependencies)
    }
}
