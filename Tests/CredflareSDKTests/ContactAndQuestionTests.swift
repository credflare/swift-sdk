import XCTest
@testable import CredflareSDK

extension ClientTests {
    func data(_ name: String) throws -> [String: Any] {
        (try JSONSerialization.jsonObject(with: fixture(name)) as! [String: Any])["data"] as! [String: Any]
    }

    func testContactCodesAreRequestedAndConfirmedOverHTTP() async throws {
        let client = VerificationSession(try descriptor("capture"))
        let email = try await client.requestCode(.email, to: "  Jane.Doe@example.test ")
        let issued = try data("email-code-request")
        XCTAssertEqual(email.destination, issued["destination"] as? String)
        XCTAssertEqual(email.sendsRemaining, issued["sends_remaining"] as? Int)
        let resend = try XCTUnwrap(email.resendDate)
        XCTAssertEqual(email.secondsUntilResend(now: resend.addingTimeInterval(-42.2)), 43)
        XCTAssertEqual(email.secondsUntilResend(now: resend.addingTimeInterval(5)), 0)
        let phone = try await client.requestCode(.phone, to: "+237 (650) 000-001")
        XCTAssertEqual(phone.channel, "phone")
        XCTAssertEqual(phone.destination, try data("phone-code-request")["destination"] as? String)
        let id = try await client.confirmCode(.phone, code: "123456")
        XCTAssertEqual(id, try data("email-code-confirm")["id"] as? Int)

        let emails = try await requests("/email-codes")
        XCTAssertEqual(try json(XCTUnwrap(emails.first)) as? [String: String], ["email": "Jane.Doe@example.test"])
        let phones = try await requests("/phone-codes")
        XCTAssertEqual(try json(XCTUnwrap(phones.first)) as? [String: String], ["phone": "+237650000001"])
        let confirms = try await requests("/phone-codes/confirm")
        XCTAssertEqual(try json(XCTUnwrap(confirms.first)) as? [String: String], ["code": "123456"])
        XCTAssertEqual(confirms.first?["method"] as? String, "POST")
    }

    func testContactDestinationsAndCodesAreCheckedBeforeSending() {
        XCTAssertTrue(ContactChannel.email.isValid("jane@example.test"))
        XCTAssertFalse(ContactChannel.email.isValid("jane@"))
        XCTAssertFalse(ContactChannel.email.isValid(String(repeating: "a", count: 250) + "@x.io"))
        XCTAssertTrue(ContactChannel.phone.isValid("+44 7700 900123"))
        XCTAssertTrue(ContactChannel.phone.isValid("+237.650.000.001"))
        XCTAssertFalse(ContactChannel.phone.isValid("07700 900123"))
        XCTAssertFalse(ContactChannel.phone.isValid("+0123456789"))
        XCTAssertEqual(ContactChannel.phone.normalized(" +44 (7700) 900-123 "), "+447700900123")
        XCTAssertEqual(ContactChannel(verificationType: "phone_verification"), .phone)
        XCTAssertEqual(ContactChannel(verificationType: "email_verification"), .email)
        XCTAssertNil(ContactChannel(verificationType: "facial_verification"))
        XCTAssertTrue(ContactChannel.isCode("012345"))
        XCTAssertFalse(ContactChannel.isCode("12345"))
        XCTAssertFalse(ContactChannel.isCode("12345a"))
    }

    func testEveryContactRejectionShowsItsSpecScreen() async throws {
        let directory = Bundle.module.url(forResource: "rejections", withExtension: nil, subdirectory: "Fixtures")!
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path).map { ($0 as NSString).deletingPathExtension }.filter { $0.hasPrefix("email.") || $0.hasPrefix("phone.") }.sorted()
        XCTAssertEqual(names.count, 14)
        let actions: [String: RejectionAction] = [
            "not_configured": .leave, "resend_too_soon": .wait, "send_limit": .leave, "code_missing": .newCode,
            "code_expired": .newCode, "code_invalid": .reenterCode, "too_many_attempts": .newCode,
        ]
        for name in names {
            let channel = ContactChannel(rawValue: String(name.split(separator: ".")[0]))!
            let reason = String(name.split(separator: ".")[1])
            let client = VerificationSession(try descriptor("reject:\(name)"))
            do {
                if ["not_configured", "resend_too_soon", "send_limit"].contains(reason) { _ = try await client.requestCode(channel, to: channel == .email ? "jane@example.test" : "+237650000001") }
                else { _ = try await client.confirmCode(channel, code: "000000") }
                XCTFail("\(name) was not rejected")
            } catch let error as CredflareError {
                XCTAssertEqual(error.code?.rawValue, name)
                let screen = Rejection(error, requester: "Acme Bank")
                let entry = try XCTUnwrap(CredflareSpec.Rejection.codes[name])
                XCTAssertEqual(screen.action, actions[reason], name)
                XCTAssertEqual(screen.action.rawValue, entry.action, name)
                XCTAssertEqual(screen.title, CredflareCopy.text(entry.title), name)
                XCTAssertEqual(screen.message, CredflareCopy.text(entry.message, ["verifier": "Acme Bank"]), name)
                XCTAssertFalse(screen.message.contains("{"), name)
                XCTAssertEqual(screen.requestedBy, "Requested by Acme Bank.")
                XCTAssertEqual(screen.help, "If you need help, contact Acme Bank.")
            }
        }
        do { _ = try await VerificationSession(try descriptor("reject:phone.not_configured")).requestCode(.phone, to: "+237650000001") }
        catch let error as CredflareError {
            let screen = Rejection(error, requester: nil)
            XCTAssertEqual(screen.message, "Confirming a phone number is not available for this request yet. Contact your verifier.")
            XCTAssertEqual(screen.actionLabel, "Close")
            XCTAssertEqual(screen.help, "If you need help, contact your verifier.")
        }
    }

    func testLeaveRejectionsEndTheFlowForTheHostWithTheirCode() async throws {
        for name in ["email.not_configured", "email.send_limit", "phone.not_configured", "phone.send_limit"] {
            let channel = ContactChannel(rawValue: String(name.split(separator: ".")[0]))!
            do { _ = try await VerificationSession(try descriptor("reject:\(name)")).requestCode(channel, to: channel == .email ? "jane@example.test" : "+237650000001"); XCTFail("\(name) was not rejected") }
            catch let error as CredflareError {
                let screen = Rejection(error, requester: nil)
                XCTAssertEqual(screen.action, .leave, name)
                XCTAssertEqual(screen.leaveResult, .hostActionRequired(code: RejectionCode(rawValue: name)), name)
            }
        }
        for name in ["phone.code_invalid", "phone.resend_too_soon", "email.code_expired"] {
            XCTAssertNil(Rejection(.api(422, "", code: RejectionCode(rawValue: name)), requester: nil).leaveResult, name)
        }
        XCTAssertNil(Rejection(.api(422, "Server said no.", code: nil), requester: nil).leaveResult)
    }

    func testResendRejectionCarriesItsOwnResendTime() async throws {
        for channel in ContactChannel.allCases {
            let raw = try JSONSerialization.jsonObject(with: fixture("rejections/\(channel.rawValue).resend_too_soon")) as! [String: Any]
            do { _ = try await VerificationSession(try descriptor("reject:\(channel.rawValue).resend_too_soon")).requestCode(channel, to: channel == .email ? "jane@example.test" : "+237650000001"); XCTFail("Expected rejection") }
            catch let error as CredflareError {
                let screen = Rejection(error, requester: nil)
                XCTAssertEqual(screen.action, .wait)
                XCTAssertEqual(screen.resendAvailableAt, ISO8601.parse(raw["resend_available_at"] as! String))
                XCTAssertNotNil(screen.resendAvailableAt)
            }
        }
        do { _ = try await VerificationSession(try descriptor("reject:email.code_invalid")).confirmCode(.email, code: "000000") }
        catch let error as CredflareError { XCTAssertNil(Rejection(error, requester: nil).resendAvailableAt) }
    }

    func testHelpLineUsesTheRequesterContact() throws {
        let requester = try XCTUnwrap(SessionInfo.decodeFixture("help-contact-session").requester)
        let error = CredflareError.api(422, "", code: .phoneSendLimit)
        let withEmail = Rejection(error, requester: requester.name, contact: requester.help)
        XCTAssertEqual(withEmail.help, "If you need help, contact \(requester.name) at \(requester.helpEmail!).")
        XCTAssertEqual(withEmail.helpLink?.absoluteString, "mailto:\(requester.helpEmail!)")
        let withURL = Rejection(error, requester: requester.name, contact: HelpContact(email: nil, url: requester.helpURL))
        XCTAssertEqual(withURL.help, "If you need help, visit \(requester.helpURL!).")
        XCTAssertEqual(withURL.helpLink?.absoluteString, requester.helpURL)
        let unsafe = Rejection(error, requester: requester.name, contact: HelpContact(email: " ", url: "javascript:alert(1)"))
        XCTAssertEqual(unsafe.help, "If you need help, contact \(requester.name).")
        XCTAssertNil(unsafe.helpLink)
        let none = try XCTUnwrap(SessionInfo.decodeFixture("questionnaire-session").requester)
        XCTAssertEqual(Rejection(error, requester: none.name, contact: none.help).help, "If you need help, contact \(none.name).")
    }

    func testValidationErrorWithoutACodeShowsTheServerMessageWithRetry() async throws {
        let expected = (try JSONSerialization.jsonObject(with: fixture("questionnaire-hidden-answer")) as! [String: Any])["message"] as! String
        do { _ = try await VerificationSession(try descriptor("hidden-answer")).submitAnswers(["employer": .string("Acme")], key: UUID()); XCTFail("Expected rejection") }
        catch let error as CredflareError {
            XCTAssertNil(error.code)
            let screen = Rejection(error, requester: "Acme Bank")
            XCTAssertNil(screen.title)
            XCTAssertEqual(screen.message, expected)
            XCTAssertEqual(screen.action, .retry)
            XCTAssertEqual(screen.actionLabel, "Try again")
        }
        let unknown = Rejection(.api(422, "Server said no.", code: RejectionCode(rawValue: "phone.future_rule")), requester: nil)
        XCTAssertNil(unknown.title)
        XCTAssertEqual(unknown.message, "Server said no.")
        XCTAssertEqual(unknown.action, .retry)
    }

    func testQuestionnaireAnswersAreCheckedAndOnlyShownAnswersAreSent() async throws {
        let client = VerificationSession(try descriptor("questionnaire"))
        let info = try await client.get()
        XCTAssertEqual(info.status, "pending")
        guard case .questions(let questionnaire) = info.nextStep else { return XCTFail("Expected the questionnaire") }
        XCTAssertTrue(questionnaire.isSupported)
        XCTAssertEqual(questionnaire.errors([:]), [
            "country": CredflareSpec.CopyKey.questionsRequired, "employment": CredflareSpec.CopyKey.questionsRequired,
            "birth_date": CredflareSpec.CopyKey.questionsRequired, "terms": CredflareSpec.CopyKey.questionsConsentRequired,
        ])
        var answers: [String: JSONValue] = [
            "country": .string("DE"), "employment": .string("Employed"), "birth_date": .string("1990-02-30"),
            "income": .string("-5"), "contact_email": .string("jane@"), "contact_phone": .string("call me"),
            "sources": .array([.string("Other")]), "terms": .bool(false),
        ]
        let errors = questionnaire.errors(answers)
        XCTAssertEqual(errors, [
            "employer": CredflareSpec.CopyKey.questionsRequired, "birth_date": CredflareSpec.CopyKey.questionsInvalidDate,
            "income": CredflareSpec.CopyKey.questionsNumberMin, "contact_email": CredflareSpec.CopyKey.questionsInvalidEmail,
            "contact_phone": CredflareSpec.CopyKey.questionsInvalidPhone, "sources_other": CredflareSpec.CopyKey.questionsRequired,
            "terms": CredflareSpec.CopyKey.questionsConsentRequired,
        ])
        let income = try XCTUnwrap(questionnaire.questions.first { $0.key == "income" })
        XCTAssertEqual(Questionnaire.message(CredflareSpec.CopyKey.questionsNumberMin, question: income), "Enter at least 0.")
        XCTAssertEqual(Questionnaire.message(CredflareSpec.CopyKey.questionsNumberMax, question: income), "Enter at most 10000000.")
        XCTAssertEqual(questionnaire.errors(["income": .string("12000000"), "employment": .string("Employed")])["income"], CredflareSpec.CopyKey.questionsNumberMax)
        XCTAssertEqual(questionnaire.errors(["employer": .string(String(repeating: "a", count: 5001)), "employment": .string("Employed")])["employer"], CredflareSpec.CopyKey.questionsTextTooLong)

        answers = [
            "country": .string("DE"), "employment": .string("Student"), "employer": .string("Left over from an earlier choice"),
            "income": .string("4000"), "birth_date": .string("1990-05-17"), "contact_email": .string(""),
            "contact_phone": .string("+237 650 000 001"), "sources": .array([.string("Salary")]), "terms": .bool(true),
        ]
        XCTAssertEqual(questionnaire.errors(answers), [:])
        let key = UUID()
        let id = try await client.submitAnswers(questionnaire.fields(answers), key: key)
        XCTAssertEqual(id, try data("questionnaire-submission")["id"] as? Int)
        let submits = try await requests("/submit")
        let submit = try XCTUnwrap(submits.first)
        XCTAssertEqual(submit["key"] as? String, key.uuidString.lowercased())
        let body = try json(submit)
        XCTAssertEqual(body["type"] as? String, "form_submission")
        let fields = try XCTUnwrap(body["fields"] as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["country", "employment", "birth_date", "contact_phone", "sources", "terms"])
        XCTAssertEqual(fields["employment"] as? String, "Student")
        XCTAssertEqual(fields["sources"] as? [String], ["Salary"])
        XCTAssertEqual(fields["terms"] as? Bool, true)
        XCTAssertNil(fields["employer"])
        XCTAssertNil(fields["income"])
    }

    func testTypedNumbersAreSentAsTheirValidatedText() {
        let questionnaire = Questionnaire(questions: [Question(.object(["key": .string("income"), "label": .string("Income"), "type": .string("number"), "required": .bool(true)]))])
        XCTAssertEqual(questionnaire.fields(["income": .string(" 4500.5 ")])["income"]?.stringValue, "4500.5")
        XCTAssertEqual(questionnaire.fields(["income": .string("4500")])["income"]?.stringValue, "4500")
        XCTAssertEqual(questionnaire.errors(["income": .string("4,500")])["income"], CredflareSpec.CopyKey.questionsInvalidNumber)
    }

    func testRefreshContinuesWithAnAddedRequirementThenShowsTheReceipt() async throws {
        let client = VerificationSession(try descriptor("questionnaire"))
        guard case .questions(let questionnaire) = try await client.get().nextStep else { return XCTFail("Expected the questionnaire") }
        _ = try await client.submitAnswers(questionnaire.fields(["country": .string("DE"), "employment": .string("Retired"), "birth_date": .string("1950-01-01"), "terms": .bool(true)]), key: UUID())
        guard case .next(let added, .check(let requirement)) = await client.refresh() else { return XCTFail("Expected the added requirement") }
        XCTAssertEqual(added.status, "in_progress")
        XCTAssertEqual(requirement.contact, .phone)
        _ = try await client.requestCode(.phone, to: "+237650000001")
        _ = try await client.confirmCode(.phone, code: "123456")
        guard case .next(_, .receipt(let hostSteps)) = await client.refresh() else { return XCTFail("Expected the receipt") }
        XCTAssertFalse(hostSteps)
        let all = try await requests("")
        XCTAssertEqual(all.filter { $0["method"] as? String == "GET" }.count, 3)
    }

    func testFailedRefreshShowsTheRefreshErrorInsteadOfTheReceipt() async throws {
        let client = VerificationSession(try descriptor("refresh-fail"))
        guard case .questions(let questionnaire) = try await client.get().nextStep else { return XCTFail("Expected the questionnaire") }
        _ = try await client.submitAnswers(questionnaire.fields(["country": .string("CM"), "employment": .string("Retired"), "birth_date": .string("1950-01-01"), "terms": .bool(true)]), key: UUID())
        guard case .failed(let message) = await client.refresh() else { return XCTFail("Expected a failed refresh") }
        XCTAssertEqual(message, CredflareCopy.text(CredflareSpec.CopyKey.errorsRefreshFailed))
    }

    func testACaseClosedBySubmittingGoesToTheReceipt() async throws {
        let client = VerificationSession(try descriptor("closes"))
        guard case .questions(let questionnaire) = try await client.get().nextStep else { return XCTFail("Expected the questionnaire") }
        _ = try await client.submitAnswers(questionnaire.fields(["country": .string("CM"), "employment": .string("Retired"), "birth_date": .string("1950-01-01"), "terms": .bool(true)]), key: UUID())
        guard case .closed = await client.refresh() else { return XCTFail("Expected a closed case") }
    }

    func testClosedOrEmptySessionsGoToTheReceipt() throws {
        let added = try SessionInfo.decodeFixture("requirement-added-session")
        guard case .check(let requirement) = added.nextStep else { return XCTFail("Expected the phone step") }
        XCTAssertEqual(requirement.type, "phone_verification")
        XCTAssertTrue(requirement.isHandledInSDK)
        XCTAssertFalse(added.profile!.needsHostSteps)
        let questionnaire = try SessionInfo.decodeFixture("questionnaire-session")
        XCTAssertTrue(questionnaire.isOpen)
        XCTAssertTrue(questionnaire.hasOutstanding)
        XCTAssertEqual(questionnaire.profile?.nextStepsCopyKey, CredflareSpec.CopyKey.documentsHostStepsNext)
    }

    @available(*, deprecated)
    func testEarlierPublicAPIStillCompiles() async throws {
        do { _ = try await VerificationSession(try descriptor("reject:phone.send_limit")).requestCode(.phone, to: "+237650000001"); XCTFail("Expected rejection") }
        catch CredflareError.api(let status, let message, let code) {
            XCTAssertEqual(status, 422)
            XCTAssertFalse(message.isEmpty)
            XCTAssertEqual(code, .phoneSendLimit)
        }
        let result: VerificationResult = .hostActionRequired
        XCTAssertEqual(result, .hostActionRequired(code: nil))
        switch VerificationResult.hostActionRequired(code: .phoneSendLimit) {
        case .submitted, .cancelled: XCTFail("Expected host action")
        case .hostActionRequired: break
        }
        XCTAssertTrue(LivenessRejection.restartCodes.contains(.livenessChallengeExpired))
        XCTAssertEqual(LivenessRejection.message(for: .api(422, "", code: .livenessChallengeExpired)), CredflareCopy.text(CredflareSpec.CopyKey.livenessExpired))
        XCTAssertEqual(LocationCopy.rejection(.api(422, "Server said no.", code: nil), reference: nil), "Server said no.")
    }
}
