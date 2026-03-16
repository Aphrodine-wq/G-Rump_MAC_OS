import XCTest
@testable import GRump

/// Comprehensive tests for XMLToolCallParser — validates all 3 XML format patterns,
/// edge cases, stripping behavior, and argument serialization.
final class XMLToolCallParserTests: XCTestCase {

    // MARK: - Pattern 1: <execute>

    func testParseExecuteBlock() {
        let input = """
        <execute>
          <function>read_file</function>
          <parameter name="path">/src/main.swift</parameter>
        </execute>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].name, "read_file")
        XCTAssertEqual(result.toolCalls[0].arguments["path"], "/src/main.swift")
    }

    func testParseExecuteBlockMultipleParams() {
        let input = """
        <execute>
          <function>edit_file</function>
          <parameter name="path">/src/main.swift</parameter>
          <parameter name="content">let x = 1</parameter>
          <parameter name="mode">replace</parameter>
        </execute>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].arguments.count, 3)
        XCTAssertEqual(result.toolCalls[0].arguments["content"], "let x = 1")
        XCTAssertEqual(result.toolCalls[0].arguments["mode"], "replace")
    }

    func testParseExecuteBlockNoParams() {
        let input = """
        <execute>
          <function>list_directory</function>
        </execute>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].name, "list_directory")
        XCTAssertTrue(result.toolCalls[0].arguments.isEmpty)
    }

    func testParseExecuteBlockMissingFunction() {
        let input = """
        <execute>
          <parameter name="path">/src/main.swift</parameter>
        </execute>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertTrue(result.toolCalls.isEmpty, "Should not parse without <function>")
    }

    func testParseExecuteBlockEmptyFunctionName() {
        let input = """
        <execute>
          <function>  </function>
        </execute>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertTrue(result.toolCalls.isEmpty, "Should not parse empty function name")
    }

    // MARK: - Pattern 2: <tool_call>

    func testParseToolCallBlock() {
        let input = """
        <tool_call>
          <name>web_search</name>
          <arguments>{"query":"Swift concurrency"}</arguments>
        </tool_call>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].name, "web_search")
        XCTAssertEqual(result.toolCalls[0].arguments["query"], "Swift concurrency")
    }

    func testParseToolCallBlockNoArguments() {
        let input = """
        <tool_call>
          <name>stop_generation</name>
        </tool_call>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].name, "stop_generation")
        XCTAssertTrue(result.toolCalls[0].arguments.isEmpty)
    }

    func testParseToolCallBlockInvalidJSON() {
        let input = """
        <tool_call>
          <name>search</name>
          <arguments>not valid json</arguments>
        </tool_call>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].name, "search")
        XCTAssertTrue(result.toolCalls[0].arguments.isEmpty, "Invalid JSON should produce empty args")
    }

    func testParseToolCallBlockMissingName() {
        let input = """
        <tool_call>
          <arguments>{"key":"value"}</arguments>
        </tool_call>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertTrue(result.toolCalls.isEmpty, "Should not parse without <name>")
    }

    func testParseToolCallBlockEmptyName() {
        let input = """
        <tool_call>
          <name>   </name>
          <arguments>{"key":"value"}</arguments>
        </tool_call>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertTrue(result.toolCalls.isEmpty, "Should not parse empty name")
    }

    // MARK: - Pattern 3: <function_call name="...">

    func testParseFunctionCallBlock() {
        let input = """
        <function_call name="read_file">
          <parameter name="path">/src/main.swift</parameter>
        </function_call>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].name, "read_file")
        XCTAssertEqual(result.toolCalls[0].arguments["path"], "/src/main.swift")
    }

    func testParseFunctionCallBlockMultipleParams() {
        let input = """
        <function_call name="write_file">
          <parameter name="path">/src/out.swift</parameter>
          <parameter name="content">import Foundation</parameter>
        </function_call>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].arguments.count, 2)
    }

    func testParseFunctionCallBlockNoParams() {
        let input = """
        <function_call name="get_status">
        </function_call>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].name, "get_status")
        XCTAssertTrue(result.toolCalls[0].arguments.isEmpty)
    }

    // MARK: - Text Stripping

    func testStrippedTextRemovesXMLBlocks() {
        let input = """
        Here is my analysis.
        <execute>
          <function>read_file</function>
          <parameter name="path">/src/main.swift</parameter>
        </execute>
        And here is more text.
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertFalse(result.strippedText.contains("<execute>"))
        XCTAssertFalse(result.strippedText.contains("</execute>"))
        XCTAssertTrue(result.strippedText.contains("Here is my analysis."))
        XCTAssertTrue(result.strippedText.contains("And here is more text."))
    }

    func testStrippedTextCollapsesNewlines() {
        let input = """
        Before.



        <execute>
          <function>test</function>
        </execute>



        After.
        """
        let result = XMLToolCallParser.parse(input)
        // Should not have 3+ consecutive newlines
        XCTAssertFalse(result.strippedText.contains("\n\n\n"))
    }

    func testStrippedTextTrimsWhitespace() {
        let input = "   <execute><function>test</function></execute>   "
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.strippedText, "")
    }

    // MARK: - Multiple Tool Calls

    func testParseMultipleMixedFormats() {
        let input = """
        I'll use two tools:
        <execute>
          <function>read_file</function>
          <parameter name="path">/a.swift</parameter>
        </execute>
        <tool_call>
          <name>web_search</name>
          <arguments>{"query":"test"}</arguments>
        </tool_call>
        <function_call name="write_file">
          <parameter name="path">/b.swift</parameter>
        </function_call>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 3)
        XCTAssertEqual(result.toolCalls[0].name, "read_file")
        XCTAssertEqual(result.toolCalls[1].name, "web_search")
        XCTAssertEqual(result.toolCalls[2].name, "write_file")
    }

    func testParseMultipleSameFormat() {
        let input = """
        <execute><function>tool1</function></execute>
        <execute><function>tool2</function></execute>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 2)
    }

    // MARK: - containsXMLToolCalls Quick Check

    func testContainsXMLToolCallsExecute() {
        XCTAssertTrue(XMLToolCallParser.containsXMLToolCalls("Some <execute> block"))
    }

    func testContainsXMLToolCallsToolCall() {
        XCTAssertTrue(XMLToolCallParser.containsXMLToolCalls("Some <tool_call> block"))
    }

    func testContainsXMLToolCallsFunctionCall() {
        XCTAssertTrue(XMLToolCallParser.containsXMLToolCalls("Some <function_call name=\"x\"> block"))
    }

    func testDoesNotContainXMLToolCalls() {
        XCTAssertFalse(XMLToolCallParser.containsXMLToolCalls("No XML here"))
        XCTAssertFalse(XMLToolCallParser.containsXMLToolCalls(""))
        XCTAssertFalse(XMLToolCallParser.containsXMLToolCalls("<html><body>Not a tool call</body></html>"))
    }

    // MARK: - argumentsJSON Serialization

    func testArgumentsJSONEmpty() {
        let call = ParsedXMLToolCall(name: "test", arguments: [:])
        XCTAssertEqual(call.argumentsJSON, "{}")
    }

    func testArgumentsJSONWithValues() {
        let call = ParsedXMLToolCall(name: "test", arguments: ["key": "value"])
        let json = call.argumentsJSON
        XCTAssertTrue(json.contains("key"))
        XCTAssertTrue(json.contains("value"))
    }

    func testArgumentsJSONIsValidJSON() {
        let call = ParsedXMLToolCall(name: "test", arguments: ["path": "/src/main.swift", "mode": "read"])
        let data = call.argumentsJSON.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?["path"] as? String, "/src/main.swift")
        XCTAssertEqual(parsed?["mode"] as? String, "read")
    }

    // MARK: - Edge Cases

    func testEmptyInput() {
        let result = XMLToolCallParser.parse("")
        XCTAssertTrue(result.toolCalls.isEmpty)
        XCTAssertTrue(result.strippedText.isEmpty)
    }

    func testNoToolCallsInInput() {
        let input = "Just a regular message with no XML tool calls."
        let result = XMLToolCallParser.parse(input)
        XCTAssertTrue(result.toolCalls.isEmpty)
        XCTAssertEqual(result.strippedText, input)
    }

    func testMalformedXMLNotCrash() {
        let inputs = [
            "<execute>no closing tag",
            "<tool_call><name>test</name>",
            "<function_call name=\"test\">",
            "<execute><function></function></execute>", // empty function
            "<tool_call><name></name></tool_call>", // empty name
        ]
        for input in inputs {
            let result = XMLToolCallParser.parse(input)
            // Should not crash
            _ = result.strippedText
            _ = result.toolCalls
        }
    }

    func testSpecialCharactersInParameterValues() {
        let input = """
        <execute>
          <function>write_file</function>
          <parameter name="content">let x = "hello & world" // 'test' <tag></parameter>
        </execute>
        """
        let result = XMLToolCallParser.parse(input)
        // The content has XML-unfriendly characters, but since we use regex (not XML parser),
        // it may still work partially. The key thing is it shouldn't crash.
        XCTAssertTrue(result.toolCalls.count <= 1)
    }

    func testMultilineParameterValue() {
        let input = """
        <execute>
          <function>write_file</function>
          <parameter name="content">line 1
        line 2
        line 3</parameter>
        </execute>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 1)
        let content = result.toolCalls[0].arguments["content"] ?? ""
        XCTAssertTrue(content.contains("line 1"))
        XCTAssertTrue(content.contains("line 3"))
    }

    func testWhitespaceInFunctionName() {
        let input = """
        <execute>
          <function>  read_file  </function>
        </execute>
        """
        let result = XMLToolCallParser.parse(input)
        XCTAssertEqual(result.toolCalls.count, 1)
        XCTAssertEqual(result.toolCalls[0].name, "read_file", "Should trim whitespace from name")
    }

    func testNestedXMLTags() {
        // Some models might produce nested tags — should not crash
        let input = """
        <execute>
          <function>test</function>
          <parameter name="data"><nested>value</nested></parameter>
        </execute>
        """
        let result = XMLToolCallParser.parse(input)
        // The regex may or may not handle this, but it shouldn't crash
        _ = result.toolCalls
    }

    // MARK: - ParsedXMLToolCall Properties

    func testParsedXMLToolCallName() {
        let call = ParsedXMLToolCall(name: "my_tool", arguments: [:])
        XCTAssertEqual(call.name, "my_tool")
    }

    func testParsedXMLToolCallArguments() {
        let args = ["a": "1", "b": "2", "c": "3"]
        let call = ParsedXMLToolCall(name: "test", arguments: args)
        XCTAssertEqual(call.arguments.count, 3)
        XCTAssertEqual(call.arguments["a"], "1")
    }

    // MARK: - XMLToolCallParseResult Properties

    func testParseResultStrippedTextAndToolCalls() {
        let result = XMLToolCallParseResult(strippedText: "clean", toolCalls: [])
        XCTAssertEqual(result.strippedText, "clean")
        XCTAssertTrue(result.toolCalls.isEmpty)
    }
}
