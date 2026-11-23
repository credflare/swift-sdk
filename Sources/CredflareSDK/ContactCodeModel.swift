import Combine
import Foundation

@MainActor
final class ContactCodeModel: ObservableObject {
    enum Stage: Equatable { case destination, sending, code, confirming, rejected(Rejection) }
    @Published var stage: Stage = .destination
    @Published var destination = ""
    @Published var code = ""
    @Published var problem: String?
    @Published var sent: ContactCodeSent? { didSet { resendAt = sent?.resendDate } }
    @Published var resendAt: Date?
    let channel: ContactChannel
    let verifier: String
    var help = HelpContact()
    private let client: VerificationSession
    private let onDone: () -> Void
    private let onLeave: (VerificationResult) -> Void

    init(client: VerificationSession, channel: ContactChannel, verifier: String, onDone: @escaping () -> Void, onLeave: @escaping (VerificationResult) -> Void) {
        self.client = client; self.channel = channel; self.verifier = verifier; self.onDone = onDone; self.onLeave = onLeave
    }

    func text(_ key: String, _ values: [String: String] = [:]) -> String {
        CredflareCopy.text(key, values.merging(["verifier": verifier]) { a, _ in a })
    }

    var titleKey: String { channel == .email ? CredflareSpec.CopyKey.emailTitle : CredflareSpec.CopyKey.phoneTitle }

    func send() async {
        guard canResend else { return }
        guard channel.isValid(destination) else {
            problem = text(channel == .email ? CredflareSpec.CopyKey.emailInvalid : CredflareSpec.CopyKey.phoneInvalid)
            return
        }
        problem = nil; stage = .sending
        do {
            sent = try await client.requestCode(channel, to: destination)
            code = ""; stage = .code
        } catch let error as CredflareError {
            if case .api(422, _, _) = error {
                let rejection = Rejection(error, requester: verifier, contact: help)
                if let next = rejection.resendAvailableAt { resendAt = next }
                stage = .rejected(rejection)
            }
            else { problem = text(CredflareSpec.CopyKey.errorsSendCodeFailed); stage = sent == nil ? .destination : .code }
        } catch {
            problem = text(CredflareSpec.CopyKey.errorsSendCodeFailed); stage = sent == nil ? .destination : .code
        }
    }

    func confirm() async {
        guard ContactChannel.isCode(code) else { return }
        problem = nil; stage = .confirming
        do {
            _ = try await client.confirmCode(channel, code: code)
            onDone()
        } catch let error as CredflareError {
            if case .api(422, _, _) = error { stage = .rejected(Rejection(error, requester: verifier, contact: help)) }
            else { problem = text(CredflareSpec.CopyKey.errorsConfirmCodeFailed); stage = .code }
        } catch {
            problem = text(CredflareSpec.CopyKey.errorsConfirmCodeFailed); stage = .code
        }
    }

    func perform(_ rejection: Rejection) async {
        problem = nil
        if let result = rejection.leaveResult { return onLeave(result) }
        switch rejection.action {
        case .reenterCode: code = ""; stage = .code
        case .newCode: await send()
        case .wait: code = ""; stage = .code
        case .retry, .restart: code = ""; stage = sent == nil ? .destination : .code
        case .leave: break
        }
    }

    var canResend: Bool { sent?.sendsRemaining != 0 }

    func secondsUntilResend(now: Date = Date()) -> Int {
        resendAt.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) } ?? 0
    }

    func changeDestination() { sent = nil; code = ""; problem = nil; stage = .destination }

    func setCode(_ value: String) {
        code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(CredflareSpec.Requirements.contactCodesCodeLength))
    }
}
