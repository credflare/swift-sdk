import Foundation

public struct Question: Identifiable, Sendable {
    public let key: String
    public let label: String
    public let type: String
    public let required: Bool
    public let options: [String]
    public let min: Double?
    public let max: Double?
    public let showIf: ShowIf?
    public var id: String { key }
    init(_ raw: JSONValue) {
        key = raw["key"]?.stringValue ?? ""
        label = raw["label"]?.stringValue ?? ""
        type = raw["type"]?.stringValue ?? "text"
        required = raw["required"]?.boolValue ?? false
        options = raw["options"]?.arrayValue?.compactMap(\.stringValue) ?? []
        min = raw["min"]?.doubleValue
        max = raw["max"]?.doubleValue
        showIf = ShowIf(raw["show_if"])
    }
    public var isSupported: Bool { CredflareSpec.Requirements.questionsTypes.contains(type) && type != "founders" }
    public var isChoice: Bool { CredflareSpec.Requirements.questionsChoiceTypes.contains(type) }
}

public struct Questionnaire: Sendable {
    public let questions: [Question]
    public init(questions: [Question]) { self.questions = questions }
    init?(_ schema: JSONValue?) {
        guard let list = schema?.arrayValue, !list.isEmpty else { return nil }
        questions = list.map(Question.init)
    }

    public var isSupported: Bool { questions.allSatisfy(\.isSupported) }

    public func visibleQuestions(_ answers: [String: JSONValue]) -> [Question] {
        var context: [String: JSONValue] = [:]
        var shown: [Question] = []
        for question in questions where Conditions.visible(question.showIf, form: .object(context)) {
            shown.append(question)
            if let answer = answers[question.key] { context[question.key] = answer }
        }
        return shown
    }

    public func errors(_ answers: [String: JSONValue]) -> [String: String] {
        var errors: [String: String] = [:]
        for question in visibleQuestions(answers) {
            if let key = Self.problem(question, answers[question.key] ?? .null) { errors[question.key] = key }
        }
        return errors
    }

    public func fields(_ answers: [String: JSONValue]) -> [String: JSONValue] {
        var fields: [String: JSONValue] = [:]
        for question in visibleQuestions(answers) {
            guard let answer = answers[question.key], !Self.isEmpty(answer) else { continue }
            fields[question.key] = Self.normalized(question, answer)
        }
        return fields
    }

    static func isEmpty(_ answer: JSONValue) -> Bool {
        switch answer {
        case .null: return true
        case .string(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let list): return list.isEmpty
        default: return false
        }
    }

    static func normalized(_ question: Question, _ answer: JSONValue) -> JSONValue {
        switch (question.type, answer) {
        case ("number", .string(let text)): return Double(text.trimmingCharacters(in: .whitespaces)).map(JSONValue.number) ?? answer
        case (_, .string(let text)): return .string(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default: return answer
        }
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }

    static func isEmail(_ value: String) -> Bool {
        value.count <= CredflareSpec.Requirements.questionsEmailMaxLength && matches(#"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, value)
    }

    static func isDate(_ value: String) -> Bool {
        guard matches(CredflareSpec.Requirements.questionsDatePattern, value) else { return false }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == parts[0] && back.month == parts[1] && back.day == parts[2]
    }

    static func problem(_ question: Question, _ answer: JSONValue) -> String? {
        typealias Key = CredflareSpec.CopyKey
        if question.type == "consent" {
            return question.required && answer.boolValue != true ? Key.questionsConsentRequired : nil
        }
        if isEmpty(answer) { return question.required ? Key.questionsRequired : nil }
        let text = answer.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch question.type {
        case "text", "textarea":
            return (text?.count ?? 0) > CredflareSpec.Requirements.questionsTextMaxLength ? Key.questionsTextTooLong : nil
        case "number":
            let value: Double?
            if let number = answer.doubleValue { value = number }
            else if let text, matches(CredflareSpec.Requirements.questionsNumberPattern, text) { value = Double(text) }
            else { value = nil }
            guard let value else { return Key.questionsInvalidNumber }
            if let min = question.min, value < min { return Key.questionsNumberMin }
            if let max = question.max, value > max { return Key.questionsNumberMax }
            return nil
        case "date": return text.map(isDate) == true ? nil : Key.questionsInvalidDate
        case "email": return text.map(isEmail) == true ? nil : Key.questionsInvalidEmail
        case "phone", "tel": return text.map { matches(CredflareSpec.Requirements.questionsPhonePattern, $0) } == true ? nil : Key.questionsInvalidPhone
        case "select", "single_select": return text.map(question.options.contains) == true ? nil : Key.questionsChooseOne
        case "multi_select":
            let picked = answer.arrayValue?.compactMap(\.stringValue) ?? []
            return Set(picked).count == picked.count && picked.allSatisfy(question.options.contains) ? nil : Key.questionsRequired
        case "country": return text.map { matches(CredflareSpec.Requirements.questionsCountryPattern, $0) } == true ? nil : Key.questionsChooseCountry
        default: return nil
        }
    }

    public static func message(_ key: String, question: Question) -> String {
        func format(_ value: Double?) -> String { value.map { Conditions.text(.number($0)) } ?? "" }
        return CredflareCopy.text(key, ["min": format(question.min), "max": format(question.max)])
    }
}
