import XCTest
import CoreGraphics
import CoreVideo
import ImageIO
@testable import CredflareSDK

final class FakeFaceSignalProvider: FaceSignalProvider {
    let name: String
    var script: [FaceSample]
    private(set) var resets = 0
    init(name: String = "vision", script: [FaceSample]) { self.name = name; self.script = script }
    func reset() { resets += 1 }
    func sample(from pixelBuffer: CVPixelBuffer, orientation: CGImagePropertyOrientation, t: Int) -> FaceSample {
        var next = script.isEmpty ? FaceSample(t: t, faces: 0) : script.removeFirst()
        next.t = t
        return next
    }
}

func pixelBuffer() -> CVPixelBuffer {
    var buffer: CVPixelBuffer?
    CVPixelBufferCreate(nil, 64, 96, kCVPixelFormatType_32BGRA, [kCVPixelBufferCGImageCompatibilityKey: true] as CFDictionary, &buffer)
    return buffer!
}

func face(eye: Double = 0.9, smile: Double = 0.1, yaw: Double = 0, pitch: Double = 0) -> FaceSample {
    FaceSample(t: 0, faces: 1, box: FaceBox(x: 0.29, y: 0.21, w: 0.42, h: 0.52), eyeOpen: eye, smile: smile, yaw: yaw, pitch: pitch)
}

let passingScript: [FaceSample] = [face()]
    + [face(eye: 0.9), face(eye: 0.1), face(eye: 0.9)]
    + Array(repeating: face(smile: 0.9), count: 5)
    + [face(yaw: -30), face(yaw: 2)]
    + [FaceSample(t: 0, faces: 0), face()]

func scriptPassing(_ gestures: [String]) -> [FaceSample] {
    var samples = [face()]
    for gesture in gestures {
        switch gesture {
        case "blink": samples += [face(eye: 0.9), face(eye: 0.1), face(eye: 0.9)]
        case "smile": samples += Array(repeating: face(smile: 0.9), count: 5)
        case "turn_left": samples += [face(yaw: 30), face(yaw: 0)]
        case "turn_right": samples += [face(yaw: -30), face(yaw: 0)]
        default: samples += [face(pitch: -25), face(pitch: 0)]
        }
    }
    return samples + [FaceSample(t: 0, faces: 0), face()]
}

let challenge = LivenessChallenge(challengeID: "01a1fb33-a1ee-71b2-bba9-9f484aa3bb1b", gestures: ["blink", "smile", "turn_right"], expiresAt: "2026-11-20T23:05:47.000000Z", recordVideo: true, maxVideoSeconds: 8)

extension LivenessChallenge {
    init(challengeID: String, gestures: [String], expiresAt: String, recordVideo: Bool, maxVideoSeconds: Int) {
        let json: [String: Any] = ["challenge_id": challengeID, "gestures": gestures, "expires_at": expiresAt, "record_video": recordVideo, "max_video_seconds": maxVideoSeconds]
        self = try! JSONDecoder().decode(LivenessChallenge.self, from: JSONSerialization.data(withJSONObject: json))
    }
}

final class LivenessCaptureTests: XCTestCase {
    let beforeExpiry = { ISO8601.parse("2026-11-20T23:04:00Z")! }

    func run(_ capture: LivenessCapture, frames: Int, step: Double = 0.066) -> [LivenessUpdate] {
        let buffer = pixelBuffer()
        return (0..<frames).map { capture.process(buffer, seconds: 100 + Double($0) * step) }
    }

    func testFakeProviderRunsServerGesturesInOrderAndCapturesFrames() throws {
        let provider = FakeFaceSignalProvider(script: passingScript)
        let capture = try LivenessCapture(challenge: challenge, provider: provider, clock: beforeExpiry)
        XCTAssertEqual(provider.resets, 1)
        XCTAssertFalse(capture.isExpired)
        let updates = run(capture, frames: passingScript.count)
        XCTAssertEqual(updates.map(\.event).filter { $0 != .none }, [
            .positionPassed,
            .gesturePassed(index: 0, gesture: "blink", isLast: false),
            .gesturePassed(index: 1, gesture: "smile", isLast: false),
            .gesturePassed(index: 2, gesture: "turn_right", isLast: true),
        ])
        XCTAssertEqual(updates.map(\.sample.t).prefix(3), [0, 66, 132])
        XCTAssertEqual(updates.last?.selfieCaptured, true)
        XCTAssertTrue(capture.isFinished)
        XCTAssertEqual(capture.gestureFrames.count, 3)
        for frame in capture.gestureFrames + [capture.selfie!] { XCTAssertEqual(Array(frame.prefix(2)), [0xFF, 0xD8]) }
        let evidence = try XCTUnwrap(capture.evidence(video: nil))
        XCTAssertEqual(evidence.results.map(\.challenge), challenge.gestures)
        XCTAssertEqual(evidence.provider, "vision")
        XCTAssertEqual(evidence.faceDetection, FaceDetectionSummary(detected: true, faceCount: 1, isCentered: true, isCorrectSize: true))
    }

    func testPositionHintsFollowTheSpecRules() throws {
        let off = FaceSample(t: 0, faces: 1, box: FaceBox(x: 0.6, y: 0.21, w: 0.38, h: 0.52))
        let small = FaceSample(t: 0, faces: 1, box: FaceBox(x: 0.4, y: 0.4, w: 0.2, h: 0.2))
        let provider = FakeFaceSignalProvider(script: [FaceSample(t: 0, faces: 0), FaceSample(t: 0, faces: 2), small, off, face()])
        let capture = try LivenessCapture(challenge: challenge, provider: provider, clock: beforeExpiry)
        let phases = run(capture, frames: 5).map(\.phase)
        XCTAssertEqual(phases, [.positioning(.noFace), .positioning(.multipleFaces), .positioning(.tooSmall), .positioning(.offCenter), .gesture(index: 0, name: "blink", tracked: true)])
    }

    func testGestureTimeoutEndsTheChallenge() throws {
        let provider = FakeFaceSignalProvider(script: [face()] + Array(repeating: face(), count: 200))
        let capture = try LivenessCapture(challenge: challenge, provider: provider, clock: beforeExpiry)
        let updates = run(capture, frames: 170)
        let timeout = try XCTUnwrap(updates.firstIndex { $0.event == .timeout })
        XCTAssertEqual(updates[timeout].phase, .timedOut(gesture: "blink"))
        XCTAssertGreaterThanOrEqual(updates[timeout].sample.t - updates[1].sample.t, CredflareSpec.Liveness.gestureTimeoutMs)
        XCTAssertTrue(capture.isFinished)
        XCTAssertNil(capture.evidence(video: nil))
    }

    func testExpiredChallengeIsReported() throws {
        let capture = try LivenessCapture(challenge: challenge, provider: FakeFaceSignalProvider(script: []), clock: { ISO8601.parse("2026-11-20T23:06:00Z")! })
        XCTAssertTrue(capture.isExpired)
    }

    func testVisionNormalizerUsesContractConventions() {
        XCTAssertEqual(VisionSignalNormalizer.contractYaw(visionRadians: -0.5), -0.5 * 180 / .pi, accuracy: 1e-9)
        XCTAssertEqual(VisionSignalNormalizer.contractPitch(visionRadians: 0.3), -0.3 * 180 / .pi, accuracy: 1e-9)
        let box = VisionSignalNormalizer.contractBox(CGRect(x: 0.2, y: 0.1, width: 0.4, height: 0.5))
        XCTAssertEqual(box.x, 0.2, accuracy: 1e-9); XCTAssertEqual(box.y, 0.4, accuracy: 1e-9)
        var normalizer = VisionSignalNormalizer()
        for _ in 0..<VisionSignalNormalizer.baselineFrames { XCTAssertEqual(normalizer.eyeOpen(ratio: 0.3), 1, accuracy: 0.2) }
        XCTAssertEqual(normalizer.eyeBaseline, 0.3, accuracy: 1e-9)
        XCTAssertLessThan(normalizer.eyeOpen(ratio: 0.12), CredflareSpec.Liveness.thresholds["default"]!["eye_closed"]!)
        XCTAssertGreaterThan(normalizer.eyeOpen(ratio: 0.27), CredflareSpec.Liveness.thresholds["default"]!["eye_open_baseline"]!)
        for _ in 0..<VisionSignalNormalizer.baselineFrames { _ = normalizer.smile(ratio: 0.9) }
        XCTAssertEqual(normalizer.smile(ratio: 0.9), 0, accuracy: 1e-9)
        XCTAssertGreaterThan(normalizer.smile(ratio: 1.05), CredflareSpec.Liveness.thresholds["default"]!["smile"]!)
    }

    func testVisionProviderSignsOnARealPhotoWhenAvailable() throws {
        let photo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../../website/public/images/individuals-portrait.jpg").standardizedFileURL
        guard let source = CGImageSourceCreateWithURL(photo as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw XCTSkip("Sibling website photo not available") }
        let original = VisionFaceSignalProvider().sample(from: image, t: 0)
        XCTAssertEqual(original.faces, 1)
        XCTAssertLessThan(try XCTUnwrap(original.yaw), -20, "The person faces their own right")
        XCTAssertLessThan(try XCTUnwrap(original.pitch), -10, "The person looks down")
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.translateBy(x: CGFloat(image.width), y: 0); context.scaleBy(x: -1, y: 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let mirrored = VisionFaceSignalProvider().sample(from: context.makeImage()!, t: 0)
        XCTAssertGreaterThan(try XCTUnwrap(mirrored.yaw), 20)
        XCTAssertNotNil(original.eyeOpen); XCTAssertNotNil(original.smile)
    }
    func testSelfiePhotoIsCappedAndReplacesTheFrame() throws {
        let context = CGContext(data: nil, width: 3024, height: 4032, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 0.5, green: 0.4, blue: 0.3, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 3024, height: 4032))
        let original = NSMutableData()
        let destination = CGImageDestinationCreateWithData(original, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil); XCTAssertTrue(CGImageDestinationFinalize(destination))
        let resized = try XCTUnwrap(LivenessCapture.resizedJPEG(original as Data, maxPixel: LivenessCapture.selfieMaxPixel))
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(resized as CFData, nil)!, 0, nil)!
        XCTAssertEqual(max(image.width, image.height), 1600)
        XCTAssertEqual(image.width, 1200)

        let capture = try LivenessCapture(challenge: challenge, provider: FakeFaceSignalProvider(script: passingScript), clock: beforeExpiry)
        capture.replaceSelfie(resized)
        XCTAssertNil(capture.selfie)
        _ = run(capture, frames: passingScript.count)
        XCTAssertNotEqual(capture.selfie, resized)
        capture.replaceSelfie(resized)
        XCTAssertEqual(capture.evidence(video: nil)?.selfie, resized)
    }

    func testChallengeVideoIsScaledToAbout480p() {
        XCTAssertTrue(LivenessCapture.videoSize(width: 720, height: 1280) == (480, 854))
        XCTAssertTrue(LivenessCapture.videoSize(width: 480, height: 640) == (480, 640))
    }
    func testRejectionCodesCoverTheSpecAndKeepUnknownValues() {
        XCTAssertEqual(Set(CredflareSpec.ErrorCode.meanings.keys).count, 28)
        XCTAssertTrue(RejectionCode.phoneCodeInvalid.isKnown)
        XCTAssertTrue(RejectionCode.locationMock.isKnown)
        let unknown = RejectionCode(rawValue: "liveness.new_rule")
        XCTAssertFalse(unknown.isKnown)
        XCTAssertEqual(CredflareError.api(422, "m", code: unknown).code?.rawValue, "liveness.new_rule")
    }
}
