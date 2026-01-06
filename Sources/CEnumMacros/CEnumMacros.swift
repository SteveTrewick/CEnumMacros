@attached(
    extension,
    conformances: RawRepresentable,
    names: named(RawValue), named(rawValue), named(init(rawValue:))
)
public macro CEnumRawValues() = #externalMacro(
    module: "CEnumMacrosMacros",
    type: "CEnumRawValuesMacro"
)

@attached(peer)
public macro CEnumValue(_ value: Any) = #externalMacro(
    module: "CEnumMacrosMacros",
    type: "CEnumValueMacro"
)
