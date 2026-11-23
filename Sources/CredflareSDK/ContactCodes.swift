import Foundation

public enum ContactChannel: String, Sendable, CaseIterable {
    case email, phone
    public var verificationType: String {
        self == .email ? CredflareSpec.Requirements.contactCodesChannelsEmail : CredflareSpec.Requirements.contactCodesChannelsPhone
    }
    public init?(verificationType: String) {
        guard let channel = Self.allCases.first(where: { $0.verificationType == verificationType }) else { return nil }
        self = channel
    }

    public func normalized(_ destination: String) -> String {
        let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard self == .phone else { return trimmed }
        return trimmed.replacingOccurrences(of: CredflareSpec.Requirements.contactCodesPhoneStrip, with: "", options: .regularExpression)
    }

    public func isValid(_ destination: String) -> Bool {
        let value = normalized(destination)
        switch self {
        case .email: return value.count <= CredflareSpec.Requirements.contactCodesEmailMaxLength && Questionnaire.isEmail(value)
        case .phone: return destination.count <= CredflareSpec.Requirements.contactCodesPhoneMaxLength && value.range(of: CredflareSpec.Requirements.contactCodesPhonePattern, options: .regularExpression) != nil
        }
    }

    public static func isCode(_ code: String) -> Bool {
        code.count == CredflareSpec.Requirements.contactCodesCodeLength && code.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

public struct ContactCodeSent: Decodable, Equatable, Sendable {
    public let channel: String
    public let destination: String
    public let expiresAt: String
    public let resendAvailableAt: String
    public let sendsRemaining: Int
    enum CodingKeys: String, CodingKey {
        case channel, destination, expiresAt = "expires_at", resendAvailableAt = "resend_available_at", sendsRemaining = "sends_remaining"
    }
    public var resendDate: Date? { ISO8601.parse(resendAvailableAt) }
    public func secondsUntilResend(now: Date = Date()) -> Int {
        guard let date = resendDate else { return 0 }
        return Swift.max(0, Int(date.timeIntervalSince(now).rounded(.up)))
    }
}
