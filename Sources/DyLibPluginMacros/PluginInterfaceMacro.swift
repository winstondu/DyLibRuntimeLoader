import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Generates the `<Protocol>Contract` peer type for a `public` protocol.
///
/// The generated `interfaceID` and `compatibilityHash` accessors are
/// `@inlinable` on purpose, and that is load-bearing: the interface module
/// ships as one shared dynamic library, so a plain `static var` would resolve
/// through that single runtime copy for both host and plugins and the values
/// could never differ. `@inlinable` freezes the literals into each separately
/// compiled binary, so a plugin built against an older protocol shape carries
/// the hash from its own build and load-time drift detection can catch the
/// mismatch.
public struct PluginInterfaceMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let protocolDecl = declaration.as(ProtocolDeclSyntax.self) else {
            context.diagnose(
                MacroDiagnosticMessage(
                    id: "interfaceNotAProtocol",
                    message: "@PluginInterface can only be applied to a protocol"),
                at: node)
            return []
        }

        guard protocolDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.public) }) else {
            context.diagnose(
                MacroDiagnosticMessage(
                    id: "interfaceNotPublic",
                    message: "@PluginInterface requires the protocol to be public (host and plugins must both see it)"),
                at: node)
            return []
        }

        var identifier = protocolDecl.name.text
        if let idArgument = MacroArguments.argument(labeled: "id", in: node),
           !idArgument.expression.is(NilLiteralExprSyntax.self) {
            guard let value = MacroArguments.stringLiteralValue(idArgument.expression) else {
                context.diagnose(
                    MacroDiagnosticMessage(
                        id: "interfaceIDNotLiteral",
                        message: "The 'id' argument must be a string literal"),
                    at: idArgument.expression)
                return []
            }
            identifier = value
        }

        var normalizedRequirements: [String] = []
        for member in protocolDecl.memberBlock.members {
            let memberDecl = member.decl
            guard memberDecl.is(FunctionDeclSyntax.self)
                || memberDecl.is(VariableDeclSyntax.self)
                || memberDecl.is(InitializerDeclSyntax.self)
                || memberDecl.is(SubscriptDeclSyntax.self)
                || memberDecl.is(AssociatedTypeDeclSyntax.self)
            else { continue }
            normalizedRequirements.append(RequirementHasher.normalize(memberDecl.trimmedDescription))
        }

        let inheritedTypes = protocolDecl.inheritanceClause?.inheritedTypes.map {
            $0.type.trimmedDescription
        } ?? []

        if normalizedRequirements.isEmpty {
            context.diagnose(
                MacroDiagnosticMessage(
                    id: "interfaceHasNoRequirements",
                    message: "Protocol has no requirements; the compatibility hash will not detect drift",
                    severity: .warning),
                at: node)
        }

        let hash = RequirementHasher.hash(
            normalizedRequirements: normalizedRequirements,
            inheritedTypes: inheritedTypes)
        let name = protocolDecl.name.text

        let contract: DeclSyntax = """
            public struct \(raw: name)Contract: PluginContract {
                public typealias Interface = \(raw: name)
                @inlinable public static var interfaceID: InterfaceID { InterfaceID(\(literal: identifier)) }
                @inlinable public static var compatibilityHash: String { \(literal: hash) }
            }
            """
        return [contract]
    }
}
