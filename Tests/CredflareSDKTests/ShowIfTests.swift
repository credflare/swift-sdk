import XCTest
@testable import CredflareSDK

final class ShowIfTests: XCTestCase {
    func fixture(_ name: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!))
    }

    func testEveryBackendConditionCaseMatches() throws {
        let cases = try XCTUnwrap(fixture("show-if-cases")["conditions"]?.arrayValue)
        XCTAssertEqual(cases.count, 55)
        for item in cases {
            let name = item["name"]?.stringValue ?? ""
            let condition = ShowIfCondition(try XCTUnwrap(item["condition"], name))
            XCTAssertEqual(Conditions.test(condition, form: item["form"] ?? .null), item["expect"]?.boolValue, name)
        }
        let used = Set(cases.compactMap { $0["condition"]?["op"]?.stringValue })
        XCTAssertEqual(used, Set(CredflareSpec.Requirements.showIfOperators))
    }

    func testEveryBackendShowIfCaseMatches() throws {
        let cases = try XCTUnwrap(fixture("show-if-cases")["show_if"]?.arrayValue)
        XCTAssertEqual(cases.count, 7)
        for item in cases {
            let name = item["name"]?.stringValue ?? ""
            XCTAssertEqual(Conditions.visible(ShowIf(item["show_if"]), form: item["form"] ?? .null), item["expect"]?.boolValue, name)
        }
    }

    func testUnicodeAndOverflowInputsMatchTheReferenceEvaluator() {
        let cases: [(String, String, JSONValue, String, Bool)] = [
            ("regex", "^\\d+$", .string("^\\d+$"), "١٢", false),
            ("regex", "ascii digits", .string("^\\d+$"), "12", true),
            ("regex", "unicode word", .string("^\\w+$"), "é", false),
            ("regex", "not digit", .string("^\\D$"), "١", true),
            ("regex", "class digit", .string("^[\\d]+$"), "١", false),
            ("regex", "word boundary", .string("\\bb"), "éb", true),
            ("regex", "escaped backslash", .string("\\\\d"), "\\d", true),
            ("regex", "unicode space", .string("^\\s$"), "\u{00A0}", true),
            ("equals", "composed", .string("e\u{0301}"), "\u{00E9}", false),
            ("in", "composed", .array([.string("e\u{0301}")]), "\u{00E9}", false),
            ("contains", "composed", .string("e\u{0301}"), "caf\u{00E9}", false),
            ("gte", "infinity", .string("1e400"), "1e400", false),
            ("equals", "infinity", .string("1e400"), "2e400", true),
            ("gt", "infinity", .string("5"), "1e400", true),
            ("lt", "negative infinity", .string("5"), "-1e400", true),
            ("fuzzy_match", "composed", .object(["text": .string("cafe\u{0301}"), "min_score": .number(100)]), "caf\u{00E9}", false),
            ("equals", "trailing dot", .number(5), "5.", true),
            ("equals", "leading dot", .number(0.5), ".5", true),
        ]
        for (op, name, value, answer, expected) in cases {
            let condition = ShowIfCondition(.object(["path": .string("form.a"), "op": .string(op), "value": value]))
            XCTAssertEqual(Conditions.test(condition, form: .object(["a": .string(answer)])), expected, "\(op) \(name)")
        }
    }

    func testFuzzySimilarityIsFastAndMatchesTheReference() {
        XCTAssertEqual(Conditions.similarity("abcab", "cabab"), 60)
        XCTAssertEqual(Conditions.similarity("Hello World", "Helo Wrld"), 90)
        let long = String(repeating: "a", count: 5000)
        let start = Date()
        XCTAssertEqual(Conditions.similarity(long, long), 100)
        XCTAssertLessThan(Date().timeIntervalSince(start), 5)
    }

    func testQuestionnaireShowsOnlyQuestionsWhoseConditionsHold() throws {
        let questionnaire = try XCTUnwrap(SessionInfo.decodeFixture("questionnaire-session").profile?.questionnaire)
        func shown(_ answers: [String: JSONValue]) -> [String] { questionnaire.visibleQuestions(answers).map(\.key) }
        XCTAssertEqual(shown([:]), ["country", "employment", "birth_date", "contact_email", "contact_phone", "sources", "terms"])
        XCTAssertFalse(shown(["employment": .string("Student")]).contains("employer"))
        XCTAssertTrue(shown(["employment": .string("Employed")]).contains("employer"))
        XCTAssertTrue(shown(["employment": .string("Self employed")]).contains("income"))
        XCTAssertFalse(shown(["employment": .string("Self employed")]).contains("employer"))
        XCTAssertTrue(shown(["sources": .array([.string("Salary"), .string("Other")])]).contains("sources_other"))
    }

    func testFuzzySimilarityCountsUTF8Bytes() {
        XCTAssertEqual(Conditions.similarity("", ""), 0)
        XCTAssertEqual(Conditions.similarity("abc", "abc"), 100)
        XCTAssertEqual(Conditions.similarity("jane do", "jane doe"), 2.0 * 7 * 100 / 15, accuracy: 0.0001)
        XCTAssertEqual(Conditions.similarity("é", "e"), 0)
    }
}

extension SessionInfo {
    static func decodeFixture(_ name: String) throws -> SessionInfo {
        struct Payload: Decodable { let data: SessionInfo }
        return try JSONDecoder().decode(Payload.self, from: Data(contentsOf: Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!)).data
    }
}
