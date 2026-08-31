import Foundation

/// A lossless, concurrency-safe JSON value used by every public GRumpKit API.
public enum JSONValue: Codable, Sendable, Equatable, Hashable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int64.self) { self = .integer(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    public var objectValue: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    public var intValue: Int? {
        switch self {
        case .integer(let value): return Int(exactly: value)
        case .number(let value) where value.rounded() == value: return Int(exactly: value)
        default: return nil
        }
    }

    public subscript(key: String) -> JSONValue? { objectValue?[key] }

    public static func decode(data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func encoded(prettyPrinted: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        if prettyPrinted { encoder.outputFormatting = [.prettyPrinted, .sortedKeys] }
        return try encoder.encode(self)
    }
}

extension JSONValue: ExpressibleByNilLiteral { public init(nilLiteral: ()) { self = .null } }
extension JSONValue: ExpressibleByBooleanLiteral { public init(booleanLiteral value: Bool) { self = .bool(value) } }
extension JSONValue: ExpressibleByIntegerLiteral { public init(integerLiteral value: Int64) { self = .integer(value) } }
extension JSONValue: ExpressibleByFloatLiteral { public init(floatLiteral value: Double) { self = .number(value) } }
extension JSONValue: ExpressibleByStringLiteral { public init(stringLiteral value: String) { self = .string(value) } }
extension JSONValue: ExpressibleByArrayLiteral { public init(arrayLiteral elements: JSONValue...) { self = .array(elements) } }
extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) { self = .object(Dictionary(uniqueKeysWithValues: elements)) }
}
