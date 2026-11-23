import Foundation

extension JSONValue {
    subscript(key: String) -> JSONValue? { if case .object(let value) = self { return value[key] }; return nil }
    var stringValue: String? { if case .string(let value) = self { return value }; return nil }
    var doubleValue: Double? { if case .number(let value) = self { return value }; return nil }
    var intValue: Int? { doubleValue.map { Int($0) } }
    var boolValue: Bool? { if case .bool(let value) = self { return value }; return nil }
    var arrayValue: [JSONValue]? { if case .array(let value) = self { return value }; return nil }
}

public struct FacialSettings: Equatable, Sendable {
    public let gestures: [String]
    public let gestureCount: Int
    public let recordVideo: Bool
    init(_ settings: JSONValue?) {
        gestures = settings?["gestures"]?.arrayValue?.compactMap(\.stringValue) ?? CredflareSpec.Settings.facialVerificationGesturesDefault
        gestureCount = settings?["gesture_count"]?.intValue ?? CredflareSpec.Settings.facialVerificationGestureCountDefault
        recordVideo = settings?["record_video"]?.boolValue ?? CredflareSpec.Settings.facialVerificationRecordVideoDefault
    }
}

public struct PlaceReference: Equatable, Sendable {
    public enum Rule: String, Sendable { case within, outside }
    public let rule: Rule
    public let match: String
    public let placeLabels: [String]
    init?(_ value: JSONValue?) {
        guard let value, case .object = value else { return nil }
        rule = Rule(rawValue: value["rule"]?.stringValue ?? "within") ?? .within
        match = value["match"]?.stringValue ?? "any"
        placeLabels = value["places"]?.arrayValue?.compactMap { $0["label"]?.stringValue }.filter { !$0.isEmpty } ?? []
    }
}

public struct LocationSettings: Equatable, Sendable {
    public let maxAccuracyM: Int
    public let maxAgeS: Int
    public let mockLocation: String
    public let ipCountry: String
    public let reference: PlaceReference?
    init(_ settings: JSONValue?) {
        maxAccuracyM = settings?["max_accuracy_m"]?.intValue ?? CredflareSpec.Settings.locationVerificationMaxAccuracyMDefault
        maxAgeS = settings?["max_age_s"]?.intValue ?? CredflareSpec.Settings.locationVerificationMaxAgeSDefault
        mockLocation = settings?["mock_location"]?.stringValue ?? CredflareSpec.Settings.locationVerificationMockLocationDefault
        ipCountry = settings?["ip_country"]?.stringValue ?? CredflareSpec.Settings.locationVerificationIpCountryDefault
        reference = PlaceReference(settings?["reference"])
    }
}

public struct VerificationRequirement: Sendable {
    public let type: String
    public let facial: FacialSettings?
    public let location: LocationSettings?
    public let contact: ContactChannel?
    public var isHandledInSDK: Bool { facial != nil || location != nil || contact != nil }
    init(_ raw: JSONValue) {
        type = raw["verification_type"]?.stringValue ?? ""
        facial = type == "facial_verification" ? FacialSettings(raw["settings"]) : nil
        location = type == "location_verification" ? LocationSettings(raw["settings"]) : nil
        contact = ContactChannel(verificationType: type)
    }
}

public struct LivenessChallenge: Decodable, Equatable, Sendable {
    public let challengeID: String
    public let gestures: [String]
    public let expiresAt: String
    public let recordVideo: Bool
    public let maxVideoSeconds: Int
    enum CodingKeys: String, CodingKey { case challengeID = "challenge_id", gestures, expiresAt = "expires_at", recordVideo = "record_video", maxVideoSeconds = "max_video_seconds" }
    public var expiryDate: Date? { ISO8601.parse(expiresAt) }
}

public enum BiometricUploadType: String, Sendable { case gesture, livenessVideo = "liveness_video", selfie }

public struct LivenessResult: Encodable, Equatable, Sendable {
    public let challenge: String
    public let completed: Bool
    public let timestamp: String
    public init(challenge: String, completed: Bool, timestamp: String) { self.challenge = challenge; self.completed = completed; self.timestamp = timestamp }
}

public struct FaceDetectionSummary: Encodable, Equatable, Sendable {
    public let detected: Bool
    public let faceCount: Int
    public let isCentered: Bool
    public let isCorrectSize: Bool
    public init(detected: Bool, faceCount: Int, isCentered: Bool, isCorrectSize: Bool) { self.detected = detected; self.faceCount = faceCount; self.isCentered = isCentered; self.isCorrectSize = isCorrectSize }
    enum CodingKeys: String, CodingKey { case detected, faceCount = "face_count", isCentered = "is_centered", isCorrectSize = "is_correct_size" }
}

public struct FacialSubmission: Encodable, Sendable {
    public struct Metadata: Encodable, Sendable {
        public let provider: String
        public let livenessResults: [LivenessResult]
        public let faceDetection: FaceDetectionSummary
        public let capturedAt: String
        enum CodingKeys: String, CodingKey { case provider, livenessResults = "liveness_results", faceDetection = "face_detection", capturedAt = "captured_at" }
    }
    public let challengeID: String
    public let imageFileID: Int
    public let gestureFileIDs: [Int]
    public let videoFileID: Int?
    public let metadata: Metadata
    public init(challengeID: String, imageFileID: Int, gestureFileIDs: [Int], videoFileID: Int?, provider: String, livenessResults: [LivenessResult], faceDetection: FaceDetectionSummary, capturedAt: String) {
        self.challengeID = challengeID; self.imageFileID = imageFileID; self.gestureFileIDs = gestureFileIDs; self.videoFileID = videoFileID
        metadata = Metadata(provider: provider, livenessResults: livenessResults, faceDetection: faceDetection, capturedAt: capturedAt)
    }
    enum CodingKeys: String, CodingKey { case type, challengeID = "challenge_id", imageFileID = "image_file_id", gestureFileIDs = "gesture_file_ids", videoFileID = "video_file_id", metadata }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("facial_verification", forKey: .type)
        try c.encode(challengeID, forKey: .challengeID)
        try c.encode(imageFileID, forKey: .imageFileID)
        try c.encode(gestureFileIDs, forKey: .gestureFileIDs)
        try c.encodeIfPresent(videoFileID, forKey: .videoFileID)
        try c.encode(metadata, forKey: .metadata)
    }
}

public struct LocationSubmission: Encodable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let accuracy: Double
    public let altitude: Double?
    public let fixTime: Date
    public let isMock: Bool?
    public let provider: String
    public let capturedAt: Date
    public init(latitude: Double, longitude: Double, accuracy: Double, altitude: Double?, fixTime: Date, isMock: Bool?, provider: String, capturedAt: Date) {
        self.latitude = latitude; self.longitude = longitude; self.accuracy = accuracy; self.altitude = altitude
        self.fixTime = fixTime; self.isMock = isMock; self.provider = provider; self.capturedAt = capturedAt
    }
    enum CodingKeys: String, CodingKey { case type, latitude, longitude, metadata }
    enum MetadataKeys: String, CodingKey { case accuracy, altitude, fixTime = "fix_time", isMock = "is_mock", provider, capturedAt = "captured_at" }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode("location_verification", forKey: .type)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        var m = c.nestedContainer(keyedBy: MetadataKeys.self, forKey: .metadata)
        try m.encode(accuracy, forKey: .accuracy)
        if let altitude { try m.encode(altitude, forKey: .altitude) } else { try m.encodeNil(forKey: .altitude) }
        try m.encode(ISO8601.format(fixTime), forKey: .fixTime)
        if let isMock { try m.encode(isMock, forKey: .isMock) } else { try m.encodeNil(forKey: .isMock) }
        try m.encode(provider, forKey: .provider)
        try m.encode(ISO8601.format(capturedAt), forKey: .capturedAt)
    }
}

enum ISO8601 {
    static func format(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
    static func parse(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

extension SessionInfo.Profile {
    public var stepsAfterDocuments: [String] { requirements.filter { $0.facial != nil || $0.location != nil }.map(\.type) }

    public var nextStepsCopyKey: String? {
        var steps: [String] = []
        for step in stepsAfterDocuments where !steps.contains(step) { steps.append(step) }
        switch steps {
        case ["facial_verification"]: return CredflareSpec.CopyKey.documentsSelfieNext
        case ["location_verification"]: return CredflareSpec.CopyKey.documentsLocationNext
        case ["facial_verification", "location_verification"]: return CredflareSpec.CopyKey.documentsSelfieLocationNext
        case ["location_verification", "facial_verification"]: return CredflareSpec.CopyKey.documentsLocationSelfieNext
        case []: return needsHostSteps || questionnaire != nil || requirements.contains { $0.contact != nil } ? CredflareSpec.CopyKey.documentsHostStepsNext : nil
        default: return nil
        }
    }
}
