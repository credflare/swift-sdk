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
