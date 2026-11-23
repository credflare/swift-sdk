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

    func testFoundersAreAskedAndSentInTheContractShape() throws {
        let founders = Question(try question("employer", as: "founders"))
        XCTAssertTrue(founders.isSupported)
        let questionnaire = Questionnaire(questions: [Question(try question("employment")), founders])
        XCTAssertEqual(questionnaire.errors(["employment": .string("Employed")])["employer"], Key.questionsRequired)
        let empty: JSONValue = .object(["includes_applicant": .bool(false), "names": .array([.string("  ")])])
        XCTAssertEqual(questionnaire.errors(["employment": .string("Employed"), "employer": empty])["employer"], Key.questionsRequired)
        let answer: JSONValue = .object(["includes_applicant": .bool(true), "names": .array([.string(" Ada Obi "), .string("")])])
        let answers: [String: JSONValue] = ["employment": .string("Employed"), "employer": answer]
        XCTAssertEqual(questionnaire.errors(answers), [:])
        let sent = try XCTUnwrap(questionnaire.fields(answers)["employer"])
        XCTAssertEqual(sent["includes_applicant"]?.boolValue, true)
        XCTAssertEqual(sent["names"]?.arrayValue?.compactMap(\.stringValue), ["Ada Obi"])
        let onlyMe: JSONValue = .object(["includes_applicant": .bool(true), "names": .array([])])
        XCTAssertEqual(questionnaire.fields(["employment": .string("Employed"), "employer": onlyMe])["employer"]?["names"]?.arrayValue?.count, 0)
        XCTAssertEqual(questionnaire.errors(["employment": .string("Employed"), "employer": .string("Ada")])["employer"], Key.questionsRequired)
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

    func earlierSession(answer: String) throws -> SessionInfo {
        let raw = try String(decoding: Data(contentsOf: Bundle.module.url(forResource: "questionnaire-earlier-answers-session", withExtension: "json", subdirectory: "Fixtures")!), as: UTF8.self)
        let edited = raw
            .replacingOccurrences(of: #""type": "text",\s*"required": true"#, with: #""type": "number", "required": false"#, options: .regularExpression)
            .replacingOccurrences(of: #""employment": "Employed""#, with: #""employment": "Employed", "employer": \#(answer)"#)
        struct Payload: Decodable { let data: SessionInfo }
        return try JSONDecoder().decode(Payload.self, from: Data(edited.utf8)).data
    }

    func testEarlierNumbersKeepTheirDigitsAndShowInTheField() throws {
        let questionnaire = try XCTUnwrap(earlierSession(answer: "9007199254740993").profile?.questionnaire)
        XCTAssertEqual(questionnaire.questions.first?.type, "number")
        let start = questionnaire.startingAnswers
        XCTAssertEqual(Questionnaire.displayText(start["employer"]), "9007199254740993")
        XCTAssertEqual(questionnaire.fields(start)["employer"]?.stringValue, "9007199254740993")
        XCTAssertNil(questionnaire.fields(start)["employment"])
        XCTAssertEqual(Questionnaire.displayText(.number(4500)), "4500")
    }

    func testClearingAnAnswerAskedAgainSendsNull() throws {
        let questionnaire = try XCTUnwrap(earlierSession(answer: "4500").profile?.questionnaire)
        var answers = questionnaire.startingAnswers
        answers["employer"] = .string("  ")
        XCTAssertEqual(questionnaire.errors(answers), [:])
        let fields = questionnaire.fields(answers)
        XCTAssertEqual(Array(fields.keys), ["employer"])
        guard case .null? = fields["employer"] else { return XCTFail("Expected null") }
        let body = String(decoding: try JSONEncoder().encode(fields), as: UTF8.self)
        XCTAssertEqual(body, #"{"employer":null}"#)
    }

    func testCountriesMustBeAssignedCodes() throws {
        let questionnaire = Questionnaire(questions: [Question(try question("country"))])
        XCTAssertNil(questionnaire.errors(["country": .string("DE")])["country"])
        XCTAssertEqual(questionnaire.errors(["country": .string("ZZ")])["country"], Key.questionsChooseCountry)
    }
}

extension Question {
    var withoutShowIf: Question {
        Question(.object(["key": .string(key), "label": .string(label), "type": .string(type), "required": .bool(required),
                          "min": min.map(JSONValue.number) ?? .null, "max": max.map(JSONValue.number) ?? .null]))
    }
}
