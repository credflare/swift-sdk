import Combine
import Foundation

@MainActor
final class QuestionsModel: ObservableObject {
    enum Stage: Equatable { case form, sending, rejected(Rejection) }
    @Published var stage: Stage = .form
    @Published var answers: [String: JSONValue] = [:]
    @Published var errors: [String: String] = [:]
    @Published var problem: String?
    let questionnaire: Questionnaire
    let verifier: String
    var help = HelpContact()
    private let client: VerificationSession
    private let onDone: () -> Void
    private var submitKey = UUID()

    init(client: VerificationSession, questionnaire: Questionnaire, verifier: String, onDone: @escaping () -> Void) {
        self.client = client; self.questionnaire = questionnaire; self.verifier = verifier; self.onDone = onDone
    }

    var visible: [Question] { questionnaire.visibleQuestions(answers) }

    func set(_ key: String, _ value: JSONValue) {
        answers[key] = value; errors[key] = nil; submitKey = UUID()
    }

    func send() async {
        errors = questionnaire.errors(answers)
        guard errors.isEmpty else { return }
        problem = nil; stage = .sending
        do {
            _ = try await client.submitAnswers(questionnaire.fields(answers), key: submitKey)
            onDone()
        } catch let error as CredflareError {
            if case .api(422, _, _) = error { stage = .rejected(Rejection(error, requester: verifier, contact: help)) }
            else { problem = CredflareCopy.text(CredflareSpec.CopyKey.errorsSendAnswersFailed); stage = .form }
        } catch {
            problem = CredflareCopy.text(CredflareSpec.CopyKey.errorsSendAnswersFailed); stage = .form
        }
    }

    static let countries: [(code: String, name: String)] = Locale.Region.isoRegions
        .map(\.identifier)
        .filter { $0.range(of: CredflareSpec.Requirements.questionsCountryPattern, options: .regularExpression) != nil }
        .compactMap { code in Locale.current.localizedString(forRegionCode: code).map { (code, $0) } }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
}
