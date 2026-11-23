#if canImport(UIKit)
import SwiftUI

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

struct QuestionsView: View {
    @Environment(\.colorScheme) private var scheme
    @ObservedObject var model: QuestionsModel

    var body: some View {
        let theme = CredflareTheme(scheme)
        VStack(spacing: CredflareTheme.gap) {
            switch model.stage {
            case .form:
                TitleText(CredflareCopy.text(CredflareSpec.CopyKey.questionsTitle))
                ThemedText(CredflareCopy.text(CredflareSpec.CopyKey.questionsBody, ["verifier": model.verifier]), tone: \.muted)
                ForEach(model.visible) { question in
                    VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingXs)) {
                        if question.type != "consent" {
                            ThemedText(question.required ? question.label : question.label + " (" + CredflareCopy.text(CredflareSpec.CopyKey.questionsOptional) + ")", style: CredflareSpec.Tokens.typeLabel)
                        }
                        field(question, theme: theme)
                        if let key = model.errors[question.key] {
                            Text(Questionnaire.message(key, question: question)).specText(CredflareSpec.Tokens.typeSmall).foregroundStyle(theme.error)
                        }
                    }
                    .padding(.vertical, CGFloat(CredflareSpec.Tokens.spacingXs))
                    .accessibilityElement(children: .contain)
                }
                if let problem = model.problem { ErrorBox(message: problem) }
                PrimaryButton(CredflareCopy.text(CredflareSpec.CopyKey.questionsSend)) { Task { await model.send() } }
            case .sending:
                LoadingBlock(label: CredflareCopy.text(CredflareSpec.CopyKey.questionsSending))
            case .rejected(let rejection):
                RejectionPanel(rejection: rejection, fallbackTitle: CredflareCopy.text(CredflareSpec.CopyKey.questionsTitle)) { model.stage = .form }
            }
        }
    }

    private func string(_ key: String) -> Binding<String> {
        Binding(get: { model.answers[key]?.stringValue ?? "" }, set: { model.set(key, .string($0)) })
    }

    @ViewBuilder private func field(_ question: Question, theme: CredflareTheme) -> some View {
        let invalid = model.errors[question.key] != nil
        switch question.type {
        case "textarea":
            InputField(placeholder: "", text: string(question.key), invalid: invalid, multiline: true)
        case "number":
            InputField(placeholder: "", text: string(question.key), keyboard: .decimalPad, invalid: invalid)
        case "email":
            InputField(placeholder: CredflareCopy.text(CredflareSpec.CopyKey.emailPlaceholder), text: string(question.key), keyboard: .emailAddress, content: .emailAddress, invalid: invalid)
        case "phone", "tel":
            InputField(placeholder: "", text: string(question.key), keyboard: .phonePad, content: .telephoneNumber, invalid: invalid)
        case "date":
            DatePicker(question.label, selection: Binding(
                get: { model.answers[question.key]?.stringValue.flatMap(Self.dateFormatter.date) ?? Date() },
                set: { model.set(question.key, .string(Self.dateFormatter.string(from: $0))) }
            ), displayedComponents: .date)
            .labelsHidden().datePickerStyle(.compact).frame(maxWidth: .infinity)
            .opacity(model.answers[question.key] == nil ? 0.6 : 1)
        case "select", "single_select":
            choice(question, placeholder: CredflareSpec.CopyKey.questionsChooseOne, options: question.options.map { ($0, $0) }, theme: theme)
        case "country":
            choice(question, placeholder: CredflareSpec.CopyKey.questionsChooseCountry, options: QuestionsModel.countries.map { ($0.code, $0.name) }, theme: theme)
        case "multi_select":
            VStack(spacing: CGFloat(CredflareSpec.Tokens.spacingXs)) {
                ThemedText(CredflareCopy.text(CredflareSpec.CopyKey.questionsChooseMany), style: CredflareSpec.Tokens.typeSmall, tone: \.muted)
                ForEach(question.options, id: \.self) { option in
                    let picked = model.answers[question.key]?.arrayValue?.compactMap(\.stringValue) ?? []
                    Toggle(option, isOn: Binding(get: { picked.contains(option) }, set: { on in
                        let next = question.options.filter { $0 == option ? on : picked.contains($0) }
                        model.set(question.key, .array(next.map(JSONValue.string)))
                    }))
                    .toggleStyle(CheckboxStyle())
                }
            }
        case "consent":
            Toggle(question.label, isOn: Binding(get: { model.answers[question.key]?.boolValue ?? false }, set: { model.set(question.key, .bool($0)) }))
                .toggleStyle(CheckboxStyle())
        default:
            InputField(placeholder: "", text: string(question.key), invalid: invalid)
        }
    }

    private func choice(_ question: Question, placeholder: String, options: [(String, String)], theme: CredflareTheme) -> some View {
        let selected = model.answers[question.key]?.stringValue
        return Menu {
            Picker(question.label, selection: Binding(get: { selected ?? "" }, set: { model.set(question.key, .string($0)) })) {
                ForEach(options, id: \.0) { value, name in Text(name).tag(value) }
            }
        } label: {
            HStack {
                Text(options.first { $0.0 == selected }?.1 ?? CredflareCopy.text(placeholder))
                    .foregroundStyle(selected == nil ? theme.muted : theme.ink)
                Spacer(minLength: 0)
                SpecIconView(CredflareSpec.Icons.chevronRight, color: theme.muted, size: 16).rotationEffect(.degrees(90))
            }
            .font(.system(size: CGFloat(CredflareSpec.Tokens.typeBody.size)))
            .padding(.horizontal, CGFloat(CredflareSpec.Tokens.spacingMd))
            .frame(maxWidth: .infinity, minHeight: CGFloat(CredflareSpec.Tokens.sizeButtonHeight))
            .background(theme.soft)
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusMd)))
            .overlay(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusMd)).stroke(model.errors[question.key] != nil ? theme.error : theme.border))
        }
        .accessibilityLabel(question.label)
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct CheckboxStyle: ToggleStyle {
    @Environment(\.colorScheme) private var scheme
    func makeBody(configuration: Configuration) -> some View {
        let theme = CredflareTheme(scheme)
        Button { configuration.isOn.toggle() } label: {
            HStack(alignment: .top, spacing: CGFloat(CredflareSpec.Tokens.spacingSm)) {
                RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusSm))
                    .fill(configuration.isOn ? theme.primary : theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusSm)).stroke(configuration.isOn ? theme.primary : theme.border, lineWidth: 2))
                    .overlay(Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.onPrimary).opacity(configuration.isOn ? 1 : 0))
                    .frame(width: 22, height: 22)
                configuration.label
                    .font(.system(size: CGFloat(CredflareSpec.Tokens.typeBody.size)))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(CGFloat(CredflareSpec.Tokens.spacingMd))
            .background(theme.soft)
            .clipShape(RoundedRectangle(cornerRadius: CGFloat(CredflareSpec.Tokens.radiusMd)))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
    }
}
#endif
