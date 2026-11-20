import Foundation

public struct FaceBox: Codable, Equatable, Sendable {
    public var x: Double, y: Double, w: Double, h: Double
    public init(x: Double, y: Double, w: Double, h: Double) { self.x = x; self.y = y; self.w = w; self.h = h }
}

public struct FaceSample: Codable, Equatable, Sendable {
    public var t: Int
    public var faces: Int
    public var box: FaceBox?
    public var eyeOpen: Double?
    public var smile: Double?
    public var yaw: Double?
    public var pitch: Double?
    public init(t: Int, faces: Int, box: FaceBox? = nil, eyeOpen: Double? = nil, smile: Double? = nil, yaw: Double? = nil, pitch: Double? = nil) {
        self.t = t; self.faces = faces; self.box = box; self.eyeOpen = eyeOpen; self.smile = smile; self.yaw = yaw; self.pitch = pitch
    }
    enum CodingKeys: String, CodingKey { case t, faces, box, eyeOpen = "eye_open", smile, yaw, pitch }
    func signal(_ name: String) -> Double? {
        switch name {
        case "eye_open": return eyeOpen
        case "smile": return smile
        case "yaw": return yaw
        case "pitch": return pitch
        default: return nil
        }
    }
}

public struct LivenessRules: Sendable {
    public var gestureTimeoutMs: Int
    public var faceLostResetMs: Int
    public var faceAreaMin: Double
    public var faceAreaMax: Double
    public var centerTolerance: Double
    public var faces: Int
    public var thresholds: [String: [String: Double]]
    public var gestures: [String: [SpecGestureStep]]

    public static let spec = LivenessRules(
        gestureTimeoutMs: CredflareSpec.Liveness.gestureTimeoutMs,
        faceLostResetMs: CredflareSpec.Liveness.faceLostResetMs,
        faceAreaMin: CredflareSpec.Liveness.positionFaceAreaMin,
        faceAreaMax: CredflareSpec.Liveness.positionFaceAreaMax,
        centerTolerance: CredflareSpec.Liveness.positionCenterTolerance,
        faces: CredflareSpec.Liveness.positionFaces,
        thresholds: CredflareSpec.Liveness.thresholds,
        gestures: CredflareSpec.Liveness.gestures
    )

    public func resolvedThresholds(_ provider: String) -> [String: Double] {
        (thresholds["default"] ?? [:]).merging(thresholds[provider] ?? [:]) { _, override in override }
    }
}

public enum PositionStatus: String, Sendable, CaseIterable {
    case noFace = "no_face", multipleFaces = "multiple_faces", tooSmall = "too_small", tooLarge = "too_large", offCenter = "off_center", ok

    public var copyKey: String {
        switch self {
        case .noFace: return CredflareSpec.CopyKey.livenessPositionNoFace
        case .multipleFaces: return CredflareSpec.CopyKey.livenessPositionOneFace
        case .tooSmall: return CredflareSpec.CopyKey.livenessPositionMoveCloser
        case .tooLarge: return CredflareSpec.CopyKey.livenessPositionMoveFurther
        case .offCenter: return CredflareSpec.CopyKey.livenessPositionCenter
        case .ok: return CredflareSpec.CopyKey.livenessPositionReady
        }
    }

    public static func of(_ sample: FaceSample, rules: LivenessRules = .spec) -> PositionStatus {
        if sample.faces == 0 { return .noFace }
        if sample.faces > rules.faces { return .multipleFaces }
        guard let box = sample.box else { return .noFace }
        let area = box.w * box.h
        if area < rules.faceAreaMin { return .tooSmall }
        if area > rules.faceAreaMax { return .tooLarge }
        if abs(box.x + box.w / 2 - 0.5) > rules.centerTolerance || abs(box.y + box.h / 2 - 0.5) > rules.centerTolerance { return .offCenter }
        return .ok
    }
}

public enum EngineState: String, Sendable { case running, pass, timeout }

public struct PositionGate: Sendable {
    public struct Result: Equatable, Sendable { public let state: EngineState; public let status: PositionStatus }
    private let rules: LivenessRules
    private var start: Int?
    private(set) public var finished = false
    public init(rules: LivenessRules = .spec) { self.rules = rules }

    public mutating func push(_ sample: FaceSample) -> Result {
        precondition(!finished, "Position gate already finished")
        if start == nil { start = sample.t }
        let status = PositionStatus.of(sample, rules: rules)
        if sample.t - start! >= rules.gestureTimeoutMs { finished = true; return Result(state: .timeout, status: status) }
        if status == .ok { finished = true; return Result(state: .pass, status: status) }
        return Result(state: .running, status: status)
    }
}

public struct GestureRun: Sendable {
    public struct Result: Equatable, Sendable { public let state: EngineState; public let step: Int; public let tracked: Bool }
    public let gesture: String
    private let steps: [SpecGestureStep]
    private let thresholds: [String: Double]
    private let timeoutMs: Int
    private let resetMs: Int
    private var start: Int?
    private var prevT: Int?
    private var lostSince: Int?
    private var count = 0
    private(set) public var index = 0
    private(set) public var finished = false
    public var stepCount: Int { steps.count }

    public init(gesture: String, provider: String = "default", rules: LivenessRules = .spec) throws {
        guard let steps = rules.gestures[gesture], !steps.isEmpty else { throw CredflareError.validation("Unknown gesture \(gesture).") }
        self.gesture = gesture; self.steps = steps
        thresholds = rules.resolvedThresholds(provider)
        timeoutMs = rules.gestureTimeoutMs; resetMs = rules.faceLostResetMs
    }

    private func resolve(_ value: String) -> Double? { thresholds[value] ?? Double(value) }

    private func test(_ step: SpecGestureStep, _ sample: FaceSample) -> Bool {
        guard let s = sample.signal(step.signal), let v = resolve(step.value) else { return false }
        switch step.op {
        case "gt": return s > v
        case "lt": return s < v
        case "lt_neg": return s < -v
        case "abs_lt": return abs(s) < v
        default: return false
        }
    }

    public mutating func push(_ sample: FaceSample) -> Result {
        precondition(!finished, "Gesture run already finished")
        if start == nil { start = sample.t }
        if sample.t - start! >= timeoutMs { finished = true; return Result(state: .timeout, step: index, tracked: sample.faces == 1) }
        let gap = prevT.map { sample.t - $0 >= resetMs } ?? false
        prevT = sample.t
        if sample.faces != 1 {
            count = 0
            if lostSince == nil { lostSince = sample.t }
            if sample.t - lostSince! >= resetMs { index = 0 }
            return Result(state: .running, step: index, tracked: false)
        }
        if gap || lostSince.map({ sample.t - $0 >= resetMs }) == true { index = 0; count = 0 }
        lostSince = nil
        let step = steps[index]
        if test(step, sample) {
            count += 1
            let hold = step.holdFrames.flatMap(resolve).map { Int($0) } ?? 1
            if count >= hold {
                index += 1; count = 0
                if index == steps.count { finished = true; return Result(state: .pass, step: index, tracked: true) }
            }
        } else {
            count = 0
        }
        return Result(state: .running, step: index, tracked: true)
    }
}

public struct LivenessTrace: Decodable, Sendable {
    public let gesture: String
    public let provider: String?
    public let expect: String
    public let expectStatus: String?
    public let description: String?
    public let samples: [FaceSample]
    enum CodingKeys: String, CodingKey { case gesture, provider, expect, expectStatus = "expect_status", description, samples }
    public init(gesture: String, provider: String?, expect: String = "pass", expectStatus: String? = nil, description: String? = nil, samples: [FaceSample]) {
        self.gesture = gesture; self.provider = provider; self.expect = expect; self.expectStatus = expectStatus; self.description = description; self.samples = samples
    }

    public struct Outcome: Equatable, Sendable { public let outcome: String; public let status: PositionStatus?; public let t: Int? }

    public func run(rules: LivenessRules = .spec) throws -> Outcome {
        if gesture == "position" {
            var gate = PositionGate(rules: rules)
            var last: PositionGate.Result?
            for sample in samples {
                last = gate.push(sample)
                if last!.state != .running { return Outcome(outcome: last!.state.rawValue, status: last!.status, t: sample.t) }
            }
            return Outcome(outcome: "fail", status: last?.status, t: nil)
        }
        var run = try GestureRun(gesture: gesture, provider: provider ?? "default", rules: rules)
        for sample in samples {
            let result = run.push(sample)
            if result.state != .running { return Outcome(outcome: result.state.rawValue, status: nil, t: sample.t) }
        }
        return Outcome(outcome: "fail", status: nil, t: nil)
    }
}
