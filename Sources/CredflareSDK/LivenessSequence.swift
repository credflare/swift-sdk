import Foundation

public final class LivenessSequence {
    public enum Phase: Equatable, Sendable {
        case positioning(PositionStatus)
        case gesture(index: Int, name: String, tracked: Bool)
        case timedOut(gesture: String?)
        case completed
    }
    public enum Event: Equatable, Sendable {
        case none
        case positionPassed
        case gesturePassed(index: Int, gesture: String, isLast: Bool)
        case timeout
    }

    public let gestures: [String]
    public let provider: String
    private let rules: LivenessRules
    private let clock: () -> Date
    private var gate: PositionGate
    private var run: GestureRun?
    private(set) public var phase: Phase = .positioning(.noFace)
    private(set) public var results: [LivenessResult] = []
    private(set) public var faceDetection = FaceDetectionSummary(detected: false, faceCount: 0, isCentered: false, isCorrectSize: false)

    public init(gestures: [String], provider: String, rules: LivenessRules = .spec, clock: @escaping () -> Date = Date.init) throws {
        guard !gestures.isEmpty else { throw CredflareError.validation("The challenge has no gestures.") }
        for gesture in gestures where rules.gestures[gesture] == nil { throw CredflareError.validation("Unknown gesture \(gesture).") }
        self.gestures = gestures; self.provider = provider; self.rules = rules; self.clock = clock
        gate = PositionGate(rules: rules)
    }

    public var currentGestureIndex: Int? { if case .gesture(let index, _, _) = phase { return index }; return nil }

    public func push(_ sample: FaceSample) -> Event {
        switch phase {
        case .timedOut, .completed:
            return .none
        case .positioning:
            let result = gate.push(sample)
            switch result.state {
            case .running:
                phase = .positioning(result.status); return .none
            case .timeout:
                phase = .timedOut(gesture: nil); return .timeout
            case .pass:
                faceDetection = FaceDetectionSummary(detected: true, faceCount: sample.faces, isCentered: true, isCorrectSize: true)
                run = try? GestureRun(gesture: gestures[0], provider: provider, rules: rules)
                phase = .gesture(index: 0, name: gestures[0], tracked: true)
                return .positionPassed
            }
        case .gesture(let index, let name, _):
            guard var current = run else { return .none }
            let result = current.push(sample)
            run = current
            switch result.state {
            case .running:
                phase = .gesture(index: index, name: name, tracked: result.tracked); return .none
            case .timeout:
                phase = .timedOut(gesture: name); return .timeout
            case .pass:
                results.append(LivenessResult(challenge: name, completed: true, timestamp: ISO8601.format(clock())))
                let next = index + 1
                if next == gestures.count { phase = .completed; run = nil; return .gesturePassed(index: index, gesture: name, isLast: true) }
                run = try? GestureRun(gesture: gestures[next], provider: provider, rules: rules)
                phase = .gesture(index: next, name: gestures[next], tracked: true)
                return .gesturePassed(index: index, gesture: name, isLast: false)
            }
        }
    }

    public static func promptKey(for gesture: String) -> String { "liveness.gesture.\(gesture)" }
}
