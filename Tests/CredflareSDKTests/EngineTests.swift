import XCTest
import CoreVideo
import ImageIO
@testable import CredflareSDK

final class EngineTests: XCTestCase {
    func traces() throws -> [(String, LivenessTrace)] {
        let directory = Bundle.module.url(forResource: "liveness-traces", withExtension: nil, subdirectory: "Fixtures")!
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try files.map { ($0.lastPathComponent, try JSONDecoder().decode(LivenessTrace.self, from: Data(contentsOf: $0))) }
    }

    func testEveryTraceEndsWithItsExpectedOutcome() throws {
        let all = try traces()
        XCTAssertEqual(all.count, 33)
        for (file, trace) in all {
            let outcome = try trace.run()
            XCTAssertEqual(outcome.outcome, trace.expect, file)
            if let status = trace.expectStatus { XCTAssertEqual(outcome.status?.rawValue, status, file) }
        }
    }

    func testFaceLostResetTracesFailOnlyBecauseOfTheResetRule() throws {
        var rules = LivenessRules.spec
        rules.faceLostResetMs = Int.max / 2
        let reset = try traces().filter { $0.0.contains("_reset_") }
        XCTAssertGreaterThanOrEqual(reset.count, 3)
        for (file, trace) in reset { XCTAssertEqual(try trace.run(rules: rules).outcome, "pass", file) }
    }

    func testProviderOverridesChangeTheOutcome() throws {
        let all = Dictionary(uniqueKeysWithValues: try traces())
        let mediapipe = all["smile_mediapipe_pass.json"]!, mlkit = all["smile_mlkit_fail.json"]!
        func asDefault(_ trace: LivenessTrace) -> LivenessTrace { LivenessTrace(gesture: trace.gesture, provider: "default", samples: trace.samples) }
        XCTAssertEqual(try asDefault(mediapipe).run().outcome, "fail")
        XCTAssertEqual(try asDefault(mlkit).run().outcome, "pass")
        XCTAssertEqual(LivenessRules.spec.resolvedThresholds("vision"), LivenessRules.spec.resolvedThresholds("default"))
        XCTAssertEqual(LivenessRules.spec.resolvedThresholds("unknown"), LivenessRules.spec.resolvedThresholds("default"))
    }

    func testPositionStatusesMapToSpecCopy() {
        for status in PositionStatus.allCases { XCTAssertNotNil(CredflareSpec.Copy.en[status.copyKey], status.rawValue) }
        for gesture in CredflareSpec.Liveness.gestureNames { XCTAssertNotNil(CredflareSpec.Copy.en[LivenessSequence.promptKey(for: gesture)], gesture) }
    }

    func testUnknownGestureIsRejected() {
        XCTAssertThrowsError(try GestureRun(gesture: "wink"))
        XCTAssertThrowsError(try LivenessSequence(gestures: ["blink", "wink"], provider: "vision"))
        XCTAssertThrowsError(try LivenessSequence(gestures: [], provider: "vision"))
    }
}
