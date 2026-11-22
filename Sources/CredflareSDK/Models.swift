import Foundation

public struct SessionDescriptor: Decodable, CustomStringConvertible, CustomDebugStringConvertible {
    public let sessionID: UUID
    public let apiBaseURL: URL
    public let expiresAt: String
    let token: String
    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id", token, apiBaseURL = "api_base_url", expiresAt = "expires_at"
    }
    public init(sessionID: UUID, token: String, apiBaseURL: URL, expiresAt: String) throws {
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(apiBaseURL.host ?? "")
        guard apiBaseURL.scheme == "https" || (local && apiBaseURL.scheme == "http"),
              apiBaseURL.host != nil, apiBaseURL.user == nil, apiBaseURL.password == nil,
              apiBaseURL.query == nil, apiBaseURL.fragment == nil, !token.isEmpty else {
            throw CredflareError.validation("Use an HTTPS API URL or HTTP loopback for development.")
        }
        self.sessionID = sessionID; self.token = token; self.apiBaseURL = apiBaseURL; self.expiresAt = expiresAt
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(sessionID: values.decode(UUID.self, forKey: .sessionID), token: values.decode(String.self, forKey: .token), apiBaseURL: values.decode(URL.self, forKey: .apiBaseURL), expiresAt: values.decode(String.self, forKey: .expiresAt))
    }
    public var description: String { "Credflare session \(sessionID)" }
    public var debugDescription: String { description }
}

public enum JSONValue: Codable, Sendable {
    case object([String: JSONValue]), array([JSONValue]), string(String), number(Double), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let v = try? value.decode(Bool.self) { self = .bool(v) }
        else if let v = try? value.decode(Double.self) { self = .number(v) }
        else if let v = try? value.decode(String.self) { self = .string(v) }
        else if let v = try? value.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try value.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let v): try value.encode(v)
        case .array(let v): try value.encode(v)
        case .string(let v): try value.encode(v)
        case .number(let v): try value.encode(v)
        case .bool(let v): try value.encode(v)
        case .null: try value.encodeNil()
        }
    }
    var isEmpty: Bool {
        switch self { case .null: return true; case .array(let v): return v.isEmpty; case .object(let v): return v.isEmpty; default: return false }
    }
}

public struct SessionInfo: Decodable {
    public let sessionID: UUID
    public let status: String?
    public let environment: String
    public let requester: Requester?
    public let customMessage: String?
    public let uploadLimits: UploadLimits
    public let profile: Profile?
    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id", status, environment, requester, customMessage = "custom_message", uploadLimits = "upload_limits", profile
    }
    public struct Requester: Decodable {
        public let name: String; public let logoURL: URL?; public let helpEmail: String?; public let helpURL: String?
        enum CodingKeys: String, CodingKey { case name, logoURL = "logo_url", helpEmail = "help_email", helpURL = "help_url" }
        public var help: HelpContact { HelpContact(email: helpEmail, url: helpURL) }
    }
    public struct UploadLimits: Decodable {
        public let maxFileSizeBytes: Int; public let allowedFileTypes: [String]
        enum CodingKeys: String, CodingKey { case maxFileSizeBytes = "max_file_size_bytes", allowedFileTypes = "allowed_file_types" }
    }
    public struct Profile: Decodable {
        public let documentRequirements: [DocumentRequirement]
        public let formSchema: JSONValue?
        public let verificationRequirements: [JSONValue]
        enum CodingKeys: String, CodingKey { case documentRequirements = "document_requirements", formSchema = "form_schema", verificationRequirements = "verification_requirements" }
        public var requirements: [VerificationRequirement] { verificationRequirements.map(VerificationRequirement.init) }
        public var requiresSelfie: Bool { requirements.contains { $0.facial != nil } }
        public var requiresLocation: Bool { requirements.contains { $0.location != nil } }
        public var questionnaire: Questionnaire? { Questionnaire(formSchema) }
        public var needsHostSteps: Bool { !(questionnaire?.isSupported ?? true) || requirements.contains { !$0.isHandledInSDK } }
    }
}

public struct DocumentRequirement: Decodable, Identifiable {
    public let documentType: DocumentType
    public let captureMethod: String?
    public let requestedSides: [DocumentSide]?
    public let groupKey: String?
    public let rule: String
    public let minRequired: Int?
    public let remainingRequired: Int?
    public var id: Int { documentType.id }
    public struct DocumentType: Decodable {
        public let id: Int; public let name: String; public let twoSided: Bool; public let captureMethod: String
        enum CodingKeys: String, CodingKey { case id, name, twoSided = "two_sided", captureMethod = "capture_method" }
    }
    enum CodingKeys: String, CodingKey { case documentType = "document_type", captureMethod = "capture_method", requestedSides = "requested_sides", groupKey = "group_key", rule, minRequired = "min_required", remainingRequired = "remaining_required" }
    public var policy: String {
        let method = captureMethod ?? (documentType.captureMethod == "camera" ? "snapshot_or_upload" : "upload")
        return method == "either" ? "snapshot_or_upload" : method
    }
    public var isSupported: Bool { ["upload", "snapshot_or_upload", "snapshot", "snapshot_and_upload"].contains(policy) }
    public var methodSummary: String {
        switch policy {
        case "snapshot": return CredflareCopy.text(CredflareSpec.CopyKey.documentsMethodCamera)
        case "upload": return CredflareCopy.text(CredflareSpec.CopyKey.documentsMethodUpload)
        case "snapshot_or_upload": return CredflareCopy.text(CredflareSpec.CopyKey.documentsMethodEither)
        case "snapshot_and_upload": return CredflareCopy.text(CredflareSpec.CopyKey.documentsMethodBoth)
        default: return CredflareCopy.text(CredflareSpec.CopyKey.documentsUnavailable, ["verifier": CredflareCopy.verifier(nil)])
        }
    }
    public func captureSteps() throws -> [CaptureStep] {
        guard isSupported else { throw CredflareError.validation("This capture method is not available in this app.") }
        let sides = requestedSides ?? (documentType.twoSided ? [.front, .back] : [.front])
        let sources: [CaptureInput] = policy == "snapshot_and_upload" ? [.camera, .upload] : [policy == "snapshot" ? .camera : policy == "snapshot_or_upload" ? .cameraOrUpload : .upload]
        return sources.flatMap { source in sides.map { CaptureStep(side: $0, input: source) } }
    }
}
public enum DocumentSide: String, Codable { case front, back; public var label: String { rawValue.capitalized } }
public enum CaptureSource: String, Codable { case camera, upload }
public enum CaptureInput: String { case camera, upload, cameraOrUpload = "camera_or_upload" }
public struct CaptureStep: Identifiable {
    public let side: DocumentSide; public let input: CaptureInput
    public var id: String { "\(input.rawValue):\(side.rawValue)" }
}
public struct UploadedEvidence: Decodable { public let id: Int }
public struct Evidence: Encodable {
    public let fileID: Int; public let source: CaptureSource; public let side: DocumentSide
    public init(fileID: Int, source: CaptureSource, side: DocumentSide) { self.fileID = fileID; self.source = source; self.side = side }
    enum CodingKeys: String, CodingKey { case fileID = "file_id", source, side }
}
public struct RejectionCode: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public var isKnown: Bool { CredflareSpec.ErrorCode.meanings[rawValue] != nil }
    public var description: String { rawValue }
    public static let locationAccuracy = RejectionCode(rawValue: CredflareSpec.ErrorCode.locationAccuracy)
    public static let locationStale = RejectionCode(rawValue: CredflareSpec.ErrorCode.locationStale)
    public static let locationMock = RejectionCode(rawValue: CredflareSpec.ErrorCode.locationMock)
    public static let locationIpCountry = RejectionCode(rawValue: CredflareSpec.ErrorCode.locationIpCountry)
    public static let locationReferenceNotMatched = RejectionCode(rawValue: CredflareSpec.ErrorCode.locationReferenceNotMatched)
    public static let livenessChallengeInvalid = RejectionCode(rawValue: CredflareSpec.ErrorCode.livenessChallengeInvalid)
    public static let livenessChallengeExpired = RejectionCode(rawValue: CredflareSpec.ErrorCode.livenessChallengeExpired)
    public static let livenessChallengeUsed = RejectionCode(rawValue: CredflareSpec.ErrorCode.livenessChallengeUsed)
    public static let livenessGestureMismatch = RejectionCode(rawValue: CredflareSpec.ErrorCode.livenessGestureMismatch)
    public static let livenessFrameOutOfWindow = RejectionCode(rawValue: CredflareSpec.ErrorCode.livenessFrameOutOfWindow)
    public static let livenessNotCamera = RejectionCode(rawValue: CredflareSpec.ErrorCode.livenessNotCamera)
    public static let livenessVideoMissing = RejectionCode(rawValue: CredflareSpec.ErrorCode.livenessVideoMissing)
    public static let livenessVideoTooLong = RejectionCode(rawValue: CredflareSpec.ErrorCode.livenessVideoTooLong)
    public static let livenessVideoUnreadable = RejectionCode(rawValue: CredflareSpec.ErrorCode.livenessVideoUnreadable)
    public static let emailNotConfigured = RejectionCode(rawValue: CredflareSpec.ErrorCode.emailNotConfigured)
    public static let emailResendTooSoon = RejectionCode(rawValue: CredflareSpec.ErrorCode.emailResendTooSoon)
    public static let emailSendLimit = RejectionCode(rawValue: CredflareSpec.ErrorCode.emailSendLimit)
    public static let emailCodeMissing = RejectionCode(rawValue: CredflareSpec.ErrorCode.emailCodeMissing)
    public static let emailCodeExpired = RejectionCode(rawValue: CredflareSpec.ErrorCode.emailCodeExpired)
    public static let emailCodeInvalid = RejectionCode(rawValue: CredflareSpec.ErrorCode.emailCodeInvalid)
    public static let emailTooManyAttempts = RejectionCode(rawValue: CredflareSpec.ErrorCode.emailTooManyAttempts)
    public static let phoneNotConfigured = RejectionCode(rawValue: CredflareSpec.ErrorCode.phoneNotConfigured)
    public static let phoneResendTooSoon = RejectionCode(rawValue: CredflareSpec.ErrorCode.phoneResendTooSoon)
    public static let phoneSendLimit = RejectionCode(rawValue: CredflareSpec.ErrorCode.phoneSendLimit)
    public static let phoneCodeMissing = RejectionCode(rawValue: CredflareSpec.ErrorCode.phoneCodeMissing)
    public static let phoneCodeExpired = RejectionCode(rawValue: CredflareSpec.ErrorCode.phoneCodeExpired)
    public static let phoneCodeInvalid = RejectionCode(rawValue: CredflareSpec.ErrorCode.phoneCodeInvalid)
    public static let phoneTooManyAttempts = RejectionCode(rawValue: CredflareSpec.ErrorCode.phoneTooManyAttempts)
}

public enum CredflareError: LocalizedError {
    case validation(String), network(String), api(Int, String, code: RejectionCode?, resendAvailableAt: String? = nil), invalidResponse
    public var errorDescription: String? {
        switch self { case .validation(let v), .network(let v), .api(_, let v, _, _): return v; case .invalidResponse: return "Credflare returned an invalid response." }
    }
    public var code: RejectionCode? { if case .api(_, _, let code, _) = self { return code }; return nil }
    public var resendAvailableAt: Date? { if case .api(_, _, _, let value?) = self { return ISO8601.parse(value) }; return nil }
    public var type: String {
        switch self { case .validation: return "validation"; case .network: return "network"; case .invalidResponse: return "api"; case .api(let status, _, _, _): return status == 401 ? "session_unavailable" : status == 409 ? "verification_closed" : status == 422 ? "validation" : "api" }
    }
}
public enum VerificationResult: Equatable { case submitted, cancelled, hostActionRequired(code: RejectionCode? = nil) }
