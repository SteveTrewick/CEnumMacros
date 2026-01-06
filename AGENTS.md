## CEnumMacros

# Problem Definition

Swift cannot use imported C `#define` string constants as enum raw values
because raw values must be compile-time literals. Swift macros also cannot
evaluate imported C constants into literals.

We want ergonomic enums that map to imported C string constants without
hard-coding literal values or referencing external header paths.

## Solution

Provide macros that generate `RawRepresentable` conformance using the imported
constants directly:

- `@CEnumRawValues` attaches to an enum and generates `RawRepresentable` with
  `RawValue = String`, using a switch over the imported constants.
- `@CEnumValue(...)` attaches to each case with the corresponding imported
  C constant.

## Example

```swift
@CEnumRawValues
enum IOPSKey {
  @CEnumValue(kIOPSPowerAdapterIDKey)
  case powerAdapterID
}
```
