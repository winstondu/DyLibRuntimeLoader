import DyLibPlugin
import Foundation
import Testing
import TestPluginFixtureInterface

// SwiftPM caveat: within one package, products embed their target
// dependencies statically, so this test executable and the fixture dylib
// each carry their own copy of the DyLibPlugin and fixture-interface
// metadata. In a real app those modules are shared dynamic frameworks
// embedded exactly once (the configuration the runtime requires). If the
// `as? Greeter` cast assertions fail under plain `swift test` while the
// symbol/manifest/error assertions pass, the cause is this duplication in
// the test harness, not the runtime.

private final class TestBundleLocator {}

private enum FixtureLibrary {
    static let path: String? = {
        let candidateNames = [
            "libTestPluginFixture.dylib",
            "libTestPluginFixture.so",
            "TestPluginFixture.framework/TestPluginFixture",
        ]
        var directories = [URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()]
        let bundleURL = Bundle(for: TestBundleLocator.self).bundleURL
        directories.append(bundleURL.deletingLastPathComponent())
        directories.append(bundleURL)
        for directory in directories {
            for name in candidateNames {
                let candidate = directory.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: candidate.path) {
                    return candidate.path
                }
            }
        }
        return nil
    }()

    static var isAvailable: Bool { path != nil }
}

@Suite(.enabled(
    if: FixtureLibrary.isAvailable,
    "TestPluginFixture dynamic library was not built next to the test executable"))
struct PluginManagerIntegrationTests {
    private let fixtureID = PluginID("com.fixture.greeter")

    @Test func registerReturnsFixtureManifest() throws {
        let path = try #require(FixtureLibrary.path)
        let manager = PluginManager()
        let manifest = try manager.register(.path(path))
        #expect(manifest.id == fixtureID)
        #expect(manifest.version == SemanticVersion(1, 0, 0))
        #expect(manifest.exports == [
            InterfaceExport(interfaceID: InterfaceID("Greeter"), compatibilityHash: "fnv1a:fixture-greeter")
        ])
        #expect(manager.registeredManifests.contains { $0.id == fixtureID })
    }

    @Test func instanceBeforeActivationThrowsNotActivated() throws {
        let path = try #require(FixtureLibrary.path)
        let manager = PluginManager()
        try manager.register(.path(path))
        #expect(throws: PluginError.notActivated(fixtureID)) {
            _ = try manager.instance(of: GreeterContract.self)
        }
    }

    @Test func activatedFixtureProvidesWorkingGreeter() throws {
        let path = try #require(FixtureLibrary.path)
        let manager = PluginManager()
        try manager.register(.path(path))
        try manager.activateAll()
        let greeter = try manager.instance(of: GreeterContract.self)
        #expect(greeter.greet(name: "World") == "Hello, World!")
    }

    @Test func unexportedInterfaceThrowsInterfaceNotExported() throws {
        let path = try #require(FixtureLibrary.path)
        let manager = PluginManager()
        try manager.register(.path(path))
        try manager.activateAll()
        #expect(throws: PluginError.interfaceNotExported(InterfaceID("Farewell"))) {
            _ = try manager.instance(of: FarewellContract.self)
        }
    }

    @Test func staleContractHashThrowsInterfaceIncompatible() throws {
        let path = try #require(FixtureLibrary.path)
        let manager = PluginManager()
        try manager.register(.path(path))
        try manager.activateAll()
        #expect(throws: PluginError.interfaceIncompatible(
            interfaceID: InterfaceID("Greeter"),
            hostHash: "fnv1a:stale",
            pluginHash: "fnv1a:fixture-greeter",
            plugin: fixtureID)
        ) {
            _ = try manager.instance(of: StaleGreeterContract.self)
        }
    }

    @Test func reRegisteringSamePathIsIdempotent() throws {
        let path = try #require(FixtureLibrary.path)
        let manager = PluginManager()
        let first = try manager.register(.path(path))
        let second = try manager.register(.path(path))
        #expect(second.id == first.id)
        #expect(second.version == first.version)
        #expect(manager.registeredManifests.count == 1)
    }

    @Test func loadingNonPluginLibraryThrowsNotAPlugin() throws {
        #if canImport(Darwin)
        // Resolved from the dyld shared cache, so no file-existence check.
        let libraryPath = "/usr/lib/libSystem.B.dylib"
        #else
        let candidates = [
            "/usr/lib/x86_64-linux-gnu/libz.so.1",
            "/usr/lib/aarch64-linux-gnu/libz.so.1",
            "/lib/x86_64-linux-gnu/libz.so.1",
        ]
        guard let libraryPath = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            return
        }
        #endif
        let manager = PluginManager()
        #expect(throws: PluginError.notAPlugin(path: libraryPath)) {
            try manager.register(.path(libraryPath))
        }
    }

    @Test func deactivateRemovesRegistrationAndReRegisterRevives() throws {
        let path = try #require(FixtureLibrary.path)
        let manager = PluginManager()
        try manager.register(.path(path))
        try manager.activateAll()
        try manager.deactivate(fixtureID)

        #expect(throws: PluginError.interfaceNotExported(InterfaceID("Greeter"))) {
            _ = try manager.instance(of: GreeterContract.self)
        }

        try manager.register(.path(path))
        try manager.activateAll()
        let greeter = try manager.instance(of: GreeterContract.self)
        #expect(greeter.greet(name: "World") == "Hello, World!")
    }
}
