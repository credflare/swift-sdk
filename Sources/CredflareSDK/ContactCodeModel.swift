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
    @Published var changeAfter = false
    var sentTo: String?
    let channel: ContactChannel
    let verifier: String
    var help = HelpContact()
    private let client: VerificationSession
    private let onDone: () -> Void
    private let onLeave: (VerificationResult) -> Void
    private let onClosed: () -> Void

    init(client: VerificationSession, channel: ContactChannel, verifier: String, onDone: @escaping () -> Void, onLeave: @escaping (VerificationResult) -> Void, onClosed: @escaping () -> Void = {}) {
        self.client = client; self.channel = channel; self.verifier = verifier; self.onDone = onDone; self.onLeave = onLeave; self.onClosed = onClosed
    }

    func text(_ key: String, _ values: [String: String] = [:]) -> String {
        CredflareCopy.text(key, values.merging(["verifier": verifier]) { a, _ in a })
    }

    var titleKey: String { channel == .email ? CredflareSpec.CopyKey.emailTitle : CredflareSpec.CopyKey.phoneTitle }

    func send() async {
        guard stage != .sending, stage != .confirming else { return }
        guard channel.isValid(destination) else {
            problem = text(channel == .email ? CredflareSpec.CopyKey.emailInvalid : CredflareSpec.CopyKey.phoneInvalid)
            return
        }
        let target = channel.normalized(destination)
        if stage == .destination, sent?.sendsRemaining == 0, target == sentTo { problem = nil; code = ""; stage = .code; return }
        let back: Stage = stage == .destination || sent == nil ? .destination : .code
        problem = nil; stage = .sending
        do {
            sent = try await client.requestCode(channel, to: target)
            sentTo = target; changeAfter = false
            code = ""; stage = .code
        } catch let error as CredflareError {
            if case .api(409, _, _) = error { onClosed() }
            else if case .api(422, _, _) = error {
                let rejection = Rejection(error, requester: verifier, contact: help)
                if let next = rejection.resendAvailableAt { resendAt = next }
                stage = .rejected(rejection)
            }
            else { problem = text(CredflareSpec.CopyKey.errorsSendCodeFailed); stage = back }
        } catch {
            problem = text(CredflareSpec.CopyKey.errorsSendCodeFailed); stage = back
        }
    }

    func confirm() async {
        guard stage == .code, ContactChannel.isCode(code) else { return }
        problem = nil; stage = .confirming
        do {
            _ = try await client.confirmCode(channel, code: code)
            onDone()
        } catch let error as CredflareError {
            if case .api(409, _, _) = error { onClosed() }
            else if case .api(422, _, _) = error { stage = .rejected(Rejection(error, requester: verifier, contact: help)) }
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
        case .newCode: await resend()
        case .wait:
            let typed = channel.normalized(destination)
            if let waiting = rejection.waitingCode {
                if let known = sentTo, !Self.masked(waiting.destination, matches: known) { sentTo = nil }
                let same = sentTo.map { $0 == typed } ?? Self.masked(waiting.destination, matches: typed)
                if let sentTo, !same { destination = sentTo }
                sent = waiting
                changeAfter = !same
            } else if let sentTo, sentTo != typed { destination = sentTo; changeAfter = true }
            code = ""; stage = .code
        case .retry, .restart: code = ""; stage = sent == nil ? .destination : .code
        case .leave: break
        }
    }

    var canResend: Bool { sent?.sendsRemaining != 0 }

    func resend() async {
        guard let sentTo else { return changeDestination() }
        destination = sentTo
        await send()
    }

    static func masked(_ mask: String, matches value: String) -> Bool {
        let shown = Array(mask), typed = Array(value)
        guard shown.count == typed.count, shown.contains("*") else { return mask == value }
        return zip(shown, typed).allSatisfy { $0 == "*" || $0.lowercased() == $1.lowercased() }
    }

    func secondsUntilResend(now: Date = Date()) -> Int {
        resendAt.map { max(0, Int($0.timeIntervalSince(now).rounded(.up))) } ?? 0
    }

    func changeDestination() { code = ""; problem = nil; changeAfter = false; stage = .destination }

    func returnToCode() {
        if let sentTo { destination = sentTo }
        problem = nil; stage = .code
    }

    func setCode(_ value: String) {
        code = String(value.filter { $0.isASCII && $0.isNumber }.prefix(CredflareSpec.Requirements.contactCodesCodeLength))
    }
}
