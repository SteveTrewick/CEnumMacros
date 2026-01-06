# CEnumMacros

Swift 6 macros for ergonomic enum access to imported C string constants.

## Overview


Let's say we have a .h file (in this case, IOPSKeys.h) with a bunch of defines

```c
 /*!
  @define kIOPSPowerAdapterIDKey
  @astract This key refers to the attached external AC power adapter's ID.
         The value associated with this key is a CFNumberRef intger.
  @discussion This key may be present in the dictionary returned from @link IOPSCopyExternalPowerAdapterDetails @/link
         This key might not be defined for any given power source.
  */
 #define kIOPSPowerAdapterIDKey          "AdapterID"
```

Swift can’t use imported C `#define` string constants as enum raw values because
raw values must be compile-time literals. This package instead generates
`RawRepresentable` conformance that *uses the imported constants directly*
at runtime.

So we can't do this :
```swift
enum IOPSKey : String {
  case powerAdapterID = kIOPSPowerAdapterIDKey
}
```

But we **can** do *this* :

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

So we can do things like :

```swift
if let cenum = IOPSKey(rawValue: "AdapterID") {
  print(cenum)
}
```

Or, more importantly (and likely)

```swift
for key in dict.keys {
  if let keynum = IOPSKey(rawValue: key) {
    // now we have a strongly typed dot not'd enum, nice.
  }
}
```

### Notes

- Don’t declare a raw type or other conformances on the enum; the macro adds
  `RawRepresentable` and the `RawValue` typealias.
- One case per `case` declaration.
- No associated values or manual raw values for cases.
