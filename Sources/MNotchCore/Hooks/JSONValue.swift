import Foundation

/// A Sendable JSON tree, so hook payloads can cross from the server queue to the main actor.
public enum JSONValue: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let boolean = try? container.decode(Bool.self) {
            self = .bool(boolean)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let text = try? container.decode(String.self) {
            self = .string(text)
        } else if let items = try? container.decode([JSONValue].self) {
            self = .array(items)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let text): try container.encode(text)
        case .number(let number): try container.encode(number)
        case .bool(let boolean): try container.encode(boolean)
        case .array(let items): try container.encode(items)
        case .object(let fields): try container.encode(fields)
        case .null: try container.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        guard case .object(let fields) = self else { return nil }
        return fields[key]
    }

    public var stringValue: String? {
        guard case .string(let text) = self else { return nil }
        return text
    }

    public var intValue: Int? {
        guard case .number(let number) = self else { return nil }
        return Int(number)
    }

    public var boolValue: Bool? {
        guard case .bool(let boolean) = self else { return nil }
        return boolean
    }

    public var arrayValue: [JSONValue]? {
        guard case .array(let items) = self else { return nil }
        return items
    }

    public var isNull: Bool { self == .null }

    public static func decode(_ data: Data) -> JSONValue? {
        try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    public func encoded(sortedKeys: Bool = false) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = sortedKeys ? [.sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]
        return (try? encoder.encode(self)) ?? Data("null".utf8)
    }

    public var canonicalString: String {
        String(decoding: encoded(sortedKeys: true), as: UTF8.self)
    }
}
