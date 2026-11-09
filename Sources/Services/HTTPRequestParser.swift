import Foundation

public struct HTTPRequest: Equatable {
    public let method: String
    public let path: String
    public let headers: [String: String]
    public let body: Data

    /// Value of `name` in the Cookie header.
    public func cookie(_ name: String) -> String? {
        headers["cookie"]?
            .split(separator: ";")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("\(name)=") }
            .map { String($0.dropFirst(name.count + 1)) }
    }

    public var formFields: [String: String] {
        HTTPRequestParser.formFields(String(decoding: body, as: UTF8.self))
    }
}

/// Minimal HTTP/1.1 request parsing for the local configuration server.
public enum HTTPRequestParser {
    public enum Result: Equatable {
        case incomplete
        case invalid
        case complete(HTTPRequest)
    }

    public static let maxRequestSize = 64 * 1024

    public static func parse(_ data: Data) -> Result {
        if data.count > maxRequestSize { return .invalid }
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }

        let head = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/") else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? -1
        guard contentLength >= 0 else { return .invalid }
        let body = data[headerEnd.upperBound...]
        if body.count < contentLength { return .incomplete }

        return .complete(HTTPRequest(
            method: String(requestLine[0]),
            path: String(requestLine[1]),
            headers: headers,
            body: Data(body.prefix(contentLength))
        ))
    }

    /// Decodes `application/x-www-form-urlencoded` ("+" is a space).
    public static func formFields(_ body: String) -> [String: String] {
        var fields: [String: String] = [:]
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let rawKey = parts.first else { continue }
            let decode = { (value: Substring) in
                value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String(value)
            }
            fields[decode(rawKey)] = parts.count > 1 ? decode(parts[1]) : ""
        }
        return fields
    }

    public static func htmlEscape(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            case "'": escaped += "&#39;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}
