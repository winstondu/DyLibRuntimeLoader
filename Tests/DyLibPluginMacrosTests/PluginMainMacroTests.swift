import SwiftDiagnostics
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import DyLibPluginMacros

private let testMacros: [String: Macro.Type] = [
    "PluginInterface": PluginInterfaceMacro.self,
    "PluginMain": PluginMainMacro.self,
]

final class PluginMainMacroTests: XCTestCase {
    func testExpandsEntryPointAndMarker() {
        assertMacroExpansion(
            """
            @PluginMain(id: "com.demo.dog", version: "1.2.3")
            struct DogPlugin: PluginModule {
                static func register(in registry: PluginRegistry) {
                }
            }
            """,
            expandedSource: """
            struct DogPlugin: PluginModule {
                static func register(in registry: PluginRegistry) {
                }
            }

            @_cdecl("dylib_plugin_main")
            public func _dylibPluginMain() -> UnsafeMutableRawPointer {
                PluginEntryPoint.makeDescriptor(
                    id: PluginID("com.demo.dog"),
                    version: SemanticVersion(1, 2, 3),
                    module: DogPlugin.self)
            }

            @_cdecl("dylib_plugin_id_com_demo_dog")
            public func _dylibPluginMarker() -> Int32 {
                0
            }
            """,
            macros: testMacros)
    }

    func testSanitizesMarkerSymbol() {
        assertMacroExpansion(
            """
            @PluginMain(id: "com.demo-x.dog_2", version: "2.0.0")
            struct WeirdPlugin: PluginModule {
            }
            """,
            expandedSource: """
            struct WeirdPlugin: PluginModule {
            }

            @_cdecl("dylib_plugin_main")
            public func _dylibPluginMain() -> UnsafeMutableRawPointer {
                PluginEntryPoint.makeDescriptor(
                    id: PluginID("com.demo-x.dog_2"),
                    version: SemanticVersion(2, 0, 0),
                    module: WeirdPlugin.self)
            }

            @_cdecl("dylib_plugin_id_com_demo_x_dog_2")
            public func _dylibPluginMarker() -> Int32 {
                0
            }
            """,
            macros: testMacros)
    }

    func testProtocolEmitsError() {
        assertMacroExpansion(
            """
            @PluginMain(id: "com.demo.dog", version: "1.0.0")
            public protocol NotAModule {
            }
            """,
            expandedSource: """
            public protocol NotAModule {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@PluginMain can only be applied to a struct, class, enum, or actor",
                    line: 1,
                    column: 1)
            ],
            macros: testMacros)
    }

    func testMissingPluginModuleConformanceEmitsError() {
        assertMacroExpansion(
            """
            @PluginMain(id: "com.demo.dog", version: "1.0.0")
            struct DogPlugin {
            }
            """,
            expandedSource: """
            struct DogPlugin {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@PluginMain requires the attached type to declare conformance to PluginModule in its declaration (not in an extension)",
                    line: 1,
                    column: 1)
            ],
            macros: testMacros)
    }

    func testInvalidSemanticVersionEmitsError() {
        assertMacroExpansion(
            """
            @PluginMain(id: "com.demo.dog", version: "1.2")
            struct DogPlugin: PluginModule {
            }
            """,
            expandedSource: """
            struct DogPlugin: PluginModule {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "'1.2' is not a valid semantic version (expected major.minor.patch)",
                    line: 1,
                    column: 42)
            ],
            macros: testMacros)
    }

    func testNonLiteralVersionEmitsError() {
        assertMacroExpansion(
            """
            @PluginMain(id: "com.demo.dog", version: someVar)
            struct DogPlugin: PluginModule {
            }
            """,
            expandedSource: """
            struct DogPlugin: PluginModule {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "The 'version' argument must be a string literal",
                    line: 1,
                    column: 42)
            ],
            macros: testMacros)
    }

    func testEmptyIDEmitsError() {
        assertMacroExpansion(
            """
            @PluginMain(id: "", version: "1.0.0")
            struct DogPlugin: PluginModule {
            }
            """,
            expandedSource: """
            struct DogPlugin: PluginModule {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "Plugin id must not be empty",
                    line: 1,
                    column: 17)
            ],
            macros: testMacros)
    }
}
