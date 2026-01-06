@attached(extension, conformances: RawRepresentable)
public macro CEnumRawValues() = #externalMacro(
    module: "CEnumMacrosMacros",
    type: "CEnumRawValuesMacro"
)

@attached(peer)
public macro CEnumValue(_ value: Any) = #externalMacro(
    module: "CEnumMacrosMacros",
    type: "CEnumValueMacro"
)
