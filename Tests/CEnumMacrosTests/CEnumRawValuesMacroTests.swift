import SwiftSyntax
import SwiftSyntaxMacrosTestSupport
import XCTest

@testable import CEnumMacrosMacros

final class CEnumRawValuesMacroTests: XCTestCase {
    private let indentationWidth: Trivia = .spaces(2)

    func testGeneratesRawRepresentable() {
        assertMacroExpansion(
            """
            @CEnumRawValues
            enum IOPSKey {
              @CEnumValue(kIOPSPowerAdapterIDKey)
              case powerAdapterID
              @CEnumValue(kIOPSPowerAdapterWattsKey)
              case powerAdapterWatts
            }
            """,
            expandedSource: """
            enum IOPSKey {
              case powerAdapterID
              case powerAdapterWatts
            }

            extension IOPSKey: RawRepresentable {
              typealias RawValue = String
              init?(rawValue: String) {
                switch rawValue {
                  case kIOPSPowerAdapterIDKey:
                  self = .powerAdapterID
                  case kIOPSPowerAdapterWattsKey:
                  self = .powerAdapterWatts
                  default:
                  return nil
                }
              }

              var rawValue: String {
                switch self {
                  case .powerAdapterID:
                  return kIOPSPowerAdapterIDKey
                  case .powerAdapterWatts:
                  return kIOPSPowerAdapterWattsKey
                }
              }
            }
            """,
            macros: [
                "CEnumRawValues": CEnumRawValuesMacro.self,
                "CEnumValue": CEnumValueMacro.self
            ],
            indentationWidth: indentationWidth
        )
    }
}
