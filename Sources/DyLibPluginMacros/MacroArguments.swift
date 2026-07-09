import SwiftSyntax

enum MacroArguments {
    static func argument(labeled label: String, in node: AttributeSyntax) -> LabeledExprSyntax? {
        node.arguments?.as(LabeledExprListSyntax.self)?.first { $0.label?.text == label }
    }

    /// Returns the value of a static string literal (a single plain segment,
    /// no interpolation), or `nil` for any other expression.
    static func stringLiteralValue(_ expression: ExprSyntax) -> String? {
        guard let literal = expression.as(StringLiteralExprSyntax.self),
              literal.segments.count == 1,
              let segment = literal.segments.first?.as(StringSegmentSyntax.self)
        else { return nil }
        return segment.content.text
    }
}
