import Foundation

/// One parsed HTTP/1.1 request. Header names are lowercased.
public struct HTTPRequest: Sendable, Equatable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data
}

/// Minimal HTTP/1.1 request parser and response builder for the local hook endpoint.
public enum HTTPMessage {
    public static let maxBodyBytes = 1_048_576
    static let maxHeaderBytes = 16_384

    public enum ParseResult: Sendable, Equatable {
        case incomplete
        case complete(HTTPRequest)
        case invalid(String)
        case tooLarge(Int)
    }

    public static func parse(_ buffer: Data) -> ParseResult {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else {
            return buffer.count > maxHeaderBytes ? .invalid("header block over \(maxHeaderBytes) bytes") : .incomplete
        }
        let headerText = String(decoding: buffer[buffer.startIndex..<headerEnd.lowerBound], as: UTF8.self)
        var lines = headerText.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3 else {
            return .invalid("request line '\(requestLine.joined(separator: " "))'")
        }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let declaredLength = Int(headers["content-length"] ?? "0") ?? -1
        guard declaredLength >= 0 else {
            return .invalid("content-length '\(headers["content-length"] ?? "")'")
        }
        guard declaredLength <= maxBodyBytes else { return .tooLarge(declaredLength) }
        let bodyStart = headerEnd.upperBound
        guard buffer.count - (bodyStart - buffer.startIndex) >= declaredLength else { return .incomplete }
        let body = buffer[bodyStart..<(bodyStart + declaredLength)]
        return .complete(HTTPRequest(method: String(requestLine[0]), path: String(requestLine[1]),
                                     headers: headers, body: Data(body)))
    }

    public static func response(status: Int, body: Data = Data()) -> Data {
        let reason = [200: "OK", 400: "Bad Request", 401: "Unauthorized", 403: "Forbidden",
                      404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large"][status] ?? "Error"
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n\r\n"
        return Data(head.utf8) + body
    }
}
