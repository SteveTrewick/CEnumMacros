import Foundation

private struct Options {
    let inputPath: String
    let outputPath: String
    let enumName: String
    let matchRegex: NSRegularExpression?
    let dropPrefixes: [String]
    let dropSuffixes: [String]
    let caseStyle: CaseStyle
    let accessLevel: String?
    let imports: [String]
}

private enum CaseStyle: String {
    case lowerCamel
    case upperCamel
    case keep
}

private struct CEnumGenConfig: Decodable {
    let input: String?
    let output: String?
    let enumName: String?
    let match: String?
    let dropPrefix: [String]?
    let dropSuffix: [String]?
    let caseStyle: String?
    let access: String?
    let imports: [String]?

    enum CodingKeys: String, CodingKey {
        case input
        case output
        case enumName = "enum"
        case match
        case dropPrefix
        case dropSuffix
        case caseStyle
        case access
        case imports
    }
}

private enum GenError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let msg):
            return msg
        }
    }
}

private let swiftKeywords: Set<String> = [
    "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
    "func", "import", "init", "inout", "internal", "let", "open", "operator",
    "private", "protocol", "public", "static", "struct", "subscript", "typealias",
    "var", "break", "case", "continue", "default", "defer", "do", "else",
    "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch",
    "where", "while", "as", "any", "catch", "false", "is", "nil", "rethrows",
    "super", "self", "Self", "throw", "throws", "true", "try", "_"
]

private func printUsage() {
    let usage = """
    Usage: CEnumGen --input <header.h> --output <file.swift> --enum <EnumName> [options]

    Options:
      --match <regex>            Only include #define names that match this regex
      --drop-prefix <prefix>     Drop this prefix from the C name (repeatable)
      --drop-suffix <suffix>     Drop this suffix from the C name (repeatable)
      --case-style <style>       lowerCamel (default), upperCamel, keep
      --access <level>           public, internal, package, fileprivate, private
      --import <module>          Add an import to the generated file (repeatable)
      --config <path>            Load settings from a JSON config file
      --help                     Show this help
    """
    FileHandle.standardError.write(Data(usage.utf8))
}

private func parseOptions(_ arguments: [String]) throws -> Options {
    let configPath = findConfigPath(in: arguments)
    let configURL = configPath.map(resolveConfigURL)
    let config = try configURL.map(loadConfig)

    var inputPath: String?
    var outputPath: String?
    var enumName: String?
    var matchPattern: String?
    var dropPrefixes: [String] = []
    var dropSuffixes: [String] = []
    var caseStyle: CaseStyle = .lowerCamel
    var accessLevel: String?
    var imports: [String] = []

    if let config {
        let baseDirectory = configURL?.deletingLastPathComponent()
        if let configInput = config.input {
            inputPath = resolvePath(configInput, relativeTo: baseDirectory)
        }
        if let configOutput = config.output {
            outputPath = resolvePath(configOutput, relativeTo: baseDirectory)
        }
        enumName = config.enumName ?? enumName
        matchPattern = config.match ?? matchPattern
        dropPrefixes = config.dropPrefix ?? dropPrefixes
        dropSuffixes = config.dropSuffix ?? dropSuffixes
        if let style = config.caseStyle {
            guard let parsed = CaseStyle(rawValue: style) else {
                throw GenError.message("Invalid caseStyle in config: \(style)")
            }
            caseStyle = parsed
        }
        accessLevel = config.access ?? accessLevel
        imports = config.imports ?? imports
    }

    var index = 0
    while index < arguments.count {
        let arg = arguments[index]
        switch arg {
        case "--help", "-h":
            printUsage()
            exit(0)
        case "--config":
            index += 1
            guard index < arguments.count else { throw GenError.message("Missing value for --config") }
        case "--input":
            index += 1
            guard index < arguments.count else { throw GenError.message("Missing value for --input") }
            inputPath = arguments[index]
        case "--output":
            index += 1
            guard index < arguments.count else { throw GenError.message("Missing value for --output") }
            outputPath = arguments[index]
        case "--enum":
            index += 1
            guard index < arguments.count else { throw GenError.message("Missing value for --enum") }
            enumName = arguments[index]
        case "--match":
            index += 1
            guard index < arguments.count else { throw GenError.message("Missing value for --match") }
            matchPattern = arguments[index]
        case "--drop-prefix":
            index += 1
            guard index < arguments.count else { throw GenError.message("Missing value for --drop-prefix") }
            dropPrefixes.append(arguments[index])
        case "--drop-suffix":
            index += 1
            guard index < arguments.count else { throw GenError.message("Missing value for --drop-suffix") }
            dropSuffixes.append(arguments[index])
        case "--case-style":
            index += 1
            guard index < arguments.count else { throw GenError.message("Missing value for --case-style") }
            let value = arguments[index]
            guard let style = CaseStyle(rawValue: value) else {
                throw GenError.message("Invalid --case-style: \(value)")
            }
            caseStyle = style
        case "--access":
            index += 1
            guard index < arguments.count else { throw GenError.message("Missing value for --access") }
            accessLevel = arguments[index]
        case "--import":
            index += 1
            guard index < arguments.count else { throw GenError.message("Missing value for --import") }
            imports.append(arguments[index])
        default:
            throw GenError.message("Unknown argument: \(arg)")
        }
        index += 1
    }

    guard let inputPathUnwrapped = inputPath else { throw GenError.message("Missing required --input") }
    guard let outputPathUnwrapped = outputPath else { throw GenError.message("Missing required --output") }
    guard let enumNameUnwrapped = enumName else { throw GenError.message("Missing required --enum") }

    let matchRegex: NSRegularExpression?
    if let pattern = matchPattern {
        matchRegex = try NSRegularExpression(pattern: pattern)
    } else {
        matchRegex = nil
    }

    if let accessLevel = accessLevel {
        let allowed: Set<String> = ["public", "internal", "package", "fileprivate", "private"]
        guard allowed.contains(accessLevel) else {
            throw GenError.message("Invalid --access: \(accessLevel)")
        }
    }

    return Options(
        inputPath: inputPathUnwrapped,
        outputPath: outputPathUnwrapped,
        enumName: enumNameUnwrapped,
        matchRegex: matchRegex,
        dropPrefixes: dropPrefixes,
        dropSuffixes: dropSuffixes,
        caseStyle: caseStyle,
        accessLevel: accessLevel,
        imports: imports
    )
}

private func findConfigPath(in arguments: [String]) -> String? {
    var index = 0
    while index < arguments.count {
        if arguments[index] == "--config" {
            let valueIndex = index + 1
            guard valueIndex < arguments.count else { return nil }
            return arguments[valueIndex]
        }
        index += 1
    }
    return nil
}

private func resolveConfigURL(_ path: String) -> URL {
    if path.hasPrefix("/") {
        return URL(fileURLWithPath: path)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(path)
}

private func resolvePath(_ path: String, relativeTo baseURL: URL?) -> String {
    if path.hasPrefix("/") {
        return path
    }
    let base = baseURL ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    return base.appendingPathComponent(path).path
}

private func loadConfig(from url: URL) throws -> CEnumGenConfig {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(CEnumGenConfig.self, from: data)
}

private func warn(_ message: String) {
    FileHandle.standardError.write(Data(("warning: \(message)\n").utf8))
}

private func dropFirstMatchingPrefix(_ value: String, prefixes: [String]) -> String {
    let matching = prefixes.filter { !($0.isEmpty) && value.hasPrefix($0) }
    guard let best = matching.max(by: { $0.count < $1.count }) else {
        return value
    }
    return String(value.dropFirst(best.count))
}

private func dropFirstMatchingSuffix(_ value: String, suffixes: [String]) -> String {
    let matching = suffixes.filter { !($0.isEmpty) && value.hasSuffix($0) }
    guard let best = matching.max(by: { $0.count < $1.count }) else {
        return value
    }
    return String(value.dropLast(best.count))
}

private func splitOnSeparators(_ value: String) -> [String] {
    let separators = CharacterSet.alphanumerics.inverted
    return value
        .components(separatedBy: separators)
        .filter { !$0.isEmpty }
}

private func lowerCamelFromCamel(_ value: String) -> String {
    guard !value.isEmpty else { return value }
    let chars = Array(value)
    if chars.count == 1 {
        return String(chars[0]).lowercased()
    }

    var index = 0
    while index < chars.count, chars[index].isUppercase {
        index += 1
    }

    if index == 0 {
        return value
    }

    if index == chars.count {
        return value.lowercased()
    }

    if index == 1 {
        return String(chars[0]).lowercased() + String(chars[1...])
    }

    let head = String(chars[0..<(index - 1)]).lowercased() + String(chars[index - 1])
    return head + String(chars[index...])
}

private func upperCamelFromTokens(_ tokens: [String]) -> String {
    tokens.map { token in
        guard let first = token.first else { return "" }
        return String(first).uppercased() + String(token.dropFirst()).lowercased()
    }.joined()
}

private func lowerCamelFromTokens(_ tokens: [String]) -> String {
    guard let first = tokens.first else { return "" }
    let head = first.lowercased()
    let tail = tokens.dropFirst().map { token in
        guard let first = token.first else { return "" }
        return String(first).uppercased() + String(token.dropFirst()).lowercased()
    }
    return ([head] + tail).joined()
}

private func applyCaseStyle(_ value: String, style: CaseStyle) -> String {
    switch style {
    case .keep:
        return value
    case .upperCamel:
        if value.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil {
            return upperCamelFromTokens(splitOnSeparators(value))
        }
        let tokens = splitOnSeparators(value)
        if tokens.count > 1 {
            return upperCamelFromTokens(tokens)
        }
        if value.isEmpty { return value }
        return String(value.prefix(1)).uppercased() + String(value.dropFirst())
    case .lowerCamel:
        if value.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) != nil {
            return lowerCamelFromTokens(splitOnSeparators(value))
        }
        let tokens = splitOnSeparators(value)
        if tokens.count > 1 {
            return lowerCamelFromTokens(tokens)
        }
        return lowerCamelFromCamel(value)
    }
}

private func sanitizeIdentifier(_ value: String) -> String {
    var result = ""
    var previousWasUnderscore = false

    for char in value {
        if char.isLetter || char.isNumber || char == "_" {
            result.append(char)
            previousWasUnderscore = (char == "_")
        } else {
            if !previousWasUnderscore {
                result.append("_")
                previousWasUnderscore = true
            }
        }
    }

    while result.hasPrefix("_") && result.count > 1 {
        result.removeFirst()
    }

    if let first = result.first, first.isNumber {
        result = "_" + result
    }

    if result.isEmpty {
        result = "_"
    }

    return result
}

private func escapeIfKeyword(_ value: String) -> String {
    if swiftKeywords.contains(value) {
        return "`\(value)`"
    }
    return value
}

private func generateEnum(options: Options) throws {
    let inputURL = URL(fileURLWithPath: options.inputPath)
    let source = try String(contentsOf: inputURL, encoding: .utf8)

    let defineRegex = try NSRegularExpression(pattern: "(?m)^\\s*#define\\s+([A-Za-z_][A-Za-z0-9_]*)\\b")
    let matches = defineRegex.matches(in: source, range: NSRange(source.startIndex..., in: source))

    var seenNames = Set<String>()
    var usedCaseNames = Set<String>()
    var entries: [(cName: String, caseName: String)] = []

    for match in matches {
        guard match.numberOfRanges > 1,
              let nameRange = Range(match.range(at: 1), in: source) else {
            continue
        }
        let cName = String(source[nameRange])
        if seenNames.contains(cName) {
            warn("Duplicate #define \(cName) found; keeping first occurrence")
            continue
        }
        seenNames.insert(cName)

        if let regex = options.matchRegex {
            let range = NSRange(location: 0, length: cName.utf16.count)
            if regex.firstMatch(in: cName, range: range) == nil {
                continue
            }
        }

        var base = dropFirstMatchingPrefix(cName, prefixes: options.dropPrefixes)
        base = dropFirstMatchingSuffix(base, suffixes: options.dropSuffixes)
        if base.isEmpty {
            warn("Skipping \(cName): name is empty after dropping prefix/suffix")
            continue
        }

        let styled = applyCaseStyle(base, style: options.caseStyle)
        let sanitized = sanitizeIdentifier(styled)

        if usedCaseNames.contains(sanitized) {
            throw GenError.message("Case name collision for '\(sanitized)' derived from \(cName)")
        }
        usedCaseNames.insert(sanitized)

        entries.append((cName: cName, caseName: escapeIfKeyword(sanitized)))
    }

    if entries.isEmpty {
        warn("No matching #define entries found")
    }

    let access = options.accessLevel.map { "\($0) " } ?? ""
    let caseAccess: String
    if let accessLevel = options.accessLevel, accessLevel == "public" || accessLevel == "package" {
        caseAccess = "\(accessLevel) "
    } else {
        caseAccess = ""
    }

    var lines: [String] = []
    lines.append("// Generated by CEnumGen. Do not edit.")
    for module in options.imports {
        lines.append("import \(module)")
    }
    lines.append("import CEnumMacros")
    lines.append("")
    lines.append("@CEnumRawValues")
    lines.append("\(access)enum \(options.enumName) {")

    for entry in entries {
        lines.append("  @CEnumValue(\(entry.cName))")
        lines.append("  \(caseAccess)case \(entry.caseName)")
        lines.append("")
    }

    if lines.last == "" {
        lines.removeLast()
    }
    lines.append("}")
    lines.append("")

    let outputURL = URL(fileURLWithPath: options.outputPath)
    try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try lines.joined(separator: "\n").write(to: outputURL, atomically: true, encoding: .utf8)
}

let args = Array(CommandLine.arguments.dropFirst())

do {
    let options = try parseOptions(args)
    try generateEnum(options: options)
} catch {
    let message: String
    if let error = error as? GenError {
        message = error.description
    } else {
        message = error.localizedDescription
    }
    FileHandle.standardError.write(Data(("error: \(message)\n").utf8))
    printUsage()
    exit(1)
}
