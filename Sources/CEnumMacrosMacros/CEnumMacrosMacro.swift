import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

@main
struct CEnumMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        CEnumRawValuesMacro.self,
        CEnumValueMacro.self
    ]
}

struct CEnumValueMacro: PeerMacro {
    static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

struct CEnumRawValuesMacro: ExtensionMacro {
    static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard let enumDecl = declaration.as(EnumDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(declaration), message: MacroDiagnostic.invalidEnumTarget))
            return []
        }

        if let inheritance = enumDecl.inheritanceClause, !inheritance.inheritedTypes.isEmpty {
            context.diagnose(Diagnostic(node: Syntax(inheritance), message: MacroDiagnostic.rawTypeNotSupported))
            return []
        }

        var mappings: [(caseName: String, valueExpr: String)] = []

        for member in enumDecl.memberBlock.members {
            guard let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) else { continue }

            if caseDecl.elements.count != 1 {
                context.diagnose(Diagnostic(node: Syntax(caseDecl), message: MacroDiagnostic.multipleCaseElements))
                continue
            }

            guard let element = caseDecl.elements.first else { continue }

            if element.parameterClause != nil {
                context.diagnose(Diagnostic(node: Syntax(element), message: MacroDiagnostic.associatedValuesNotSupported))
                continue
            }

            if element.rawValue != nil {
                context.diagnose(Diagnostic(node: Syntax(element), message: MacroDiagnostic.rawValueNotSupported))
                continue
            }

            guard let valueExpr = cEnumValueExpression(from: caseDecl, in: context) else {
                context.diagnose(Diagnostic(node: Syntax(caseDecl), message: MacroDiagnostic.missingCEnumValue(element.name.text)))
                continue
            }

            mappings.append((caseName: element.name.text, valueExpr: valueExpr))
        }

        guard !mappings.isEmpty else {
            return []
        }

        let typeName = type.trimmedDescription
        let initCases = mappings
            .map { "      case \($0.valueExpr):\n      self = .\($0.caseName)" }
            .joined(separator: "\n")
        let rawCases = mappings
            .map { "      case .\($0.caseName):\n      return \($0.valueExpr)" }
            .joined(separator: "\n")

        let extensionDecl: DeclSyntax = """
        extension \(raw: typeName): RawRepresentable {
          typealias RawValue = String
          init?(rawValue: String) {
            switch rawValue {
        \(raw: initCases)
              default:
              return nil
            }
          }

          var rawValue: String {
            switch self {
        \(raw: rawCases)
            }
          }
        }
        """

        guard let extensionSyntax = extensionDecl.as(ExtensionDeclSyntax.self) else {
            context.diagnose(Diagnostic(node: Syntax(declaration), message: MacroDiagnostic.extensionGenerationFailed))
            return []
        }

        return [extensionSyntax]
    }

    private static func cEnumValueExpression(
        from caseDecl: EnumCaseDeclSyntax,
        in context: some MacroExpansionContext
    ) -> String? {
        var found: AttributeSyntax?
        for attribute in caseDecl.attributes {
            guard let attr = attribute.as(AttributeSyntax.self) else { continue }
            guard let name = attr.attributeName.as(IdentifierTypeSyntax.self)?.name.text else { continue }
            guard name == "CEnumValue" else { continue }

            if found != nil {
                context.diagnose(Diagnostic(node: Syntax(attr), message: MacroDiagnostic.duplicateCEnumValue))
                return nil
            }
            found = attr
        }

        guard let attribute = found else {
            return nil
        }

        guard case let .argumentList(arguments) = attribute.arguments,
              arguments.count == 1,
              let argument = arguments.first,
              argument.label == nil else {
            context.diagnose(Diagnostic(node: Syntax(attribute), message: MacroDiagnostic.invalidCEnumValueArguments))
            return nil
        }

        return argument.expression.trimmedDescription
    }
}

private enum MacroDiagnostic {
    static let invalidEnumTarget = SimpleDiagnostic(
        message: "@CEnumRawValues can only be attached to an enum declaration.",
        id: "CEnumMacros.invalidEnumTarget",
        severity: .error
    )

    static let rawTypeNotSupported = SimpleDiagnostic(
        message: "@CEnumRawValues enums must not declare a raw type or other conformances.",
        id: "CEnumMacros.rawTypeNotSupported",
        severity: .error
    )

    static let multipleCaseElements = SimpleDiagnostic(
        message: "@CEnumRawValues requires one case per declaration.",
        id: "CEnumMacros.multipleCaseElements",
        severity: .error
    )

    static let associatedValuesNotSupported = SimpleDiagnostic(
        message: "@CEnumRawValues does not support associated values.",
        id: "CEnumMacros.associatedValuesNotSupported",
        severity: .error
    )

    static let rawValueNotSupported = SimpleDiagnostic(
        message: "@CEnumRawValues cases must not declare raw values.",
        id: "CEnumMacros.rawValueNotSupported",
        severity: .error
    )

    static let duplicateCEnumValue = SimpleDiagnostic(
        message: "Duplicate @CEnumValue attribute found.",
        id: "CEnumMacros.duplicateCEnumValue",
        severity: .error
    )

    static let invalidCEnumValueArguments = SimpleDiagnostic(
        message: "@CEnumValue requires a single unlabeled argument.",
        id: "CEnumMacros.invalidCEnumValueArguments",
        severity: .error
    )

    static func missingCEnumValue(_ caseName: String) -> SimpleDiagnostic {
        SimpleDiagnostic(
            message: "Missing @CEnumValue for case '\(caseName)'.",
            id: "CEnumMacros.missingCEnumValue",
            severity: .error
        )
    }

    static let extensionGenerationFailed = SimpleDiagnostic(
        message: "Failed to generate extension for @CEnumRawValues.",
        id: "CEnumMacros.extensionGenerationFailed",
        severity: .error
    )
}

private struct SimpleDiagnostic: DiagnosticMessage {
    let message: String
    let id: String
    let severity: DiagnosticSeverity

    var diagnosticID: MessageID { MessageID(domain: "CEnumMacros", id: id) }
}
