import Foundation
import CoreImage
import CoreVideo
import ImageIO

public struct LivenessUpdate: Sendable {
    public let sample: FaceSample
    public let phase: LivenessSequence.Phase
    public let event: LivenessSequence.Event
    public let selfieCaptured: Bool
}

public struct LivenessEvidence: Sendable {
    public let challenge: LivenessChallenge
    public let provider: String
    public let gestureFrames: [Data]
    public let selfie: Data
    public let video: URL?
    public let results: [LivenessResult]
    public let faceDetection: FaceDetectionSummary
    public let capturedAt: Date
}

public final class LivenessCapture {
    public let challenge: LivenessChallenge
    public let sequence: LivenessSequence
    private let provider: FaceSignalProvider
    private let encoder: (CVPixelBuffer, CGImagePropertyOrientation) -> Data?
    private let clock: () -> Date
    private var startTime: Double?
    private(set) public var gestureFrames: [Data] = []
    private(set) public var selfie: Data?
    private var selfieDeadline: Int?
    private(set) public var selfieTimedOut = false

    public init(challenge: LivenessChallenge, provider: FaceSignalProvider, rules: LivenessRules = .spec, clock: @escaping () -> Date = Date.init, encoder: ((CVPixelBuffer, CGImagePropertyOrientation) -> Data?)? = nil) throws {
        self.challenge = challenge; self.provider = provider; self.clock = clock
        self.encoder = encoder ?? LivenessCapture.jpeg
        sequence = try LivenessSequence(gestures: challenge.gestures, provider: provider.name, rules: rules, clock: clock)
        provider.reset()
    }

    public var isExpired: Bool { challenge.expiryDate.map { clock() >= $0 } ?? false }
    public var isFinished: Bool { selfie != nil || selfieTimedOut || { if case .timedOut = sequence.phase { return true }; return false }() }

    public func process(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation = .up, seconds: Double) -> LivenessUpdate {
        if startTime == nil { startTime = seconds }
        let t = Int(((seconds - startTime!) * 1000).rounded())
        let sample = provider.sample(from: buffer, orientation: orientation, t: t)
        if case .completed = sequence.phase {
            guard selfie == nil, !selfieTimedOut else { return LivenessUpdate(sample: sample, phase: sequence.phase, event: .none, selfieCaptured: false) }
            if selfieDeadline == nil { selfieDeadline = t + CredflareSpec.Liveness.gestureTimeoutMs }
            let neutral = abs(sample.yaw ?? 0) < (LivenessRules.spec.resolvedThresholds(provider.name)["return"] ?? 10)
            if PositionStatus.of(sample) == .ok && neutral, let data = encoder(buffer, orientation) {
                selfie = data
                return LivenessUpdate(sample: sample, phase: sequence.phase, event: .none, selfieCaptured: true)
            }
            if t >= selfieDeadline! { selfieTimedOut = true; return LivenessUpdate(sample: sample, phase: .timedOut(gesture: nil), event: .timeout, selfieCaptured: false) }
            return LivenessUpdate(sample: sample, phase: sequence.phase, event: .none, selfieCaptured: false)
        }
        let event = sequence.push(sample)
        if case .gesturePassed = event {
            if let data = encoder(buffer, orientation) { gestureFrames.append(data) }
        }
        return LivenessUpdate(sample: sample, phase: sequence.phase, event: event, selfieCaptured: false)
    }

    public func evidence(video: URL?) -> LivenessEvidence? {
        guard let selfie, gestureFrames.count == challenge.gestures.count else { return nil }
        return LivenessEvidence(challenge: challenge, provider: provider.name, gestureFrames: gestureFrames, selfie: selfie, video: video, results: sequence.results, faceDetection: sequence.faceDetection, capturedAt: clock())
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])
    public static func jpeg(_ buffer: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> Data? {
        let image = CIImage(cvPixelBuffer: buffer).oriented(orientation)
        return context.jpegRepresentation(of: image, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [kCGImageDestinationLossyCompressionQuality as CIImageRepresentationOption: 0.85])
    }
}

public enum LivenessSubmitter {
    public static func submit(_ evidence: LivenessEvidence, client: VerificationSession, keys: inout [String: UUID]) async throws -> Int {
        func key(_ name: String) -> UUID { if let existing = keys[name] { return existing }; let next = UUID(); keys[name] = next; return next }
        let challenge = evidence.challenge
        var gestureIDs: [Int] = []
        for (index, gesture) in challenge.gestures.enumerated() {
            gestureIDs.append(try await client.uploadBiometric(evidence.gestureFrames[index], filename: "\(gesture).jpg", type: .gesture, challengeID: challenge.challengeID, gesture: gesture, key: key("gesture-\(index)")).id)
        }
        var videoID: Int?
        if challenge.recordVideo {
            guard let url = evidence.video, let data = try? Data(contentsOf: url), !data.isEmpty else { throw CredflareError.validation("The challenge video was not recorded.") }
            videoID = try await client.uploadBiometric(data, filename: "liveness.\(url.pathExtension.isEmpty ? "mp4" : url.pathExtension)", type: .livenessVideo, challengeID: challenge.challengeID, key: key("video")).id
        }
        let selfieID = try await client.uploadBiometric(evidence.selfie, filename: "selfie.jpg", type: .selfie, challengeID: challenge.challengeID, key: key("selfie")).id
        let submission = FacialSubmission(challengeID: challenge.challengeID, imageFileID: selfieID, gestureFileIDs: gestureIDs, videoFileID: videoID, provider: evidence.provider, livenessResults: evidence.results, faceDetection: evidence.faceDetection, capturedAt: ISO8601.format(evidence.capturedAt))
        return try await client.submitFacial(submission, key: key("submit"))
    }
}
