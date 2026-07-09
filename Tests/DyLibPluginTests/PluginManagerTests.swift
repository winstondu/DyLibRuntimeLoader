import DyLibPlugin
import Testing
import TestPluginFixtureInterface

struct PluginManagerTests {
    @Test func registeringMissingLibraryThrowsLibraryOpenFailed() {
        let manager = PluginManager()
        do {
            try manager.register(.path("/nonexistent/libnope.dylib"))
            Issue.record("Expected libraryOpenFailed")
        } catch PluginError.libraryOpenFailed(let path, let reason) {
            #expect(path == "/nonexistent/libnope.dylib")
            #expect(!reason.isEmpty)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test func deactivatingUnknownPluginThrowsPluginNotRegistered() {
        let manager = PluginManager()
        #expect(throws: PluginError.pluginNotRegistered(PluginID("com.unknown"))) {
            try manager.deactivate(PluginID("com.unknown"))
        }
    }

    @Test func resolvingWithNothingRegisteredThrowsInterfaceNotExported() {
        let manager = PluginManager()
        #expect(throws: PluginError.interfaceNotExported(InterfaceID("Greeter"))) {
            _ = try manager.instance(of: GreeterContract.self)
        }
    }
}
