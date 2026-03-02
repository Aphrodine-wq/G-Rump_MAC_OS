import XCTest
@testable import GRump

final class StreamEventTests: XCTestCase {

    // MARK: - StreamEvent Enum

    func testStreamEventTextCase() {
        let event = StreamEvent.text("Hello world")
        if case .text(let content) = event {
            XCTAssertEqual(content, "Hello world")
        } else {
            XCTFail("Expected .text case")
        }
    }

    func testStreamEventDoneCase() {
        let event = StreamEvent.done("stop")
        if case .done(let reason) = event {
            XCTAssertEqual(reason, "stop")
        } else {
            XCTFail("Expected .done case")
        }
    }

    func testStreamEventToolCallDeltaCase() {
        let delta = ToolCallDelta(index: 0, id: "tc1", type: "function", function: nil)
        let event = StreamEvent.toolCallDelta([delta])
        if case .toolCallDelta(let deltas) = event {
            XCTAssertEqual(deltas.count, 1)
            XCTAssertEqual(deltas[0].id, "tc1")
        } else {
            XCTFail("Expected .toolCallDelta case")
        }
    }

    // MARK: - ToolCallDelta Codable

    func testToolCallDeltaCodableRoundTrip() throws {
        let fn = ToolCallFunctionDelta(name: "read_file", arguments: "{\"path\":\"/tmp\"}")
        let delta = ToolCallDelta(index: 0, id: "call_123", type: "function", function: fn)
        let data = try JSONEncoder().encode(delta)
        let decoded = try JSONDecoder().decode(ToolCallDelta.self, from: data)
        XCTAssertEqual(decoded.index, 0)
        XCTAssertEqual(decoded.id, "call_123")
        XCTAssertEqual(decoded.type, "function")
        XCTAssertEqual(decoded.function?.name, "read_file")
        XCTAssertEqual(decoded.function?.arguments, "{\"path\":\"/tmp\"}")
    }

    func testToolCallDeltaNilFields() throws {
        let delta = ToolCallDelta(index: nil, id: nil, type: nil, function: nil)
        let data = try JSONEncoder().encode(delta)
        let decoded = try JSONDecoder().decode(ToolCallDelta.self, from: data)
        XCTAssertNil(decoded.index)
        XCTAssertNil(decoded.id)
        XCTAssertNil(decoded.type)
        XCTAssertNil(decoded.function)
    }

    // MARK: - ToolCallFunctionDelta Codable

    func testToolCallFunctionDeltaCodable() throws {
        let fn = ToolCallFunctionDelta(name: "write_file", arguments: "{}")
        let data = try JSONEncoder().encode(fn)
        let decoded = try JSONDecoder().decode(ToolCallFunctionDelta.self, from: data)
        XCTAssertEqual(decoded.name, "write_file")
        XCTAssertEqual(decoded.arguments, "{}")
    }

    func testToolCallFunctionDeltaNilName() throws {
        let fn = ToolCallFunctionDelta(name: nil, arguments: "{\"partial\":true}")
        let data = try JSONEncoder().encode(fn)
        let decoded = try JSONDecoder().decode(ToolCallFunctionDelta.self, from: data)
        XCTAssertNil(decoded.name)
        XCTAssertEqual(decoded.arguments, "{\"partial\":true}")
    }

    func testToolCallFunctionDeltaNilArguments() throws {
        let fn = ToolCallFunctionDelta(name: "search", arguments: nil)
        let data = try JSONEncoder().encode(fn)
        let decoded = try JSONDecoder().decode(ToolCallFunctionDelta.self, from: data)
        XCTAssertEqual(decoded.name, "search")
        XCTAssertNil(decoded.arguments)
    }

    // MARK: - StreamChunk Codable

    func testStreamChunkDecodeFromJSON() throws {
        let json = """
        {
            "choices": [
                {
                    "delta": {
                        "content": "Hello"
                    },
                    "finish_reason": null
                }
            ]
        }
        """.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(StreamChunk.self, from: json)
        XCTAssertEqual(chunk.choices?.count, 1)
        XCTAssertEqual(chunk.choices?[0].delta?.content, "Hello")
        XCTAssertNil(chunk.choices?[0].finishReason)
    }

    func testStreamChunkDecodeWithFinishReason() throws {
        let json = """
        {
            "choices": [
                {
                    "delta": {},
                    "finish_reason": "stop"
                }
            ]
        }
        """.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(StreamChunk.self, from: json)
        XCTAssertEqual(chunk.choices?[0].finishReason, "stop")
    }

    func testStreamChunkDecodeWithToolCalls() throws {
        let json = """
        {
            "choices": [
                {
                    "delta": {
                        "tool_calls": [
                            {
                                "index": 0,
                                "id": "call_1",
                                "type": "function",
                                "function": {
                                    "name": "read_file",
                                    "arguments": "{\\"path\\":\\"/tmp\\"}"
                                }
                            }
                        ]
                    },
                    "finish_reason": null
                }
            ]
        }
        """.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(StreamChunk.self, from: json)
        let toolCalls = chunk.choices?[0].delta?.toolCalls
        XCTAssertEqual(toolCalls?.count, 1)
        XCTAssertEqual(toolCalls?[0].id, "call_1")
        XCTAssertEqual(toolCalls?[0].function?.name, "read_file")
    }

    func testStreamChunkDecodeEmptyChoices() throws {
        let json = """
        {"choices": []}
        """.data(using: .utf8)!
        let chunk = try JSONDecoder().decode(StreamChunk.self, from: json)
        XCTAssertEqual(chunk.choices?.count, 0)
    }

    // MARK: - StreamDelta Codable

    func testStreamDeltaDecodeRole() throws {
        let json = """
        {"role": "assistant", "content": null}
        """.data(using: .utf8)!
        let delta = try JSONDecoder().decode(StreamDelta.self, from: json)
        XCTAssertEqual(delta.role, "assistant")
        XCTAssertNil(delta.content)
    }

    func testStreamDeltaDecodeContent() throws {
        let json = """
        {"content": "Hello"}
        """.data(using: .utf8)!
        let delta = try JSONDecoder().decode(StreamDelta.self, from: json)
        XCTAssertEqual(delta.content, "Hello")
        XCTAssertNil(delta.role)
        XCTAssertNil(delta.toolCalls)
    }

    // MARK: - AIServiceError

    func testAIServiceErrorNoModelSelected() {
        let error = AIServiceError.noModelSelected
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("model") ?? false)
    }

    func testAIServiceErrorProviderNotConfigured() {
        let error = AIServiceError.providerNotConfigured
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("provider") ?? false)
    }

    func testAIServiceErrorNetwork() {
        let error = AIServiceError.networkError
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.lowercased().contains("network") ?? false)
    }

    func testAIServiceErrorAPIError() {
        let error = AIServiceError.apiError(401)
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.contains("401") ?? false)
    }

    func testAIServiceErrorInvalidResponse() {
        let error = AIServiceError.invalidResponse
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription?.lowercased().contains("invalid") ?? false)
    }

    func testAIServiceErrorAllCasesHaveDescriptions() {
        let errors: [AIServiceError] = [
            .noModelSelected,
            .providerNotConfigured,
            .networkError,
            .apiError(500),
            .invalidResponse,
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Missing errorDescription for \(error)")
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }
}
