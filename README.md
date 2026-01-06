# CEnumMacros

Swift 6 macros for ergonomic enum access to imported C string constants.

## Overview

Swift can’t use imported C `#define` string constants as enum raw values because
raw values must be compile-time literals. This package instead generates
`RawRepresentable` conformance that *uses the imported constants directly*
at runtime.

## Usage

Add the package as a dependency and import the module:

```swift
// Package.swift
dependencies: [
  .package(url: "https://your.repo/CEnumMacros.git", from: "0.1.0")
],
targets: [
  .target(
    name: "YourTarget",
    dependencies: [
      .product(name: "CEnumMacros", package: "CEnumMacros")
    ]
  )
]
```

```swift
import CEnumMacros
```

### Define an enum

Annotate the enum with `@CEnumRawValues`, and each case with `@CEnumValue(...)`:

```swift
@CEnumRawValues
enum IOPSKey {
  @CEnumValue(kIOPSPowerAdapterIDKey)
  case powerAdapterID

  @CEnumValue(kIOPSPowerAdapterWattsKey)
  case powerAdapterWatts
}
```

The macro expands to a `RawRepresentable` implementation like:

```swift
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
```

### Notes

- Don’t declare a raw type or other conformances on the enum; the macro adds
  `RawRepresentable` and the `RawValue` typealias.
- One case per `case` declaration.
- No associated values or manual raw values for cases.
