import XCTest
import AVFoundation
import CoreVideo
@testable import CredflareSDK

final class LiveBackendTests: XCTestCase {
    func session() async throws -> VerificationSession {
        guard let raw = ProcessInfo.processInfo.environment["CREDFLARE_DEMO_SESSION_URL"], let url = URL(string: raw) else { throw XCTSkip("Set CREDFLARE_DEMO_SESSION_URL to run against a local backend") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["email": "swift-live-test@example.test"])
        let (data, _) = try await URLSession.shared.data(for: request)
        return VerificationSession(try JSONDecoder().decode(SessionDescriptor.self, from: data))
    }

    func video(seconds: Int) async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 480, AVVideoHeightKey: 640])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 480, kCVPixelBufferHeightKey as String: 640])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for frame in 0..<(seconds * 15) {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 1_000_000) }
            var buffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
            adaptor.append(buffer!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 15))
        }
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    func testFakeProviderChallengeIsAcceptedByTheBackend() async throws {
        let client = try await session()
        let info = try await client.get()
        XCTAssertNotNil(info.profile?.requirements.first { $0.facial != nil })
        let challenge = try await client.createLivenessChallenge()
        let capture = try LivenessCapture(challenge: challenge, provider: FakeFaceSignalProvider(script: scriptPassing(challenge.gestures)))
        let buffer = pixelBuffer()
        var index = 0
        while !capture.isFinished && index < 200 { _ = capture.process(buffer, seconds: Double(index) * 0.066); index += 1 }
        let clip = challenge.recordVideo ? try await video(seconds: 2) : nil
        defer { if let clip { try? FileManager.default.removeItem(at: clip) } }
        let evidence = try XCTUnwrap(capture.evidence(video: clip))
        var keys: [String: UUID] = [:]
        let id = try await LivenessSubmitter.submit(evidence, client: client, keys: &keys)
        XCTAssertGreaterThan(id, 0)
        do {
            _ = try await client.submitFacial(FacialSubmission(challengeID: challenge.challengeID, imageFileID: 1, gestureFileIDs: [1], videoFileID: nil, provider: "vision", livenessResults: [], faceDetection: evidence.faceDetection, capturedAt: ISO8601.format(Date())), key: UUID())
            XCTFail("A used challenge must be rejected")
        } catch let error as CredflareError {
            XCTAssertEqual(error.code, .livenessChallengeUsed)
        }
    }
}
