import DyLibPlugin

@_cdecl("dylib_plugin_main")
public func _dylibPluginMain() -> UnsafeMutableRawPointer {
    PluginEntryPoint.makeDescriptor(
        id: PluginID("com.fixture.greeter"),
        version: SemanticVersion(1, 0, 0),
        module: FixturePluginModule.self)
}

@_cdecl("dylib_plugin_id_com_fixture_greeter")
public func _dylibPluginMarker() -> Int32 { 0 }
