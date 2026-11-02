import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct DynastyPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DyLibInterfaceMacro.self,
        DyLibExportMacro.self,
        DyLibConnectMacro.self,
    ]
}
