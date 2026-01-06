// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "CEnumMacros",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "CEnumMacros",
            targets: ["CEnumMacros"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        .macro(
            name: "CEnumMacrosMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .target(
            name: "CEnumMacros",
            dependencies: ["CEnumMacrosMacros"]
        ),
        .testTarget(
            name: "CEnumMacrosTests",
            dependencies: [
                "CEnumMacrosMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        )
    ]
)
