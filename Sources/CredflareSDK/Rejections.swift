import Foundation

public enum RejectionAction: String, Sendable, CaseIterable {
    case retry, restart, reenterCode = "reenter_code", newCode = "new_code", wait, leave
    public var label: String { CredflareCopy.text(CredflareSpec.Rejection.actionLabels[rawValue] ?? CredflareSpec.CopyKey.commonTryAgain) }
}

public struct HelpContact: Equatable, Sendable {
    public let email: String?
    public let url: URL?
    public init(email: String? = nil, url: String? = nil) {
        let trimmed = email?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.email = trimmed.isEmpty ? nil : trimmed
        let link = url.flatMap(URL.init(string:))
        self.url = ["http", "https"].contains(link?.scheme?.lowercased() ?? "") && link?.host != nil ? link : nil
    }
}

public struct Rejection: Equatable, Sendable {
    public let code: RejectionCode?
    public let title: String?
    public let message: String
    public let action: RejectionAction
    public let requestedBy: String
    public let help: String
    public let helpLink: URL?
    public let resendAvailableAt: Date?
    public var actionLabel: String { action.label }
    public var leaveResult: VerificationResult? { action == .leave ? .hostActionRequired(code: code) : nil }

    public init(_ error: CredflareError, requester: String?, contact: HelpContact = HelpContact(), reference: PlaceReference? = nil) {
        let verifier = CredflareCopy.verifier(requester)
        let values = ["verifier": verifier]
        requestedBy = CredflareCopy.text(CredflareSpec.Rejection.requestedBy, values)
        resendAvailableAt = error.resendAvailableAt
        if let email = contact.email {
            help = CredflareCopy.text(CredflareSpec.Rejection.helpEmail, ["verifier": verifier, "help_email": email])
            var mail = URLComponents(); mail.scheme = "mailto"; mail.path = email
            helpLink = mail.url
        } else if let url = contact.url {
            help = CredflareCopy.text(CredflareSpec.Rejection.helpUrl, ["help_url": url.absoluteString])
            helpLink = url
        } else {
            help = CredflareCopy.text(CredflareSpec.Rejection.help, values)
            helpLink = nil
        }
        guard let code = error.code, let entry = CredflareSpec.Rejection.codes[code.rawValue] else {
            self.code = error.code
            title = nil
            message = error.localizedDescription
            action = .retry
            return
        }
        self.code = code
        title = CredflareCopy.text(entry.title, values)
        action = RejectionAction(rawValue: entry.action) ?? .retry
        if let reference, !reference.placeLabels.isEmpty,
           let key = reference.rule == .within ? entry.placeMessageWithin : entry.placeMessageOutside {
            message = CredflareCopy.text(key, values.merging(["place": reference.placeLabels.joined(separator: ", ")]) { a, _ in a })
        } else {
            message = CredflareCopy.text(entry.message, values)
        }
    }
}
