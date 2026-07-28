import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct DyLibRuntimeLoaderPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        DyLibInterfaceMacro.self,
        DyLibExportMacro.self,
        DyLibConnectMacro.self,
    ]
}
