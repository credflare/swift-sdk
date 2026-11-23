import XCTest
@testable import CredflareSDK

final class QuestionnaireRuleTests: XCTestCase {
    typealias Key = CredflareSpec.CopyKey

    func schema() throws -> [JSONValue] {
        let raw = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: Bundle.module.url(forResource: "questionnaire-session", withExtension: "json", subdirectory: "Fixtures")!))
        return try XCTUnwrap(raw["data"]?["profile"]?["form_schema"]?.arrayValue)
    }

    func question(_ key: String, as type: String? = nil, required: Bool? = nil) throws -> JSONValue {
        guard case .object(var fields)? = try schema().first(where: { $0["key"]?.stringValue == key }) else { throw XCTSkip("No \(key) question in the fixture") }
        if let type { fields["type"] = .string(type) }
        if let required { fields["required"] = .bool(required) }
        return .object(fields)
    }

    func testDatesWithNonASCIIDigitsAreInvalidInsteadOfCrashing() throws {
        let questionnaire = Questionnaire(questions: [Question(try question("birth_date"))])
        for answer in ["٢٠٢٦-١١-٢٣", "２０２６-１１-２３", "१९९०-०५-१७"] {
            XCTAssertFalse(Questionnaire.isDate(answer), answer)
            XCTAssertEqual(questionnaire.errors(["birth_date": .string(answer)])["birth_date"], Key.questionsInvalidDate, answer)
        }
        XCTAssertNil(questionnaire.errors(["birth_date": .string("2026-11-23")])["birth_date"])
    }

    func testNumbersAreSentAsTheExactTextTyped() throws {
        let questionnaire = Questionnaire(questions: [Question(try question("income", required: true)).withoutShowIf])
        let fields = questionnaire.fields(["income": .string(" 9007199254740993 ")])
        guard case .string(let text)? = fields["income"] else { return XCTFail("Expected the typed text") }
        XCTAssertEqual(text, "9007199254740993")
        let body = String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)
        XCTAssertTrue(body.contains("9007199254740993"), body)
        XCTAssertEqual(questionnaire.errors(["income": .string("10000000.0000000001")])["income"], Key.questionsNumberMax)
        XCTAssertNil(questionnaire.errors(["income": .string("10000000.0")])["income"])
        XCTAssertEqual(questionnaire.errors(["income": .string("١٢")])["income"], Key.questionsInvalidNumber)
        if case .number(let value)? = questionnaire.fields(["income": .number(4500)])["income"] { XCTAssertEqual(value, 4500) } else { XCTFail("Expected a number") }
    }

    func testShowIfSeesTheTrimmedValueThatIsSubmitted() throws {
        let questionnaire = try XCTUnwrap(Questionnaire(.array(schema())))
        let answers: [String: JSONValue] = ["employment": .string("Employed "), "country": .string("DE"), "birth_date": .string("1990-05-17"), "terms": .bool(true)]
        XCTAssertTrue(questionnaire.visibleQuestions(answers).map(\.key).contains("employer"))
        XCTAssertEqual(questionnaire.errors(answers)["employer"], Key.questionsRequired)
        XCTAssertEqual(questionnaire.fields(answers)["employment"]?.stringValue, "Employed")
        let empty: [String: JSONValue] = ["sources": .array([])]
        XCTAssertNil(questionnaire.fields(empty)["sources"])
        XCTAssertFalse(questionnaire.visibleQuestions(empty).map(\.key).contains("sources_other"))
    }

    func testWrongValueTypesAreRejected() throws {
        let sources = Questionnaire(questions: [Question(try question("sources", required: true))])
        XCTAssertEqual(sources.errors(["sources": .string("Salary")])["sources"], Key.questionsRequired)
        XCTAssertEqual(sources.errors(["sources": .array([.number(1)])])["sources"], Key.questionsRequired)
        XCTAssertNil(sources.errors(["sources": .array([.string("Salary")])])["sources"])
        let terms = Questionnaire(questions: [Question(try question("terms", required: false))])
        XCTAssertEqual(terms.errors(["terms": .string("yes")])["terms"], Key.questionsConsentRequired)
        XCTAssertNil(terms.errors(["terms": .bool(false)])["terms"])
        XCTAssertNil(terms.errors([:])["terms"])
        let email = Questionnaire(questions: [Question(try question("contact_email"))])
        XCTAssertEqual(email.errors(["contact_email": .number(5)])["contact_email"], Key.questionsInvalidEmail)
        let employer = Questionnaire(questions: [Question(try question("employer")).withoutShowIf])
        XCTAssertEqual(employer.errors(["employer": .bool(true)])["employer"], Key.questionsRequired)
    }

    func testOnlyVisibleUnsupportedQuestionsSendTheFormToTheHost() throws {
        let hiddenUnknown = Question(try question("employer", as: "signature"))
        let questionnaire = Questionnaire(questions: [Question(try question("employment")), hiddenUnknown])
        XCTAssertFalse(hiddenUnknown.isSupported)
        XCTAssertTrue(questionnaire.isSupported)
        XCTAssertFalse(Questionnaire(questions: [Question(try question("country", as: "signature"))]).isSupported)
    }

    func testASessionWithoutAProfileGoesToTheReceipt() throws {
        let raw = try Data(contentsOf: Bundle.module.url(forResource: "session", withExtension: "json", subdirectory: "Fixtures")!)
        var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        var data = try XCTUnwrap(payload["data"] as? [String: Any])
        data["profile"] = NSNull()
        payload["data"] = data
        struct Payload: Decodable { let data: SessionInfo }
        let info = try JSONDecoder().decode(Payload.self, from: JSONSerialization.data(withJSONObject: payload)).data
        XCTAssertNil(info.profile)
        guard case .receipt(let hostSteps) = info.nextStep else { return XCTFail("Expected the receipt") }
        XCTAssertFalse(hostSteps)
    }
}

extension Question {
    var withoutShowIf: Question {
        Question(.object(["key": .string(key), "label": .string(label), "type": .string(type), "required": .bool(required),
                          "min": min.map(JSONValue.number) ?? .null, "max": max.map(JSONValue.number) ?? .null]))
    }
}
