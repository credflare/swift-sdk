import Foundation

public struct ShowIfCondition: Sendable {
    public let path: String
    public let op: String
    public let value: JSONValue
    init(_ raw: JSONValue) {
        path = raw["path"]?.stringValue ?? ""
        op = raw["op"]?.stringValue ?? ""
        value = raw["value"] ?? .null
    }
}

public struct ShowIf: Sendable {
    public let match: String
    public let conditions: [ShowIfCondition]
    public init?(_ raw: JSONValue?) {
        guard let raw, case .object = raw else { return nil }
        match = raw["match"]?.stringValue ?? CredflareSpec.Requirements.showIfDefaultMatch
        conditions = raw["conditions"]?.arrayValue?.map(ShowIfCondition.init) ?? []
    }

    public func matches(form: JSONValue) -> Bool {
        let results = conditions.map { Conditions.test($0, form: form) }
        return match == "any" ? results.contains(true) : !results.contains(false)
    }
}

public enum Conditions {
    public static func visible(_ showIf: ShowIf?, form: JSONValue) -> Bool {
        guard let showIf, !showIf.conditions.isEmpty else { return true }
        return showIf.matches(form: form)
    }

    public static func test(_ condition: ShowIfCondition, form: JSONValue) -> Bool {
        let resolved = resolve(condition.path, in: .object(["form": form]))
        let actual = resolved ?? .null
        let missing: Bool = { if case .null = actual { return true }; return false }()
        let empty = missing || actual.stringValue == "" || actual.arrayValue?.isEmpty == true
        switch condition.op {
        case "is_empty": return empty
        case "is_not_empty": return !empty
        default: break
        }
        if missing { return false }
        let expected = condition.value
        switch condition.op {
        case "equals": return equals(actual, expected)
        case "not_equals": return !equals(actual, expected)
        case "gt": return compare(actual, expected).map { $0 > 0 } ?? false
        case "gte": return compare(actual, expected).map { $0 >= 0 } ?? false
        case "lt": return compare(actual, expected).map { $0 < 0 } ?? false
        case "lte": return compare(actual, expected).map { $0 <= 0 } ?? false
        case "contains": return contains(actual, expected)
        case "not_contains": return !contains(actual, expected)
        case "in": if case .array(let list) = expected { return within(actual, list) }; return false
        case "not_in": if case .array(let list) = expected { return !within(actual, list) }; return false
        case "regex": return regex(actual, expected)
        case "fuzzy_match": return fuzzy(actual, expected)
        default: return false
        }
    }

    static func resolve(_ path: String, in context: JSONValue) -> JSONValue? {
        var value = context
        for segment in path.split(separator: ".", omittingEmptySubsequences: false).map(String.init) {
            switch value {
            case .object(let object): guard let next = object[segment] else { return nil }; value = next
            case .array(let list): guard let index = Int(segment), list.indices.contains(index) else { return nil }; value = list[index]
            default: return nil
            }
        }
        return value
    }

    private static func isContainer(_ value: JSONValue) -> Bool {
        switch value { case .object, .array: return true; default: return false }
    }

    private static func isScalar(_ value: JSONValue) -> Bool {
        switch value { case .string, .number, .bool: return true; default: return false }
    }

    private static let numeric = try! NSRegularExpression(pattern: #"^[ \t\n\r\u000B\f]*[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?[ \t\n\r\u000B\f]*$"#)
    private static let datePattern = try! NSRegularExpression(pattern: #"^\d{4}-\d{2}-\d{2}([T ][0-9:.]+(Z|[+-]\d{2}:?\d{2})?)?$"#)

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func number(_ value: JSONValue) -> Double? {
        switch value {
        case .number(let number): return number.isFinite ? number : nil
        case .string(let text):
            guard matches(numeric, text) else { return nil }
            return Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return nil
        }
    }

    static func text(_ value: JSONValue) -> String {
        switch value {
        case .bool(let flag): return flag ? "1" : ""
        case .null: return ""
        case .string(let text): return text
        case .number(let number):
            if number == number.rounded(), abs(number) < 1e15 { return String(Int64(number)) }
            return String(number)
        case .array(let list): return list.map(text).joined(separator: ",")
        case .object: return "[object Object]"
        }
    }

    private static func boolean(_ value: JSONValue) -> Bool? {
        if case .bool(let flag) = value { return flag }
        if isContainer(value) { return nil }
        let normalized = text(value).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["1", "true", "on", "yes"].contains(normalized) { return true }
        if ["0", "false", "off", "no", ""].contains(normalized) { return false }
        return nil
    }

    private static func truthy(_ value: JSONValue) -> Bool {
        switch value {
        case .object(let object): return !object.isEmpty
        case .array(let list): return !list.isEmpty
        case .number(let number): return number != 0
        case .string(let text): return !(text.isEmpty || text == "0")
        case .bool(let flag): return flag
        case .null: return true
        }
    }

    private static func entries(_ value: JSONValue) -> [(String, JSONValue)]? {
        switch value {
        case .object(let object): return object.map { ($0.key, $0.value) }
        case .array(let list): return list.enumerated().map { (String($0.offset), $0.element) }
        default: return nil
        }
    }

    private static func loose(_ a: JSONValue, _ b: JSONValue) -> Bool {
        let aNull: Bool = { if case .null = a { return true }; return false }()
        let bNull: Bool = { if case .null = b { return true }; return false }()
        if aNull || bNull {
            let other = aNull ? b : a
            if case .null = other { return true }
            if let items = entries(other) { return items.isEmpty }
            if case .string(let text) = other { return text.isEmpty }
            return boolean(other) == false
        }
        if case .bool = a { return truthy(a) == truthy(b) }
        if case .bool = b { return truthy(a) == truthy(b) }
        if isContainer(a) || isContainer(b) {
            guard let left = entries(a), let right = entries(b) else { return false }
            let other = Dictionary(right, uniquingKeysWith: { first, _ in first })
            guard left.count == other.count else { return false }
            return left.allSatisfy { key, value in other[key].map { loose(value, $0) } ?? false }
        }
        if let x = number(a), let y = number(b) { return x == y }
        return text(a) == text(b)
    }

    private static func equals(_ actual: JSONValue, _ expected: JSONValue) -> Bool {
        if isContainer(actual) || isContainer(expected) { return loose(actual, expected) }
        if case .bool = actual { return boolean(actual) == boolean(expected) }
        if case .bool = expected { return boolean(actual) == boolean(expected) }
        if let x = number(actual), let y = number(expected) { return x == y }
        return text(actual) == text(expected)
    }

    private static func time(_ value: String) -> Date? {
        var iso = value
        if let space = iso.firstIndex(of: " ") { iso.replaceSubrange(space...space, with: "T") }
        if !iso.contains("T") { iso += "T00:00:00" }
        if iso.range(of: #"(Z|[+-]\d{2}:?\d{2})$"#, options: .regularExpression) == nil { iso += "Z" }
        if let range = iso.range(of: #"([+-]\d{2})(\d{2})$"#, options: .regularExpression) {
            let offset = String(iso[range])
            iso.replaceSubrange(range, with: offset.prefix(3) + ":" + offset.suffix(2))
        }
        if let date = ISO8601.parse(iso) { return date }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mmXXXXX"
        return formatter.date(from: iso)
    }

    private static func compare(_ actual: JSONValue, _ expected: JSONValue) -> Int? {
        if let x = number(actual), let y = number(expected) { return x < y ? -1 : x > y ? 1 : 0 }
        guard case .string(let a) = actual, case .string(let b) = expected, matches(datePattern, a), matches(datePattern, b) else { return nil }
        guard let x = time(a), let y = time(b) else { return nil }
        return x < y ? -1 : x > y ? 1 : 0
    }

    private static func within(_ needle: JSONValue, _ haystack: [JSONValue]) -> Bool {
        haystack.contains { !isContainer($0) && !isContainer(needle) && equals(needle, $0) }
    }

    private static func contains(_ actual: JSONValue, _ expected: JSONValue) -> Bool {
        if let items = entries(actual) { return within(expected, items.map(\.1)) }
        if isScalar(actual), isScalar(expected), !text(expected).isEmpty {
            return text(actual).lowercased().contains(text(expected).lowercased())
        }
        return false
    }

    private static func regex(_ actual: JSONValue, _ pattern: JSONValue) -> Bool {
        guard isScalar(actual), case .string(let source) = pattern, source.utf16.count <= CredflareSpec.Requirements.showIfMaxPatternLength,
              let regex = try? NSRegularExpression(pattern: source) else { return false }
        return matches(regex, text(actual))
    }

    private static func fuzzy(_ actual: JSONValue, _ expected: JSONValue) -> Bool {
        guard isScalar(actual), case .object = expected, let target = expected["text"], isScalar(target) else { return false }
        func normalize(_ value: JSONValue) -> String {
            text(value).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        }
        let score = expected["min_score"] ?? .null
        let minimum: Double
        if case .null = score { minimum = Double(CredflareSpec.Requirements.showIfFuzzyDefaultMinScore) }
        else if let value = number(score) { minimum = value }
        else { return false }
        return similarity(normalize(actual), normalize(target)) >= minimum
    }

    public static func similarity(_ a: String, _ b: String) -> Double {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count + y.count > 0 else { return 0 }
        return Double(common(x[...], y[...]) * 2 * 100) / Double(x.count + y.count)
    }

    private static func common(_ a: ArraySlice<UInt8>, _ b: ArraySlice<UInt8>) -> Int {
        var best = 0, p1 = a.startIndex, p2 = b.startIndex
        for i in a.indices {
            for j in b.indices {
                var length = 0
                while i + length < a.endIndex, j + length < b.endIndex, a[i + length] == b[j + length] { length += 1 }
                if length > best { best = length; p1 = i; p2 = j }
            }
        }
        guard best > 0 else { return 0 }
        return best + common(a[a.startIndex..<p1], b[b.startIndex..<p2]) + common(a[(p1 + best)...], b[(p2 + best)...])
    }
}
