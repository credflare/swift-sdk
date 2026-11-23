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
    public var isSupported: Bool { CredflareSpec.Requirements.questionsTypes.contains(type) }
    public var isChoice: Bool { CredflareSpec.Requirements.questionsChoiceTypes.contains(type) }
}

public struct Questionnaire: Sendable {
    public let questions: [Question]
    public let earlierAnswers: [String: JSONValue]
    var numberTexts: [String: String] = [:]
    public init(questions: [Question], earlierAnswers: [String: JSONValue] = [:]) { self.questions = questions; self.earlierAnswers = earlierAnswers }
    init?(_ schema: JSONValue?, earlierAnswers: [String: JSONValue] = [:], numberTexts: [String: String] = [:]) {
        guard let list = schema?.arrayValue, !list.isEmpty else { return nil }
        self.init(questions: list.map(Question.init), earlierAnswers: earlierAnswers)
        self.numberTexts = numberTexts
    }

    public var startingAnswers: [String: JSONValue] {
        var answers: [String: JSONValue] = [:]
        for question in questions {
            guard let answer = earlierAnswers[question.key] else { continue }
            if case .number = answer, let text = numberTexts[question.key] { answers[question.key] = .string(text) }
            else { answers[question.key] = answer }
        }
        return answers
    }

    public func unsupportedQuestionShown(_ answers: [String: JSONValue]) -> Bool {
        visibleQuestions(answers).contains { !$0.isSupported }
    }

    public var isSupported: Bool { !unsupportedQuestionShown(startingAnswers) }

    public func visibleQuestions(_ answers: [String: JSONValue]) -> [Question] {
        var context = earlierAnswers.filter { key, _ in !questions.contains { $0.key == key } }
        var shown: [Question] = []
        for question in questions where Conditions.visible(question.showIf, form: .object(context)) {
            shown.append(question)
            if let answer = answers[question.key].flatMap({ Self.submitted(question, $0) }) { context[question.key] = answer }
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
            if let answer = answers[question.key].flatMap({ Self.submitted(question, $0) }) { fields[question.key] = answer }
            else if earlierAnswers[question.key] != nil { fields[question.key] = .null }
        }
        return fields
    }

    static func submitted(_ question: Question, _ answer: JSONValue) -> JSONValue? {
        guard !isEmpty(question, answer) else { return nil }
        if question.type == "founders", case .object(let value) = answer {
            return .object(["includes_applicant": .bool(value["includes_applicant"]?.boolValue ?? false), "names": .array(founderNames(answer).map(JSONValue.string))])
        }
        if case .string(let text) = answer { return .string(text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return answer
    }

    static func founderNames(_ answer: JSONValue) -> [String] {
        (answer["names"]?.arrayValue ?? []).compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    static func isEmpty(_ question: Question, _ answer: JSONValue) -> Bool {
        if question.type == "founders", case .object = answer {
            return answer["includes_applicant"]?.boolValue != true && founderNames(answer).isEmpty
        }
        return isEmpty(answer)
    }

    static func isEmpty(_ answer: JSONValue) -> Bool {
        switch answer {
        case .null: return true
        case .string(let text): return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .array(let list): return list.isEmpty
        default: return false
        }
    }

    private static func matches(_ pattern: String, _ text: String) -> Bool { text.range(of: pattern, options: .regularExpression) != nil }

    static func isEmail(_ value: String) -> Bool {
        value.count <= CredflareSpec.Requirements.questionsEmailMaxLength && matches(#"^[^\s@]+@[^\s@]+\.[^\s@]+$"#, value)
    }

    static func isDate(_ value: String) -> Bool {
        guard matches(CredflareSpec.Requirements.questionsDatePattern, value), value.allSatisfy({ $0.isASCII }) else { return false }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == parts[0] && back.month == parts[1] && back.day == parts[2]
    }

    static let countryCodes: Set<String> = Set(Locale.Region.isoRegions.map(\.identifier).filter { matches(CredflareSpec.Requirements.questionsCountryPattern, $0) })

    static func isCountry(_ value: String) -> Bool { countryCodes.contains(value) }

    public static func displayText(_ answer: JSONValue?) -> String {
        switch answer {
        case .string(let text)?: return text
        case .number(let value)?: return Conditions.text(.number(value))
        default: return ""
        }
    }

    static func number(_ answer: JSONValue) -> Decimal? {
        switch answer {
        case .number(let value): return value.isFinite ? Decimal(value) : nil
        case .string(let text):
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard matches(CredflareSpec.Requirements.questionsNumberPattern, trimmed), trimmed.allSatisfy({ $0.isASCII }) else { return nil }
            return Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX"))
        default: return nil
        }
    }

    static func problem(_ question: Question, _ answer: JSONValue) -> String? {
        typealias Key = CredflareSpec.CopyKey
        if question.type == "consent" {
            if case .null = answer { return question.required ? Key.questionsConsentRequired : nil }
            guard let value = answer.boolValue else { return Key.questionsConsentRequired }
            return question.required && !value ? Key.questionsConsentRequired : nil
        }
        if isEmpty(question, answer) { return question.required ? Key.questionsRequired : nil }
        let text = answer.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch question.type {
        case "text", "textarea":
            guard let text else { return Key.questionsRequired }
            return text.count > CredflareSpec.Requirements.questionsTextMaxLength ? Key.questionsTextTooLong : nil
        case "number":
            guard let value = number(answer) else { return Key.questionsInvalidNumber }
            if let min = question.min, value < Decimal(min) { return Key.questionsNumberMin }
            if let max = question.max, value > Decimal(max) { return Key.questionsNumberMax }
            return nil
        case "date": return text.map(isDate) == true ? nil : Key.questionsInvalidDate
        case "email": return text.map(isEmail) == true ? nil : Key.questionsInvalidEmail
        case "phone", "tel": return text.map { matches(CredflareSpec.Requirements.questionsPhonePattern, $0) } == true ? nil : Key.questionsInvalidPhone
        case "select", "single_select": return text.map(question.options.contains) == true ? nil : Key.questionsChooseOne
        case "multi_select":
            guard let list = answer.arrayValue else { return Key.questionsRequired }
            let picked = list.compactMap(\.stringValue)
            return picked.count == list.count && Set(picked).count == picked.count && picked.allSatisfy(question.options.contains) ? nil : Key.questionsRequired
        case "country": return text.map(isCountry) == true ? nil : Key.questionsChooseCountry
        case "founders":
            guard case .object = answer, answer["includes_applicant"].map({ $0.boolValue != nil }) ?? true,
                  answer["names"].map({ $0.arrayValue?.allSatisfy { $0.stringValue != nil } == true }) ?? true else { return Key.questionsRequired }
            return nil
        default: return nil
        }
    }

    public static func message(_ key: String, question: Question) -> String {
        func format(_ value: Double?) -> String { value.map { Conditions.text(.number($0)) } ?? "" }
        return CredflareCopy.text(key, ["min": format(question.min), "max": format(question.max)])
    }
}
