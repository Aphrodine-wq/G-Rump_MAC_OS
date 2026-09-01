import Foundation
import GRumpCore

enum ToolArguments {
    static func object(_ invocation: ToolInvocation) throws -> [String: JSONValue] {
        guard case .object(let object) = invocation.arguments else {
            throw ToolError(code: .invalidArguments, message: "Arguments must be an object")
        }
        return object
    }

    static func string(_ key: String, in object: [String: JSONValue], required: Bool = true) throws -> String? {
        if let value = object[key]?.stringValue { return value }
        if required { throw ToolError(code: .invalidArguments, message: "Argument '\(key)' must be a string") }
        return nil
    }

    static func bool(_ key: String, in object: [String: JSONValue], default fallback: Bool = false) -> Bool {
        object[key]?.boolValue ?? fallback
    }

    static func int(_ key: String, in object: [String: JSONValue]) -> Int? { object[key]?.intValue }

    static func strings(_ key: String, in object: [String: JSONValue]) throws -> [String] {
        guard case .array(let values)? = object[key] else {
            throw ToolError(code: .invalidArguments, message: "Argument '\(key)' must be an array")
        }
        let strings = values.compactMap(\.stringValue)
        guard strings.count == values.count else {
            throw ToolError(code: .invalidArguments, message: "Argument '\(key)' must contain only strings")
        }
        return strings
    }
}

extension ToolResult {
    static func success(_ invocation: ToolInvocation, text: String, json: JSONValue? = nil) -> ToolResult {
        ToolResult(invocationID: invocation.id, content: [.text(text)], structuredContent: json)
    }
}
