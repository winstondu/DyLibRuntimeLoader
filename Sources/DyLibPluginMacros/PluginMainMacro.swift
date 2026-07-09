import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Generates the exported C entry point (`dylib_plugin_main`) and the
/// per-plugin marker symbol for the type conforming to `PluginModule`.
/// The marker symbol name must match `DyLibPluginABI.sanitizedSymbolComponent`,
/// which maps every character outside ASCII letters and digits to `_`.
public struct PluginMainMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let attachedType = attachedTypeInfo(of: declaration) else {
            context.diagnose(
                MacroDiagnosticMessage(
                    id: "mainInvalidDeclarationKind",
                    message: "@PluginMain can only be applied to a struct, class, enum, or actor"),
                at: node)
            return []
        }

        guard declaresPluginModuleConformance(attachedType.inheritanceClause) else {
            context.diagnose(
                MacroDiagnosticMessage(
                    id: "mainMissingPluginModuleConformance",
                    message: "@PluginMain requires the attached type to declare conformance to PluginModule in its declaration (not in an extension)"),
                at: node)
            return []
        }

        guard let idArgument = MacroArguments.argument(labeled: "id", in: node) else {
            context.diagnose(
                MacroDiagnosticMessage(
                    id: "mainIDNotLiteral",
                    message: "The 'id' argument must be a string literal"),
                at: node)
            return []
        }
        guard let id = MacroArguments.stringLiteralValue(idArgument.expression) else {
            context.diagnose(
                MacroDiagnosticMessage(
                    id: "mainIDNotLiteral",
                    message: "The 'id' argument must be a string literal"),
                at: idArgument.expression)
            return []
        }
        guard !id.isEmpty else {
            context.diagnose(
                MacroDiagnosticMessage(
                    id: "mainIDEmpty",
                    message: "Plugin id must not be empty"),
                at: idArgument.expression)
            return []
        }

        guard let versionArgument = MacroArguments.argument(labeled: "version", in: node) else {
            context.diagnose(
                MacroDiagnosticMessage(
                    id: "mainVersionNotLiteral",
                    message: "The 'version' argument must be a string literal"),
                at: node)
            return []
        }
        guard let version = MacroArguments.stringLiteralValue(versionArgument.expression) else {
            context.diagnose(
                MacroDiagnosticMessage(
                    id: "mainVersionNotLiteral",
                    message: "The 'version' argument must be a string literal"),
                at: versionArgument.expression)
            return []
        }
        guard let components = semanticVersionComponents(of: version) else {
            context.diagnose(
                MacroDiagnosticMessage(
                    id: "mainVersionInvalid",
                    message: "'\(version)' is not a valid semantic version (expected major.minor.patch)"),
                at: versionArgument.expression)
            return []
        }

        let sanitizedID = sanitizedSymbolComponent(id)

        let entryPoint: DeclSyntax = """
            @_cdecl("dylib_plugin_main")
            public func _dylibPluginMain() -> UnsafeMutableRawPointer {
                PluginEntryPoint.makeDescriptor(
                    id: PluginID(\(literal: id)),
                    version: SemanticVersion(\(raw: String(components.major)), \(raw: String(components.minor)), \(raw: String(components.patch))),
                    module: \(raw: attachedType.name).self)
            }
            """

        let marker: DeclSyntax = """
            @_cdecl("dylib_plugin_id_\(raw: sanitizedID)")
            public func _dylibPluginMarker() -> Int32 {
                0
            }
            """

        return [entryPoint, marker]
    }

    private static func attachedTypeInfo(
        of declaration: some DeclSyntaxProtocol
    ) -> (name: String, inheritanceClause: InheritanceClauseSyntax?)? {
        if let decl = declaration.as(StructDeclSyntax.self) {
            return (decl.name.text, decl.inheritanceClause)
        }
        if let decl = declaration.as(ClassDeclSyntax.self) {
            return (decl.name.text, decl.inheritanceClause)
        }
        if let decl = declaration.as(EnumDeclSyntax.self) {
            return (decl.name.text, decl.inheritanceClause)
        }
        if let decl = declaration.as(ActorDeclSyntax.self) {
            return (decl.name.text, decl.inheritanceClause)
        }
        return nil
    }

    private static func declaresPluginModuleConformance(_ clause: InheritanceClauseSyntax?) -> Bool {
        guard let clause else { return false }
        return clause.inheritedTypes.contains { inherited in
            let name = inherited.type.trimmedDescription
            return name == "PluginModule" || name.hasSuffix(".PluginModule")
        }
    }

    private static func semanticVersionComponents(
        of version: String
    ) -> (major: Int, minor: Int, patch: Int)? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let major = Int(parts[0]),
              let minor = Int(parts[1]),
              let patch = Int(parts[2]),
              major >= 0, minor >= 0, patch >= 0
        else { return nil }
        return (major, minor, patch)
    }

    private static func sanitizedSymbolComponent(_ identifier: String) -> String {
        String(identifier.map { character in
            character.isASCII && (character.isLetter || character.isNumber) ? character : "_"
        })
    }
}
