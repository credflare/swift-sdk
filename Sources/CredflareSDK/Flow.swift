import Foundation

public enum VerificationStep: Sendable {
    case documents
    case questions(Questionnaire)
    case check(VerificationRequirement)
    case receipt(hostSteps: Bool)
}

public enum RefreshResult {
    case next(SessionInfo, VerificationStep)
    case closed
    case failed(String)
}

extension SessionInfo {
    public var isOpen: Bool { status.map(CredflareSpec.Requirements.refreshOpenStatuses.contains) ?? true }

    public var hasOutstanding: Bool {
        guard let profile else { return false }
        return !profile.documentRequirements.isEmpty || !profile.verificationRequirements.isEmpty || !(profile.formSchema?.isEmpty ?? true)
    }

    public var nextStep: VerificationStep {
        guard isOpen, hasOutstanding, let profile else { return .receipt(hostSteps: false) }
        if !profile.documentRequirements.isEmpty { return .documents }
        if let questionnaire = profile.questionnaire, questionnaire.isSupported { return .questions(questionnaire) }
        if let requirement = profile.requirements.first(where: \.isHandledInSDK) { return .check(requirement) }
        return .receipt(hostSteps: true)
    }
}

extension VerificationSession {
    public func refresh() async -> RefreshResult {
        do {
            let info = try await get()
            return .next(info, info.nextStep)
        } catch CredflareError.api(409, _, _, _) {
            return .closed
        } catch {
            return .failed(CredflareCopy.text(CredflareSpec.CopyKey.errorsRefreshFailed))
        }
    }
}
