import Foundation

// MARK: - XML Tool Call Parser
//
// Some models (e.g. Glm-4.6) emit tool invocations as inline XML instead of
// using the native tool_calls API mechanism. This parser detects, extracts,
// and strips those XML blocks so they never appear as raw markup in chat.
//
// Supported formats:
//   <execute> <function>tool_name</function> <parameter name="key">value</parameter> </execute>
//   <tool_call> <name>tool_name</name> <arguments>{"key":"value"}</arguments> </tool_call>
//   <function_call name="tool_name"> <parameter name="key">value</parameter> </function_call>

struct ParsedXMLToolCall {
    let name: String
    let arguments: [String: String]

    /// Serialize arguments to JSON string for compatibility with native tool call buffers.
    var argumentsJSON: String {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments, options: []),
              let str = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return str
    }
}

struct XMLToolCallParseResult {
    /// Text with all XML tool call blocks removed.
    let strippedText: String
    /// Parsed tool calls extracted from the text.
    let toolCalls: [ParsedXMLToolCall]
}

enum XMLToolCallParser {

    // MARK: - Public API

    /// Parse and strip XML tool calls from the given text.
    /// Returns the cleaned text and any extracted tool calls.
    static func parse(_ text: String) -> XMLToolCallParseResult {
        var stripped = text
        var calls: [ParsedXMLToolCall] = []

        // Pattern 1: <execute>...</execute>
        calls.append(contentsOf: extractExecuteBlocks(&stripped))

        // Pattern 2: <tool_call>...</tool_call>
        calls.append(contentsOf: extractToolCallBlocks(&stripped))

        // Pattern 3: <function_call name="...">...</function_call>
        calls.append(contentsOf: extractFunctionCallBlocks(&stripped))

        // Clean up leftover whitespace from removed blocks
        stripped = collapseExtraNewlines(stripped)

        return XMLToolCallParseResult(strippedText: stripped, toolCalls: calls)
    }

    /// Quick check if text likely contains XML tool calls (cheap pre-filter).
    static func containsXMLToolCalls(_ text: String) -> Bool {
        text.contains("<execute>") ||
        text.contains("<tool_call>") ||
        text.contains("<function_call")
    }

    // MARK: - Pattern 1: <execute><function>name</function><parameter name="k">v</parameter></execute>

    private static func extractExecuteBlocks(_ text: inout String) -> [ParsedXMLToolCall] {
        let pattern = #"<execute>\s*(.*?)\s*</execute>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var calls: [ParsedXMLToolCall] = []

        for match in matches.reversed() {
            let fullRange = match.range
            let innerRange = match.range(at: 1)
            let inner = nsText.substring(with: innerRange)

            if let call = parseExecuteInner(inner) {
                calls.insert(call, at: 0)
            }
            text = (text as NSString).replacingCharacters(in: fullRange, with: "")
        }
        return calls
    }

    private static func parseExecuteInner(_ inner: String) -> ParsedXMLToolCall? {
        // Extract function name
        let fnPattern = #"<function>\s*(.*?)\s*</function>"#
        guard let fnRegex = try? NSRegularExpression(pattern: fnPattern, options: []),
              let fnMatch = fnRegex.firstMatch(in: inner, range: NSRange(location: 0, length: (inner as NSString).length)) else {
            return nil
        }
        let name = (inner as NSString).substring(with: fnMatch.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        // Extract parameters
        let paramPattern = #"<parameter\s+name\s*=\s*"([^"]+)"\s*>\s*(.*?)\s*</parameter>"#
        guard let paramRegex = try? NSRegularExpression(pattern: paramPattern, options: [.dotMatchesLineSeparators]) else {
            return ParsedXMLToolCall(name: name, arguments: [:])
        }
        let paramMatches = paramRegex.matches(in: inner, range: NSRange(location: 0, length: (inner as NSString).length))
        var args: [String: String] = [:]
        for pm in paramMatches {
            let key = (inner as NSString).substring(with: pm.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = (inner as NSString).substring(with: pm.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            args[key] = value
        }

        return ParsedXMLToolCall(name: name, arguments: args)
    }

    // MARK: - Pattern 2: <tool_call><name>name</name><arguments>{...}</arguments></tool_call>

    private static func extractToolCallBlocks(_ text: inout String) -> [ParsedXMLToolCall] {
        let pattern = #"<tool_call>\s*(.*?)\s*</tool_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var calls: [ParsedXMLToolCall] = []

        for match in matches.reversed() {
            let fullRange = match.range
            let innerRange = match.range(at: 1)
            let inner = nsText.substring(with: innerRange)

            if let call = parseToolCallInner(inner) {
                calls.insert(call, at: 0)
            }
            text = (text as NSString).replacingCharacters(in: fullRange, with: "")
        }
        return calls
    }

    private static func parseToolCallInner(_ inner: String) -> ParsedXMLToolCall? {
        let namePattern = #"<name>\s*(.*?)\s*</name>"#
        guard let nameRegex = try? NSRegularExpression(pattern: namePattern, options: []),
              let nameMatch = nameRegex.firstMatch(in: inner, range: NSRange(location: 0, length: (inner as NSString).length)) else {
            return nil
        }
        let name = (inner as NSString).substring(with: nameMatch.range(at: 1))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }

        // Try to extract JSON arguments
        let argsPattern = #"<arguments>\s*(.*?)\s*</arguments>"#
        var args: [String: String] = [:]
        if let argsRegex = try? NSRegularExpression(pattern: argsPattern, options: [.dotMatchesLineSeparators]),
           let argsMatch = argsRegex.firstMatch(in: inner, range: NSRange(location: 0, length: (inner as NSString).length)) {
            let argsStr = (inner as NSString).substring(with: argsMatch.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let data = argsStr.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (k, v) in parsed {
                    args[k] = "\(v)"
                }
            }
        }

        return ParsedXMLToolCall(name: name, arguments: args)
    }

    // MARK: - Pattern 3: <function_call name="..."><parameter name="k">v</parameter></function_call>

    private static func extractFunctionCallBlocks(_ text: inout String) -> [ParsedXMLToolCall] {
        let pattern = #"<function_call\s+name\s*=\s*"([^"]+)"\s*>\s*(.*?)\s*</function_call>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var calls: [ParsedXMLToolCall] = []

        for match in matches.reversed() {
            let fullRange = match.range
            let nameRange = match.range(at: 1)
            let innerRange = match.range(at: 2)
            let name = nsText.substring(with: nameRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let inner = nsText.substring(with: innerRange)

            guard !name.isEmpty else {
                text = (text as NSString).replacingCharacters(in: fullRange, with: "")
                continue
            }

            // Extract parameters (same format as execute blocks)
            let paramPattern = #"<parameter\s+name\s*=\s*"([^"]+)"\s*>\s*(.*?)\s*</parameter>"#
            var args: [String: String] = [:]
            if let paramRegex = try? NSRegularExpression(pattern: paramPattern, options: [.dotMatchesLineSeparators]) {
                let paramMatches = paramRegex.matches(in: inner, range: NSRange(location: 0, length: (inner as NSString).length))
                for pm in paramMatches {
                    let key = (inner as NSString).substring(with: pm.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
                    let value = (inner as NSString).substring(with: pm.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
                    args[key] = value
                }
            }

            calls.insert(ParsedXMLToolCall(name: name, arguments: args), at: 0)
            text = (text as NSString).replacingCharacters(in: fullRange, with: "")
        }
        return calls
    }

    // MARK: - Helpers

    private static func collapseExtraNewlines(_ text: String) -> String {
        // Replace 3+ consecutive newlines with 2
        var result = text
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
