import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct DyLibPluginMacrosPlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [
        PluginInterfaceMacro.self,
        PluginMainMacro.self,
    ]
}
